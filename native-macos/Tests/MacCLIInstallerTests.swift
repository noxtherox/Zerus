import XCTest
@testable import Zerus_Native

final class MacCLIInstallerTests: XCTestCase {
    func testBundledCLIInstallsRunsAndSharesDesktopSkillLocationsAndExports() async throws {
        try await withInstallation { home, resources, installer in
            let initial = try await installer.status()
            XCTAssertFalse(initial.installed); XCTAssertFalse(initial.onPath)
            let review = try await installer.prepare(.executable)
            XCTAssertEqual(review.destination, home.appendingPathComponent(".local/bin/zerus")); XCTAssertNil(review.before)
            try await installer.install(review)
            let installed = try await installer.status()
            XCTAssertTrue(installed.installed); XCTAssertTrue(installed.matches); XCTAssertTrue(installed.onPath)
            let process = Process(), output = Pipe()
            process.executableURL = review.destination; process.arguments = ["--version"]; process.standardOutput = output
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "zerus " + installed.version)
            let locations: [(MacCLIAgent, String)] = [(.codex, ".agents/skills/zerus/SKILL.md"), (.claude, ".claude/skills/zerus/SKILL.md"), (.hermes, ".hermes/skills/note-taking/zerus/SKILL.md")]
            let skill = try Data(contentsOf: resources.appendingPathComponent("SKILL.md"))
            for (agent, relative) in locations {
                let review = try await installer.prepare(.skill(agent))
                XCTAssertEqual(review.destination, home.appendingPathComponent(relative))
                try await installer.install(review)
                XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent(relative)), skill)
                XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: review.destination.path)[.posixPermissions] as? NSNumber)?.intValue, 0o644)
            }
            let ready = try await installer.status(); XCTAssertTrue(ready.skills.allSatisfy(\.matches))
            let exported = home.appendingPathComponent("Zerus export.md")
            let exportReview = try await installer.prepare(.export(exported)); try await installer.install(exportReview)
            XCTAssertEqual(try Data(contentsOf: exported), skill)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: exported.path)
            let replaceExport = try await installer.prepare(.export(exported)); try await installer.install(replaceExport)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: exported.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600, "Replacing a private export must keep its permissions")
            let reinstall = try await installer.prepare(.executable); XCTAssertNotNil(reinstall.before)
            try await installer.install(reinstall)
            XCTAssertTrue(try FileManager.default.attributesOfItem(atPath: review.destination.path)[.posixPermissions] as? Int == 0o755)
        }
    }
    func testUnusualInstallEntriesDoNotBlockOtherInstallActions() async throws {
        let targets: [MacCLIInstallReview.Kind] = [.executable] + MacCLIAgent.allCases.map { .skill($0) }
        for kind in targets { for symlink in [true, false] {
            try await withInstallation { home, _, installer in
                let target = try await installer.prepare(kind)
                try FileManager.default.createDirectory(at: target.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if symlink {
                    let other = home.appendingPathComponent("Dotfile source"); try Data("Keep linked source".utf8).write(to: other)
                    try FileManager.default.createSymbolicLink(at: target.destination, withDestinationURL: other)
                } else {
                    FileManager.default.createFile(atPath: target.destination.path, contents: Data())
                    let file = try FileHandle(forWritingTo: target.destination)
                    let limit = { if case .executable = kind { return 50 * 1024 * 1024 }; return 1024 * 1024 }()
                    try file.truncate(atOffset: UInt64(limit + 1)); try file.close()
                }
                do {
                    let status = try await installer.status(); XCTAssertFalse(status.version.isEmpty)
                    if case .skill(let agent) = kind {
                        XCTAssertNotNil(status.skills.first { $0.agent == agent }?.issue)
                        XCTAssertNil(status.issue)
                        XCTAssertTrue(status.skills.filter { $0.agent != agent }.allSatisfy { $0.issue == nil })
                    } else { XCTAssertNotNil(status.issue); XCTAssertTrue(status.skills.allSatisfy { $0.issue == nil }) }
                    let other: MacCLIInstallReview.Kind = { if case .executable = kind { return .skill(.codex) }; return .executable }()
                    let review = try await installer.prepare(other); try await installer.install(review)
                    let ready = try await installer.status()
                    if case .executable = kind { XCTAssertTrue(ready.skills.first { $0.agent == .codex }?.matches == true) }
                    else { XCTAssertTrue(ready.matches) }
                } catch { XCTFail("One unusual destination must not block other install actions: " + error.localizedDescription) }
            }
        } }
    }
    func testInstallationRefusesChangedDestinationsSymlinksAndDamagedBundleWithoutRunningUnknownCLI() async throws {
        try await withInstallation { home, resources, installer in
            do { _ = try await installer.prepare(.export(home.appendingPathComponent("Invalid.txt"))); XCTFail("Skill export needs a Markdown destination") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Markdown (.md)"), error.localizedDescription) }
            let review = try await installer.prepare(.executable)
            try FileManager.default.createDirectory(at: review.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let marker = home.appendingPathComponent("unexpected-execution")
            let script = "#!/bin/sh\ntouch '" + marker.path.replacingOccurrences(of: "'", with: "'\\''") + "'\nprintf 'zerus unknown\\n'\n"
            try Data(script.utf8).write(to: review.destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: review.destination.path)
            let status = try await installer.status()
            XCTAssertTrue(status.installed); XCTAssertFalse(status.matches)
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Merely reading installation status must not run a different executable")
            do { try await installer.install(review); XCTFail("Newer writing at the reviewed destination must survive") }
            catch { XCTAssertTrue(error.localizedDescription.contains("destination changed after review"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: review.destination), Data(script.utf8))
            try FileManager.default.removeItem(at: review.destination)
            let other = home.appendingPathComponent("Other executable"); try Data("Keep other file".utf8).write(to: other)
            try FileManager.default.createSymbolicLink(at: review.destination, withDestinationURL: other)
            do { _ = try await installer.prepare(.executable); XCTFail("Do not install through a destination symlink") }
            catch { XCTAssertTrue(error.localizedDescription.contains("not an ordinary file"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: other), Data("Keep other file".utf8))
            try FileManager.default.removeItem(at: review.destination)
            for name in ["SKILL.md", "zerus", "manifest.json"] {
                let url = resources.appendingPathComponent(name), original = try Data(contentsOf: url)
                let damaged: Data
                if name == "manifest.json" {
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any]); object["schemaVersion"] = 2
                    damaged = try JSONSerialization.data(withJSONObject: object)
                } else { damaged = Data("Damaged bundled asset".utf8) }
                try damaged.write(to: url)
                do { _ = try await installer.prepare(.skill(.claude)); XCTFail("An altered or unsupported bundled asset must not be installed") }
                catch { XCTAssertTrue(error.localizedDescription.contains("bundled command-line tools are incomplete or changed"), error.localizedDescription) }
                try original.write(to: url)
            }
        }
    }
    private func withInstallation(_ operation: (URL, URL, MacCLIInstaller) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-CLI-install-" + UUID().uuidString)
        let home = root.appendingPathComponent("home"), resources = root.appendingPathComponent("CLI")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("CLI")
        try FileManager.default.copyItem(at: source, to: resources)
        let installer = MacCLIInstaller(home: home, resources: resources, searchPath: home.appendingPathComponent(".local/bin").path)
        try await operation(home, resources, installer)
    }
}
