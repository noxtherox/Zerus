import XCTest
import SwiftUI
@testable import Zerus_Native

/// Opt-in: opens every note of `TEST_RUNNER_ZERUS_RENDER_VAULT` in a hosted
/// workspace window and prints one line per note (editor mode, body and
/// rendered-text digests, open time) so two builds can be compared.
@MainActor
final class MacVaultRenderCheckTests: XCTestCase {
    func testEveryNoteOpensAndRenders() async throws {
        guard let path = ProcessInfo.processInfo.environment["ZERUS_RENDER_VAULT"] else { throw XCTSkip("Set TEST_RUNNER_ZERUS_RENDER_VAULT.") }
        let store = MacWorkspace()
        await store.openVault(URL(fileURLWithPath: path))
        let host = NSHostingView(rootView: MacWorkspaceView(store: store))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func settle() async throws { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) } }
        func editor(_ node: NSView) -> NSTextView? {
            if let text = node as? NSTextView, text.isEditable { return text }
            return node.subviews.lazy.compactMap(editor).first
        }
        try await settle()
        var problems: [String] = []
        for note in store.regularNotes.sorted(by: { $0.path < $1.path }) {
            let start = ContinuousClock.now
            await store.openNote(note.path)
            try await settle()
            let elapsed = start.duration(to: .now)
            let shown = editor(host)?.string ?? "<no editor>"
            if store.selection != note.path { problems.append(note.path + ": not selected") }
            if let issue = store.issue { problems.append(note.path + ": " + issue); store.issue = nil }
            if store.body != note.parts.body { problems.append(note.path + ": body differs from saved note") }
            print("ZRENDER \(note.path)|source=\(store.sourceMode)|body=\(NativeHistory.hash(store.body).prefix(12))|shown=\(NativeHistory.hash(shown).prefix(12))|chars=\(shown.count)|ms=\(elapsed.components.attoseconds / 1_000_000_000_000_000 + elapsed.components.seconds * 1000)")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        // Opening notes must not have written to the vault.
        for note in store.regularNotes { XCTAssertFalse(store.isDirty, note.path) }
    }
}
