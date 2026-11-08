@preconcurrency import AVFoundation
import Speech

@MainActor
public final class OnDeviceSpeechRecognizer {
  public init() {}
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var tapInstalled = false
  private var transcript = ""
  private var recognitionError: Error?
  private var captureID: UUID?
  private var cancelRequested = false
  private var finalizing = false
  private var sessionStartTask: Task<Void, Error>?
  private var cleanupTask: Task<Void, Never>?

  public private(set) var isListening = false

  public func start(localeIdentifier: String?) async throws {
    guard captureID == nil else { throw SpeechRecognitionError.alreadyListening }
    let id = UUID(); captureID = id; cancelRequested = false
    do { try await startCapture(localeIdentifier: localeIdentifier, id: id) }
    catch { await finishCapture(id); throw error }
  }

  private func startCapture(localeIdentifier: String?, id: UUID) async throws {
    try checkCapture(id)

    guard await requestSpeechPermission() else {
      throw SpeechRecognitionError.speechPermissionDenied
    }
    try checkCapture(id)
    guard await requestMicrophonePermission() else {
      throw SpeechRecognitionError.microphonePermissionDenied
    }

    try checkCapture(id)
    let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw SpeechRecognitionError.unsupportedLocale(locale.identifier)
    }
    guard recognizer.supportsOnDeviceRecognition else {
      throw SpeechRecognitionError.onDeviceRecognitionUnavailable(locale.identifier)
    }

    transcript = ""
    recognitionError = nil

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.contextualStrings = ["Zerus"]
    recognitionRequest = request

    do {
      let activation = Task { try await SpeechAudioSession.shared.acquire(id) }
      sessionStartTask = activation
      try await activation.value
      try checkCapture(id)
      sessionStartTask = nil

      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw SpeechRecognitionError.microphoneUnavailable
      }

      input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
        request.append(buffer)
      }
      tapInstalled = true

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          guard let self, self.captureID == id, !self.cancelRequested, self.recognitionRequest === request else { return }
          if let result {
            let nextTranscript = result.bestTranscription.formattedString
            if nextTranscript != self.transcript {
              self.transcript = nextTranscript
            }
          }
          if let error {
            self.recognitionError = error
          }
          if result?.isFinal == true {
            self.stopAudioCapture()
          }
        }
      }

      audioEngine.prepare()
      try audioEngine.start()
      isListening = true
    } catch {
      await finishCapture(id)
      throw error
    }
  }

  public func stop() async throws -> String {
    guard let id = captureID, !cancelRequested, !finalizing, isListening || recognitionTask != nil else {
      throw SpeechRecognitionError.notListening
    }

    finalizing = true
    do { return try await finishTranscript(id) }
    catch { await finishCapture(id); throw error }
  }

  private func finishTranscript(_ id: UUID) async throws -> String {
    stopAudioCapture()
    recognitionRequest?.endAudio()
    // Give the on-device recognizer a brief chance to flush the final audio
    // buffer before collecting its latest partial/final transcription.
    try? await Task.sleep(nanoseconds: 250_000_000)
    try checkCapture(id)
    recognitionTask?.cancel()

    let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalError = recognitionError
    await finishCapture(id)

    guard !finalTranscript.isEmpty else {
      if let finalError { throw finalError }
      throw SpeechRecognitionError.noSpeechDetected
    }
    return finalTranscript
  }

  public func cancel() async {
    guard let id = captureID else { return }
    await finishCapture(id)
  }

  private func finishCapture(_ id: UUID) async {
    guard captureID == id else { return }
    cancelRequested = true
    stopAudioCapture()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    if cleanupTask == nil {
      let start = sessionStartTask
      start?.cancel()
      cleanupTask = Task {
        _ = try? await start?.value
        await SpeechAudioSession.shared.release(id)
      }
    }
    await cleanupTask?.value
    guard captureID == id else { return }
    reset()
  }

  private func checkCapture(_ id: UUID) throws {
    try Task.checkCancellation()
    guard captureID == id, !cancelRequested else { throw CancellationError() }
  }

  public func progress() -> (listening: Bool, transcript: String) {
    (isListening, transcript)
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    isListening = false
  }

  private func reset() {
    captureID = nil
    cancelRequested = false
    finalizing = false
    sessionStartTask = nil
    cleanupTask = nil
    recognitionTask = nil
    recognitionRequest = nil
    recognitionError = nil
    isListening = false

  }

  private func requestSpeechPermission() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    @unknown default:
      return false
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    @unknown default:
      return false
    }
  }
}

public enum SpeechRecognitionError: LocalizedError {
  case alreadyListening
  case notListening
  case speechPermissionDenied
  case microphonePermissionDenied
  case microphoneUnavailable
  case unsupportedLocale(String)
  case onDeviceRecognitionUnavailable(String)
  case noSpeechDetected

  public var errorDescription: String? {
    switch self {
    case .alreadyListening:
      "Speech recognition is already listening."
    case .notListening:
      "Speech recognition is not currently listening."
    case .speechPermissionDenied:
      "Speech Recognition permission is required. Enable it in Settings to dictate messages."
    case .microphonePermissionDenied:
      "Microphone permission is required. Enable it in Settings to dictate messages."
    case .microphoneUnavailable:
      "The microphone is unavailable."
    case .unsupportedLocale(let locale):
      "Speech recognition does not support the current language (\(locale))."
    case .onDeviceRecognitionUnavailable(let locale):
      "On-device speech recognition is not available for the current language (\(locale))."
    case .noSpeechDetected:
      "No speech was detected. Try again and speak closer to the microphone."
    }
  }
}
