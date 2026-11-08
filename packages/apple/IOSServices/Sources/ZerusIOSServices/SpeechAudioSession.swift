@preconcurrency import AVFoundation
import Foundation

/// One app-wide capture lease. A late cleanup can only release its own session,
/// and a following capture waits until the system acknowledges deactivation.
actor SpeechAudioSession {
  static let shared = SpeechAudioSession()
  private static let queue = DispatchQueue(label: "com.zerus.speech.audio-session")
  private var owner: UUID?
  private var activation: Task<Void, Error>?
  private var cleanup: (id: UUID, task: Task<Void, Never>)?

  func acquire(_ id: UUID) async throws {
    if let previous = cleanup {
      await previous.task.value
      finishRelease(previous.id)
    }
    try Task.checkCancellation()
    guard owner == nil else { throw SpeechRecognitionError.alreadyListening }
    owner = id
    let operation = Task { try await Self.activateSystem() }
    activation = operation
    do {
      try await operation.value
      try Task.checkCancellation()
      guard owner == id, cleanup == nil else { throw CancellationError() }
    } catch {
      await release(id)
      throw error
    }
  }

  func release(_ id: UUID) async {
    guard owner == id else { return }
    if let pending = cleanup {
      await pending.task.value
      finishRelease(id)
      return
    }
    let pendingActivation = activation
    let operation = Task {
      // Failed activation never owns an active session to deactivate.
      do { try await pendingActivation?.value } catch { return }
      await Self.deactivateSystem()
    }
    cleanup = (id, operation)
    await operation.value
    finishRelease(id)
  }

  private func finishRelease(_ id: UUID) {
    guard owner == id else { return }
    owner = nil; activation = nil; cleanup = nil
  }

  private static func activateSystem() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        let session = AVAudioSession.sharedInstance()
        do {
          try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
          if #available(iOS 27.0, *) {
            session.activate(options: []) { active, error in
              if let error { continuation.resume(throwing: error) }
              else if active { continuation.resume() }
              else { continuation.resume(throwing: SpeechRecognitionError.microphoneUnavailable) }
            }
          } else {
            try session.setActive(true)
            continuation.resume()
          }
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private static func deactivateSystem() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      queue.async {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
          session.deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in continuation.resume() }
        } else {
          try? session.setActive(false, options: .notifyOthersOnDeactivation)
          continuation.resume()
        }
      }
    }
  }
}
