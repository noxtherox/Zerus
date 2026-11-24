import SwiftUI
import AppKit
import Combine
import Sparkle

/// Native appcasts and their signing key are supplied by the build. Do not
/// inherit the desktop web client's JSON feed or a defaults-based feed override.
struct MacUpdateChannel {
    let feed: URL
    enum Failure: Error { case unconfigured, invalid }
    init(bundle: Bundle = .main) throws {
        let raw = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty || !key.isEmpty else { throw Failure.unconfigured }
        guard let feed = URL(string: raw), feed.scheme == "https", let host = feed.host, !host.isEmpty,
              feed.user == nil, feed.password == nil, feed.fragment == nil,
              feed.path.lowercased().hasSuffix(".xml"),
              let bytes = Data(base64Encoded: key), bytes.count == 32, bytes.base64EncodedString() == key else { throw Failure.invalid }
        self.feed = feed
    }
}

@MainActor final class MacUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = MacUpdates()
    @Published private(set) var canCheck = true
    private var channel: MacUpdateChannel?
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var started = false
    func start() {
        guard !started else { return }; started = true
        do {
            channel = try MacUpdateChannel()
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            observation = controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }
            try controller.updater.start()
        } catch {
            observation = nil; controller = nil; channel = nil; canCheck = true
        }
    }
    func check() {
        start()
        if let controller { controller.checkForUpdates(nil) }
        else {
            let alert = NSAlert()
            alert.messageText = "Updates unavailable in this build"
            alert.informativeText = "This preview does not have a native update channel yet. Install a newer native build manually when it is available."
            alert.addButton(withTitle: "OK"); alert.runModal()
        }
    }
    func feedURLString(for updater: SPUUpdater) -> String? { channel?.feed.absoluteString }
}

struct MacCheckForUpdates: View {
    @ObservedObject private var updates = MacUpdates.shared
    var body: some View { Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck) }
}
