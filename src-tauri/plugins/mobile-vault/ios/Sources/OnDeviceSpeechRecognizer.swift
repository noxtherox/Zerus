import AVFoundation
import Speech

@MainActor
final class OnDeviceSpeechRecognizer {
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var tapInstalled = false
  private var transcript = ""
  private var recognitionError: Error?

  private(set) var isListening = false

  func start(localeIdentifier: String?) async throws {
    guard !isListening else { throw SpeechRecognitionError.alreadyListening }

    guard await requestSpeechPermission() else {
      throw SpeechRecognitionError.speechPermissionDenied
    }
    guard await requestMicrophonePermission() else {
      throw SpeechRecognitionError.microphonePermissionDenied
    }

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
    request.contextualStrings = ["Grimoire"]
    recognitionRequest = request

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try session.setActive(true, options: .notifyOthersOnDeactivation)

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
          guard let self, self.recognitionRequest != nil else { return }
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
      stopAudioCapture()
      recognitionTask?.cancel()
      reset()
      throw error
    }
  }

  func stop() async throws -> String {
    guard isListening || recognitionRequest != nil else {
      throw SpeechRecognitionError.notListening
    }

    stopAudioCapture()
    recognitionRequest?.endAudio()
    // Give the on-device recognizer a brief chance to flush the final audio
    // buffer before collecting its latest partial/final transcription.
    try? await Task.sleep(nanoseconds: 250_000_000)
    recognitionTask?.cancel()

    let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalError = recognitionError
    reset()

    guard !finalTranscript.isEmpty else {
      if let finalError { throw finalError }
      throw SpeechRecognitionError.noSpeechDetected
    }
    return finalTranscript
  }

  func cancel() {
    stopAudioCapture()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    reset()
  }

  func progress() -> (listening: Bool, transcript: String) {
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
    recognitionTask = nil
    recognitionRequest = nil
    recognitionError = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
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

enum SpeechRecognitionError: LocalizedError {
  case alreadyListening
  case notListening
  case speechPermissionDenied
  case microphonePermissionDenied
  case microphoneUnavailable
  case unsupportedLocale(String)
  case onDeviceRecognitionUnavailable(String)
  case noSpeechDetected

  var errorDescription: String? {
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
