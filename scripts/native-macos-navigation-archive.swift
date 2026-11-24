import AppKit
import CryptoKit
import Foundation

/// Compile with native-macos/Sources/MacNavigationArchive.swift. This is an
/// offline maintenance command, not a vault writer or an automatic deletion job.
@main struct NativeNavigationArchiveCommand {
    struct Entry { let key: String; let data: Data; let root: String }
    static let domain = "com.zerus.notes.macos.native"
    static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func aliases(_ path: String) -> Set<String> {
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        var result = Set([path, canonical])
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var")) == "private/var" {
            for value in [path, canonical] {
                if value.hasPrefix("/private/var/") { result.insert(String(value.dropFirst(8))) }
                else if value.hasPrefix("/var/") { result.insert("/private" + value) }
            }
        }
        return result
    }
    static func temporaryRoots() throws -> [String] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/getconf"); process.arguments = ["DARWIN_USER_TEMP_DIR"]; process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("Cannot establish this user's temporary directory.") }
        let raw = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases(URL(fileURLWithPath: raw).standardizedFileURL.path).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "ZerusNavigationArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    @MainActor static func requireStopped() throws {
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == domain }) else {
            throw failure("Quit every Zerus Native application before applying or restoring navigation archives.")
        }
    }
    static func candidates(_ values: [String: Any], temporary: [String]) -> [Entry] {
        let recent = Set((values["zerus.mac.recentVaults"] as? [String] ?? []).flatMap(aliases))
        var entries: [String: Entry] = [:]
        for (bookmarkKey, value) in values where bookmarkKey.hasPrefix("zerus.mac.bookmark.") {
            guard let data = value as? Data else { continue }
            var stale = false
            guard (try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)) == nil,
                  let raw = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?.allValues[.pathKey] as? String, raw.hasPrefix("/") else { continue }
            let path = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path, paths = aliases(raw)
            guard temporary.contains(where: { path.hasPrefix($0) }), !FileManager.default.fileExists(atPath: path),
                  paths.isDisjoint(with: recent), paths.contains(where: { bookmarkKey == "zerus.mac.bookmark." + hash($0) }) else { continue }
            for path in paths {
                let key = "zerus.mac.navigation.v1." + hash(path)
                guard let bytes = values[key] as? Data,
                      let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], object["version"] as? Int == 1 else { continue }
                entries[key] = .init(key: key, data: bytes, root: raw)
            }
        }
        return entries.values.sorted { $0.key < $1.key }
    }
    @MainActor static func main() {
        do { try run() }
        catch { FileHandle.standardError.write(Data(("error: " + error.localizedDescription + "\n").utf8)); exit(1) }
    }
    @MainActor static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, ["plan", "apply", "restore"].contains(arguments[1]) else {
            throw failure("Usage: navigation-archive plan|apply|restore <report-directory> <supporting-app>")
        }
        let mode = arguments[1], report = URL(fileURLWithPath: arguments[2], isDirectory: true), app = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let defaults = UserDefaults(suiteName: domain)!, before = defaults.persistentDomain(forName: domain) ?? [:]
        let temporary = try temporaryRoots(), entries = candidates(before, temporary: temporary)
        if mode != "plan" {
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == domain, info?["ZerusNavigationArchiveVersion"] as? String == "1" else {
                throw failure("The supplied application does not declare support for navigation archives. Nothing was moved.")
            }
            try requireStopped()
        }
        try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var affected = Set<String>()
        if mode == "apply" {
            let backup = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.data) })
            let file = report.appendingPathComponent("navigation-backup.plist")
            try PropertyListSerialization.data(fromPropertyList: backup, format: .binary, options: 0).write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            for entry in entries {
                try requireStopped()
                let current = defaults.persistentDomain(forName: domain) ?? [:]
                guard !FileManager.default.fileExists(atPath: entry.root),
                      !(current["zerus.mac.recentVaults"] as? [String] ?? []).contains(where: { !aliases($0).isDisjoint(with: aliases(entry.root)) }) else {
                    throw failure("A candidate vault became available or recent. Remaining records were left in preferences.")
                }
                try MacNavigationArchive.archiveLegacy(entry.data, forKey: entry.key, defaults: defaults)
                affected.insert(entry.key)
            }
        } else if mode == "restore" {
            let backup = try PropertyListSerialization.propertyList(from: Data(contentsOf: report.appendingPathComponent("navigation-backup.plist")), format: nil) as? [String: Data]
            guard let backup else { throw failure("Invalid navigation backup.") }
            for (key, bytes) in backup {
                _ = try MacNavigationArchive.location(forKey: key)
                guard defaults.data(forKey: key) == nil else { continue } // Preserve all newer preference writes.
                try requireStopped(); defaults.set(bytes, forKey: key); affected.insert(key)
            }
        }
        defaults.synchronize()
        let after = defaults.persistentDomain(forName: domain) ?? [:]
        guard NSDictionary(dictionary: before.filter { !affected.contains($0.key) }).isEqual(to: after.filter { !affected.contains($0.key) }) else {
            throw failure("Unselected preferences changed concurrently. Inspect the report and backup before continuing.")
        }
        let eligible = Set(entries.map(\.key))
        let projected = before.filter { !eligible.contains($0.key) }
        let result: [String: Any] = ["mode": mode, "eligibleRecords": entries.count, "eligibleKeys": entries.map(\.key), "affectedRecords": affected.count,
            "estimatedDomainBytesAfterArchive": try PropertyListSerialization.data(fromPropertyList: projected, format: .binary, options: 0).count,
            "beforeBytes": try PropertyListSerialization.data(fromPropertyList: before, format: .binary, options: 0).count,
            "afterBytes": try PropertyListSerialization.data(fromPropertyList: after, format: .binary, options: 0).count,
            "otherEntriesUnchanged": true, "keys": affected.sorted()]
        let file = report.appendingPathComponent(mode + ".json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        print("\(mode): \(entries.count) eligible; \(affected.count) affected. Other preferences preserved.")
    }
}
