import Foundation
import SwiftUI

/// The shared on-device AI controller (`native-ios/Sources/NativeLocalAI.swift`).
typealias MacLocalAI = NativeLocalAI

extension MacWorkspace: LocalAIVaultSource {
    var localAINotes: [NoteDocument] { noteSearchSources().notes }
}

/// Mac windows' open AI action sheets, keyed by workspace.
@MainActor @Observable final class MacLocalAIPresentation {
    static let shared = MacLocalAIPresentation()
    var requests: [UUID: MacLocalAIRequest] = [:]
}

/// Keeps the current vault's index in step with its notes (debounced).
struct MacLocalAIIndexing: ViewModifier {
    let store: MacWorkspace
    @State private var pending: Task<Void, Never>?
    private var ai: MacLocalAI { .shared }

    func body(content: Content) -> some View {
        content
            .onChange(of: store.notes) { schedule() }
            .onChange(of: store.root) { schedule(delay: .zero) }
            .onChange(of: ai.installed) { schedule(delay: .zero) }
            .onAppear { schedule(delay: .seconds(2)) }
    }

    private func schedule(delay: Duration = .seconds(3)) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, store.root != nil else { return }
            ai.sync(store)
        }
    }
}
