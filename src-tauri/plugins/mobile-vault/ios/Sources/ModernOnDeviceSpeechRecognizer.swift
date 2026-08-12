@preconcurrency import AVFoundation
import Speech

@available(iOS 26.0, *)
@MainActor
final class ModernOnDeviceSpeechRecognizer {
  private let audioEngine = AVAudioEngine()
  private var analyzer: SpeechAnalyzer?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var analyzerTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var tapInstalled = false
  private var finalizedTranscript = ""
  private var volatileTranscript = ""
  private var recognitionError: Error?

  private(set) var isListening = false

  var transcript: String {
    joined(finalizedTranscript, volatileTranscript)
  }

  func start(localeIdentifier: String?) async throws {
    guard !isListening else { throw SpeechRecognitionError.alreadyListening }
    guard await requestSpeechPermission() else {
      throw SpeechRecognitionError.speechPermissionDenied
    }
    guard await requestMicrophonePermission() else {
      throw SpeechRecognitionError.microphonePermissionDenied
    }

    let requestedLocale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
    guard let locale = await DictationTranscriber.supportedLocale(
      equivalentTo: requestedLocale
    ) else {
      throw SpeechRecognitionError.unsupportedLocale(requestedLocale.identifier)
    }

    let transcriber = DictationTranscriber(
      locale: locale,
      preset: .progressiveShortDictation
    )
    try await ensureModel(for: transcriber, locale: locale)

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: [transcriber]
    ) else {
      throw SpeechRecognitionError.microphoneUnavailable
    }

    finalizedTranscript = ""
    volatileTranscript = ""
    recognitionError = nil
    self.analyzer = analyzer

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      try await analyzer.prepareToAnalyze(in: analyzerFormat)

      let input = audioEngine.inputNode
      let naturalFormat = input.outputFormat(forBus: 0)
      guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
        throw SpeechRecognitionError.microphoneUnavailable
      }
      guard let converter = AVAudioConverter(from: naturalFormat, to: analyzerFormat) else {
        throw SpeechRecognitionError.microphoneUnavailable
      }

      let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
      inputContinuation = continuation

      resultsTask = Task { [weak self] in
        do {
          for try await result in transcriber.results {
            guard let self else { return }
            let text = String(result.text.characters)
              .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if result.isFinal {
              self.finalizedTranscript = self.joined(self.finalizedTranscript, text)
              self.volatileTranscript = ""
            } else {
              self.volatileTranscript = text
            }
          }
        } catch {
          self?.recognitionError = error
        }
      }

      analyzerTask = Task { [weak self] in
        do {
          try await analyzer.start(inputSequence: inputStream)
        } catch {
          self?.recognitionError = error
        }
      }

      input.installTap(onBus: 0, bufferSize: 1_024, format: naturalFormat) {
        buffer, _ in
        guard let converted = Self.convert(
          buffer,
          using: converter,
          to: analyzerFormat
        ) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
      }
      tapInstalled = true

      audioEngine.prepare()
      try audioEngine.start()
      isListening = true
    } catch {
      cancel()
      throw error
    }
  }

  func stop() async throws -> String {
    guard isListening || analyzer != nil else {
      throw SpeechRecognitionError.notListening
    }

    stopAudioCapture()
    inputContinuation?.finish()
    do {
      try await analyzer?.finalizeAndFinishThroughEndOfInput()
      await analyzerTask?.value
      await resultsTask?.value
    } catch {
      recognitionError = error
    }

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
    inputContinuation?.finish()
    analyzerTask?.cancel()
    resultsTask?.cancel()
    if let analyzer {
      Task { await analyzer.cancelAndFinishNow() }
    }
    reset()
  }

  func progress() -> (listening: Bool, transcript: String) {
    (isListening, transcript)
  }

  private func ensureModel(
    for transcriber: DictationTranscriber,
    locale: Locale
  ) async throws {
    switch await AssetInventory.status(forModules: [transcriber]) {
    case .installed:
      break
    case .supported, .downloading:
      if let request = try await AssetInventory.assetInstallationRequest(
        supporting: [transcriber]
      ) {
        try await request.downloadAndInstall()
      }
    case .unsupported:
      throw SpeechRecognitionError.onDeviceRecognitionUnavailable(locale.identifier)
    @unknown default:
      throw SpeechRecognitionError.onDeviceRecognitionUnavailable(locale.identifier)
    }
    _ = try await AssetInventory.reserve(locale: locale)
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning { audioEngine.stop() }
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    isListening = false
  }

  private func reset() {
    analyzerTask = nil
    resultsTask = nil
    inputContinuation = nil
    analyzer = nil
    recognitionError = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  private func joined(_ first: String, _ second: String) -> String {
    guard !first.isEmpty else { return second }
    guard !second.isEmpty else { return first }
    return first.last?.isWhitespace == true ? first + second : first + " " + second
  }

  nonisolated private static func convert(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      return nil
    }

    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, status in
      if suppliedInput {
        status.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      status.pointee = .haveData
      return buffer
    }
    guard conversionError == nil, status != .error else { return nil }
    return output
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
