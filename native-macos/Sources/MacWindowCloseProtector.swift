import AppKit
import SwiftUI

/// Interpose only the close decision; preserve SwiftUI's window delegate callbacks.
@MainActor final class MacWindowCloseGuard: NSObject, NSWindowDelegate {
    private let workspace: MacWorkspace
    private weak var window: NSWindow?
    nonisolated(unsafe) private weak var original: NSWindowDelegate?
    private var pending: Task<Void, Never>?
    private var approved = false
    init(workspace: MacWorkspace, window: NSWindow) {
        self.workspace = workspace; self.window = window; self.original = window.delegate
        super.init(); window.delegate = self
    }
    func detach() {
        pending?.cancel(); pending = nil
        if let window, window.delegate === self { window.delegate = original }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if approved {
            let allowed = original?.windowShouldClose?(sender) ?? true
            // Preparation holds agent admission until the window really closes.
            // SwiftUI's original delegate can still keep the window open.
            if !allowed { workspace.agentController?.cancelLeaving() }
            return allowed
        }
        guard pending == nil else { return false }
        pending = Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            let controller = workspace.agentController
            let saved = await workspace.prepareToCloseWindow()
            pending = nil
            guard !Task.isCancelled, saved, sender.delegate === self else {
                if saved { controller?.cancelLeaving() }
                return
            }
            approved = true; sender.performClose(nil); approved = false
        }
        return false
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? { original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector) }
}

struct MacWindowCloseProtector: NSViewRepresentable {
    let workspace: MacWorkspace
    func makeNSView(context: Context) -> Host { Host(workspace: workspace) }
    func updateNSView(_ view: Host, context: Context) { view.attach() }
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.protection?.detach() }
    final class Host: NSView {
        let workspace: MacWorkspace
        var protection: MacWindowCloseGuard?
        init(workspace: MacWorkspace) { self.workspace = workspace; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); attach()
            // SwiftUI may finish installing its own delegate after attaching content.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        func attach() {
            workspace.presentationWindow = window
            guard let window else { protection?.detach(); protection = nil; return }
            if let protection, window.delegate === protection { return }
            protection?.detach(); protection = MacWindowCloseGuard(workspace: workspace, window: window)
        }
    }
}
