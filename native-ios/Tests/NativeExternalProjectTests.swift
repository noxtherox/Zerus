import XCTest
import UIKit
@testable import ZerusNative

final class NativeExternalProjectTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeProject-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func image() throws -> Data {
        let value = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20)) }
        return try XCTUnwrap(value.pngData())
    }
    func testProjectSelectionImportsBinaryAttachmentsRebasesCopiesAndReopensWithoutChangingTheOriginalUntilSaved() async throws {
        let source = root.appendingPathComponent("Note.md"), original = Data("---\nforeign: 'Kept'\n---\n# Outside\n".utf8), png = try image()
        try original.write(to: source)
        let store = NativeExternalNotesStore(directory: root.appendingPathComponent("Private")), snapshot = try await store.open(selected: source)
        let project = try await store.mapProject(snapshot, selected: root)
        let markdown = "![A caption](assets/from-clipboard)\n\n`![literal](assets/not-a-file)`\n"
        let fragment = NativeClipboardFragment(markdown: markdown, resources: [.init(reference: "assets/from-clipboard", path: nil, name: "Spaced image.png", bytes: png)])
        let imported = try await project.importFragment(fragment), reference = try XCTUnwrap(MarkdownResources.localReferences(in: imported).first)
        XCTAssertTrue(reference.hasPrefix("./assets/")); XCTAssertTrue(reference.contains("Spaced%20image.png")); XCTAssertTrue(imported.contains("`![literal](assets/not-a-file)`"))
        let bytes = try await project.data(reference); XCTAssertEqual(bytes, png)
        XCTAssertEqual(try Data(contentsOf: source), original, "Importing clipboard files cannot write the Markdown before the editor accepts the paste")
        let copied = try await project.fragment(imported); XCTAssertTrue(copied.includesLocalResources); XCTAssertEqual(copied.resources.first?.bytes, png)
        let saved = try await store.save(snapshot, content: snapshot.content + "\n" + imported)
        let second = root.appendingPathComponent("Nested/Second.md"); try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("# Second\n".utf8).write(to: second)
        let secondSnapshot = try await store.open(selected: second), other = try await store.mapProject(secondSnapshot, selected: root)
        let rebased = try await other.importFragment(copied), secondRef = try XCTUnwrap(MarkdownResources.localReferences(in: rebased).first)
        XCTAssertTrue(secondRef.hasPrefix("../assets/")); let reused = try await other.data(secondRef); XCTAssertEqual(reused, png)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path).count, 1, "Same-project paste reuses an unchanged attachment")
        let restored = try await NativeExternalNotesStore(directory: root.appendingPathComponent("Private")).reopen(saved.entry.id)
        let restoredAccess = try await store.project(restored)
        let restoredProject = try XCTUnwrap(restoredAccess)
        let restoredBytes = try await restoredProject.data(reference); XCTAssertEqual(restoredBytes, png)
        let thumbnail = try await restoredProject.thumbnail(reference); XCTAssertGreaterThan(thumbnail.width, 0)
        XCTAssertTrue(String(decoding: try Data(contentsOf: source), as: UTF8.self).contains("foreign: 'Kept'")); XCTAssertFalse(String(decoding: try Data(contentsOf: source), as: UTF8.self).contains("zerus-id:"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus").path))
    }
    func testProjectCapabilitiesRejectOutsideLinksLinkedAttachmentDirectoriesAndMovedOrReplacedRoots() async throws {
        let projectRoot = root.appendingPathComponent("Project"), outside = root.appendingPathComponent("Outside"), png = try image()
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let source = projectRoot.appendingPathComponent("Note.md"); try Data("# Project\n".utf8).write(to: source)
        let original = outside.appendingPathComponent("Protected.png"); try png.write(to: original)
        let access = try NativeExternalProjectFiles(selectedProject: projectRoot, source: source)
        for reference in ["../Outside/Protected.png", original.absoluteString, "file://server" + original.path] {
            do { _ = try await access.data(reference); XCTFail("Outside resources cannot inherit project access") } catch {}
        }
        try FileManager.default.createSymbolicLink(at: projectRoot.appendingPathComponent("assets"), withDestinationURL: outside)
        let incoming = NativeClipboardFragment(markdown: "![Image](assets/new)", resources: [.init(reference: "assets/new", path: nil, name: "Image.png", bytes: png)])
        do { _ = try await access.importFragment(incoming); XCTFail("A linked attachment folder cannot authorize an outside write") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["Protected.png"]); XCTAssertEqual(try Data(contentsOf: original), png)
        let moved = root.appendingPathComponent("Moved"); try FileManager.default.moveItem(at: projectRoot, to: moved)
        do { _ = try await access.importFragment(incoming); XCTFail("An old capability cannot recreate a moved project") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.path))
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        do { _ = try await access.importFragment(incoming); XCTFail("A different folder at the old path cannot reuse the project grant") } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: projectRoot.path).isEmpty)
        XCTAssertEqual(String(decoding: try Data(contentsOf: moved.appendingPathComponent("Note.md")), as: UTF8.self), "# Project\n")
    }
}
