import ZerusIOSServices
import Foundation
import Combine
import AVFoundation
import UIKit

struct NativeDictationDraft {
    let id = UUID()
    let workspace: UUID
    let conversationID: String
    let prefix: String
    var lastWritten: String
    init(workspace: UUID, conversationID: String, prefix: String) {
        self.workspace = workspace; self.conversationID = conversationID
        self.prefix = prefix; lastWritten = prefix
    }
}

@MainActor
final class NativeDictationController: ObservableObject {
    enum Phase {
        case idle, preparing, listening, finishing
        var label: String {
            switch self {
            case .idle: "Dictation"
            case .preparing: "Preparing on-device dictation… Models may download."
            case .listening: "Listening on this device…"
            case .finishing: "Finishing dictation…"
            }
        }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var issue: String?
    @Published private(set) var needsSettings = false
    var active: Bool { phase != .idle }
    private static weak var activeOwner: NativeDictationController?
    private var operation: Task<Void, Never>?
    private var recognizer: ModernOnDeviceSpeechRecognizer?
    private var watches: [AnyCancellable] = []
    private var stopRequested = false

    func start(chat: NativeChat, vault: VaultStore, workspace: UUID) {
        guard !active, !chat.running, !chat.agent.running, vault.workspaceID == workspace, !vault.switchingVault else { return }
        guard Self.activeOwner?.active != true else { issue = "Dictation is already active in another window. Stop it there before starting here."; return }
        guard let lease = chat.beginDictation(workspace: workspace) else { issue = "This prompt cannot be recorded over. Save or share its existing draft first."; return }
        Self.activeOwner = self
        phase = .preparing; issue = nil; needsSettings = false; stopRequested = false
        let engine = ModernOnDeviceSpeechRecognizer(); recognizer = engine
        watches = [vault.$workspaceID.dropFirst().sink { [weak self] value in if value != workspace { self?.cancel() } }]
        for name in [UIApplication.didEnterBackgroundNotification, AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification] {
            watches.append(NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.cancel() })
        }
        watches.append(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).receive(on: DispatchQueue.main).sink { [weak self] note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self?.cancel() }
        })
        watches.append(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: DispatchQueue.main).sink { [weak self] note in
            guard self?.phase == .listening, let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            let changes = [AVAudioSession.RouteChangeReason.oldDeviceUnavailable, .newDeviceAvailable, .noSuitableRouteForCategory, .override]
            if changes.contains(where: { $0.rawValue == reason }) { self?.cancel() }
        })
        operation = Task { [weak self, weak chat, weak vault] in
            guard let self else { return }
            defer {
                chat?.endDictation(lease)
                self.recognizer = nil; self.watches = []; self.phase = .idle; self.operation = nil
                if Self.activeOwner === self { Self.activeOwner = nil }
            }
            do {
                try Task.checkCancellation()
                try await engine.start(localeIdentifier: Locale.current.identifier)
                try Task.checkCancellation()
                guard let chat, let vault, vault.workspaceID == workspace else { throw CancellationError() }
                self.phase = .listening
                let deadline = ProcessInfo.processInfo.systemUptime + 300
                while !self.stopRequested, ProcessInfo.processInfo.systemUptime < deadline {
                    try Task.checkCancellation()
                    guard vault.workspaceID == workspace else { throw CancellationError() }
                    let progress = engine.progress()
                    if !chat.acceptDictation(progress.transcript, id: lease, workspace: workspace) {
                        throw VaultFailure(message: "Dictation stopped because the prompt changed. Your newer text was kept.")
                    }
                    if !progress.listening { break }
                    try await Task.sleep(for: .milliseconds(150))
                }
                try Task.checkCancellation()
                self.phase = .finishing
                let final = try await engine.stop()
                try Task.checkCancellation()
                guard vault.workspaceID == workspace else { throw CancellationError() }
                guard chat.acceptDictation(final, id: lease, workspace: workspace) else { throw VaultFailure(message: "Dictation stopped because the prompt changed. Your newer text was kept.") }
            } catch {
                if !(error is CancellationError), !Task.isCancelled {
                    self.issue = error.localizedDescription
                    if let permission = error as? SpeechRecognitionError {
                        switch permission { case .speechPermissionDenied, .microphonePermissionDenied: self.needsSettings = true; default: break }
                    }
                }
            }
            await engine.cancel()
        }
    }
    func stop() { guard phase == .listening else { return }; stopRequested = true; phase = .finishing }
    func cancel() {
        guard active else { return }
        phase = .finishing; operation?.cancel()
        let engine = recognizer
        Task { await engine?.cancel() }
        // Keep the global audio lease until the pending start/finalization has
        // actually returned, so an older cleanup cannot deactivate a new capture.
    }
    func promptChanged() {
        guard active else { return }
        issue = "Dictation stopped because the prompt changed. Your newer text was kept."; cancel()
    }
    func dismissIssue() { issue = nil; needsSettings = false }
}
