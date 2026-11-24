import Foundation
import Combine

@MainActor final class MacAgentRunDefaults: ObservableObject {
    @Published var mode = NativeAgentMode.review { didSet { if !applying { choseMode = true } } }
    @Published var writeScope = NativeAgentPreferences.WriteScope.context { didSet { if !applying { choseScope = true } } }
    @Published private(set) var snapshot: NativeAgentPreferencesSnapshot?
    @Published private(set) var ready = false
    @Published private(set) var loading = false
    @Published private(set) var issue: String?
    private var choseMode = false, choseScope = false, applying = false
    func load(_ workspace: MacAgentWorkspace, available: Bool) async {
        guard available else { ready = false; return }
        guard !loading else { return }
        loading = true; ready = false
        defer { loading = false }
        do {
            let next = try await workspace.preferences()
            applying = true
            if !choseMode { mode = next.value.mode.native }
            if !choseScope { writeScope = next.value.writeScope }
            applying = false
            snapshot = next; ready = true; issue = nil
        } catch { issue = error.localizedDescription }
    }
    func useSaved() {
        guard ready, let snapshot else { return }
        applying = true; mode = snapshot.value.mode.native; writeScope = snapshot.value.writeScope; applying = false
        choseMode = false; choseScope = false
    }
}
