import XCTest
import SwiftUI
import AppKit
@testable import Zerus_Native

@MainActor final class MacInterfaceTextTests: XCTestCase {
    /// Interface text resizes text only; fixed-size controls and the zoom
    /// transform stay untouched.
    func testInterfaceTextScalesTextIndependentlyOfZoomAndControls() throws {
        let suite = "Zerus-interface-text-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
            Text("Body text sample").fixedSize().background(Probe(name: "body"))
            Text("Caption sample").macFont(.caption.bold()).fixedSize().background(Probe(name: "caption"))
            Color.red.frame(width: 40, height: 20).background(Probe(name: "control"))
        }.modifier(MacInterfaceTextHost()).defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        func size(_ name: String) throws -> CGSize { try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == name }).bounds.size }
        var measured: [Int: (body: CGSize, caption: CGSize, control: CGSize)] = [:]
        for percentage in [100, 150, 80] {
            preferences.set(percentage, forKey: MacInterfaceText.key)
            preferences.set(100, forKey: "zerus.mac.interfaceZoom")
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            measured[percentage] = (try size("body"), try size("caption"), try size("control"))
        }
        let base = try XCTUnwrap(measured[100]), large = try XCTUnwrap(measured[150]), small = try XCTUnwrap(measured[80])
        XCTAssertGreaterThan(large.body.width, base.body.width * 1.3)
        XCTAssertGreaterThan(large.caption.width, base.caption.width * 1.3)
        XCTAssertLessThan(small.body.width, base.body.width * 0.9)
        XCTAssertEqual(large.control, base.control, "Interface text must not resize controls")
        XCTAssertEqual(MacInterfaceText.validated(42), 100)
    }
    private struct Probe: NSViewRepresentable {
        let name: String
        func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = .init(name); return view }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}
