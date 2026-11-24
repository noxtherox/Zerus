import Foundation
import CryptoKit
import Darwin

enum MacCLIAgent: String, CaseIterable, Sendable {
    case codex, claude, hermes
    var label: String { switch self { case .codex: return "Codex / Agent Skills"; case .claude: return "Claude"; case .hermes: return "Hermes" } }
    var directory: String { switch self { case .codex: return ".agents/skills/zerus"; case .claude: return ".claude/skills/zerus"; case .hermes: return ".hermes/skills/note-taking/zerus" } }
}
struct MacCLIStatus: Sendable {
    struct Skill: Identifiable, Sendable { let agent: MacCLIAgent; let path: URL; let installed: Bool; let matches: Bool; let issue: String?; var id: MacCLIAgent { agent } }
    let version: String
    let skillVersion: String
    let path: URL
    let installed: Bool
    let matches: Bool
    let onPath: Bool
    let issue: String?
    let skills: [Skill]
}
struct MacCLIInstallReview: Identifiable, Sendable {
    enum Kind: Sendable { case executable; case skill(MacCLIAgent); case export(URL) }
    let id = UUID()
    let kind: Kind
    let destination: URL
    let before: Data?
    let incoming: Data
    var label: String { switch kind { case .executable: return "Zerus CLI"; case .skill(let agent): return agent.label + " skill"; case .export: return "Zerus skill export" } }
}

/// Installation operates only after the UI reviews an exact destination snapshot.
/// Status never executes a pre-existing user executable to discover its version.
actor MacCLIInstaller {
    static let shared = MacCLIInstaller(home: FileManager.default.homeDirectoryForCurrentUser,
                                        resources: (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("CLI"),
                                        searchPath: ProcessInfo.processInfo.environment["PATH"] ?? "")
    private let home: URL
    private let resources: URL
    private let searchPath: String
    init(home: URL, resources: URL, searchPath: String) { self.home = home; self.resources = resources; self.searchPath = searchPath }
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let version: String
        let skillVersion: String
        let executableSha256: String
        let skillSha256: String
    }
    private func bytes(_ path: URL, limit: Int = 50 * 1024 * 1024) throws -> Data? {
        let info: [FileAttributeKey: Any]
        do { info = try FileManager.default.attributesOfItem(atPath: path.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
        guard info[.type] as? FileAttributeType == .typeRegular, ((info[.size] as? NSNumber)?.intValue ?? Int.max) <= limit else {
            throw VaultFailure(message: "The file at \(path.path) is not an ordinary file within the installation size limit. It was left unchanged.")
        }
        let value = try Data(contentsOf: path)
        guard value.count <= limit else { throw VaultFailure(message: "The installation file grew beyond its size limit. It was left unchanged.") }
        return value
    }
    private func bundled() throws -> (Manifest, Data, Data) {
        guard let raw = try bytes(resources.appendingPathComponent("manifest.json"), limit: 16 * 1024) else { throw VaultFailure(message: "The command-line tools are unavailable in this app build.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: raw)
        guard manifest.schemaVersion == 1, manifest.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              manifest.skillVersion.range(of: #"^\d+$"#, options: .regularExpression) != nil,
              let binary = try bytes(resources.appendingPathComponent("zerus")), let skill = try bytes(resources.appendingPathComponent("SKILL.md"), limit: 1024 * 1024),
              Self.hash(binary) == manifest.executableSha256, Self.hash(skill) == manifest.skillSha256 else {
            throw VaultFailure(message: "The bundled command-line tools are incomplete or changed. Reinstall this app before installing them.")
        }
        return (manifest, binary, skill)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private var executable: URL { home.appendingPathComponent(".local/bin/zerus") }
    private func destination(_ kind: MacCLIInstallReview.Kind) -> URL {
        switch kind { case .executable: return executable; case .skill(let agent): return home.appendingPathComponent(agent.directory).appendingPathComponent("SKILL.md"); case .export(let url): return url }
    }
    private func observed(_ path: URL, limit: Int = 50 * 1024 * 1024) -> (data: Data?, issue: String?) {
        do { return (try bytes(path, limit: limit), nil) }
        catch { return (nil, error.localizedDescription) }
    }
    func status() throws -> MacCLIStatus {
        let (manifest, binary, skill) = try bundled(), installed = observed(executable)
        let available = installed.data != nil && FileManager.default.isExecutableFile(atPath: executable.path)
        let onPath = available && searchPath.split(separator: ":", omittingEmptySubsequences: false).contains { part in
            guard !part.isEmpty else { return false }
            return URL(fileURLWithPath: String(part)).appendingPathComponent("zerus").resolvingSymlinksInPath().standardizedFileURL == executable.resolvingSymlinksInPath().standardizedFileURL
        }
        let skills = MacCLIAgent.allCases.map { agent -> MacCLIStatus.Skill in
            let path = destination(.skill(agent)), existing = observed(path, limit: 1024 * 1024)
            return .init(agent: agent, path: path, installed: existing.data != nil || existing.issue != nil, matches: existing.data == skill, issue: existing.issue)
        }
        return .init(version: manifest.version, skillVersion: manifest.skillVersion, path: executable, installed: installed.data != nil || installed.issue != nil,
                     matches: available && installed.data == binary, onPath: onPath, issue: installed.issue ?? (installed.data != nil && !available ? "This CLI file is not executable. Reinstall it to restore owner execute permission." : nil), skills: skills)
    }
    func prepare(_ kind: MacCLIInstallReview.Kind) throws -> MacCLIInstallReview {
        let (_, binary, skill) = try bundled(), path = destination(kind)
        if case .export = kind, path.pathExtension.lowercased() != "md" { throw VaultFailure(message: "Choose a Markdown (.md) file for the skill export.") }
        let incoming: Data
        if case .executable = kind { incoming = binary } else { incoming = skill }
        return .init(kind: kind, destination: path, before: try bytes(path), incoming: incoming)
    }
    func install(_ review: MacCLIInstallReview) throws {
        try Task.checkCancellation()
        guard review.destination == destination(review.kind), try bytes(review.destination) == review.before else {
            throw VaultFailure(message: "The installation destination changed after review. Refresh and review it again; nothing was replaced.")
        }
        let folder = review.destination.deletingLastPathComponent(), fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".zerus-install-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try review.incoming.write(to: temporary, options: .withoutOverwriting)
        let previousMode = (try? fm.attributesOfItem(atPath: review.destination.path)[.posixPermissions] as? NSNumber)?.intValue
        let permissions: Int
        if case .executable = review.kind { permissions = previousMode.map { ($0 & 0o777) | 0o100 } ?? 0o755 }
        else { permissions = previousMode.map { $0 & 0o777 } ?? 0o644 }
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        try Task.checkCancellation()
        guard try bytes(review.destination) == review.before else { throw VaultFailure(message: "The installation destination changed while preparing. Refresh and review it again; nothing was replaced.") }
        let result = review.before == nil
            ? Darwin.renamex_np(temporary.path, review.destination.path, UInt32(RENAME_EXCL))
            : Darwin.rename(temporary.path, review.destination.path)
        guard result == 0 else {
            if errno == EEXIST { throw VaultFailure(message: "The installation destination appeared while preparing. Refresh and review it again; nothing was replaced.") }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
