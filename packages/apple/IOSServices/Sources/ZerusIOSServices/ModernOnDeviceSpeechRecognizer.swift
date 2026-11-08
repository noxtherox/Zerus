@preconcurrency import AVFoundation
import Speech

@available(iOS 26.0, *)
@MainActor
public final class ModernOnDeviceSpeechRecognizer {
  public init() {}
  private let audioEngine = AVAudioEngine()
  private var analyzer: SpeechAnalyzer?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var analyzerTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var tapInstalled = false
  private var finalizedTranscript = ""
  private var volatileTranscript = ""
  private var recognitionError: Error?
  private var captureID: UUID?
  private var cancelRequested = false
  private var finalizing = false
  private var sessionStartTask: Task<Void, Error>?
  private var cleanupTask: Task<Void, Never>?

  public private(set) var isListening = false

  public var transcript: String {
    joined(finalizedTranscript, volatileTranscript)
  }

  public func start(localeIdentifier: String?) async throws {
    guard captureID == nil else { throw SpeechRecognitionError.alreadyListening }
    let id = UUID()
    captureID = id
    cancelRequested = false
    do { try await startCapture(localeIdentifier: localeIdentifier, id: id) }
    catch { await finishCapture(id, cancelAnalysis: true); throw error }
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
    let requestedLocale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
    guard let locale = await DictationTranscriber.supportedLocale(
      equivalentTo: requestedLocale
    ) else {
      throw SpeechRecognitionError.unsupportedLocale(requestedLocale.identifier)
    }

    try checkCapture(id)
    let transcriber = DictationTranscriber(
      locale: locale,
      preset: .progressiveShortDictation
    )
    try await ensureModel(for: transcriber, locale: locale, captureID: id)
    try checkCapture(id)

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: [transcriber]
    ) else {
      throw SpeechRecognitionError.microphoneUnavailable
    }

    try checkCapture(id)
    finalizedTranscript = ""
    volatileTranscript = ""
    recognitionError = nil
    self.analyzer = analyzer

    do {
      let activation = Task { try await SpeechAudioSession.shared.acquire(id) }
      sessionStartTask = activation
      try await activation.value
      try checkCapture(id)
      sessionStartTask = nil
      try await analyzer.prepareToAnalyze(in: analyzerFormat)
      try checkCapture(id)

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
            guard let self, self.captureID == id && !self.cancelRequested else { return }
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
          if let self, self.captureID == id && !self.cancelRequested { self.stopAudioCapture() }
        } catch {
          if let self, self.captureID == id && !self.cancelRequested { self.recognitionError = error; self.stopAudioCapture() }
        }
      }

      analyzerTask = Task { [weak self] in
        do {
          try await analyzer.start(inputSequence: inputStream)
        } catch {
          if let self, self.captureID == id && !self.cancelRequested { self.recognitionError = error; self.stopAudioCapture() }
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
      if captureID == id { await finishCapture(id, cancelAnalysis: true) }
      else { await analyzer.cancelAndFinishNow() }
      throw error
    }
  }

  public func stop() async throws -> String {
    guard let id = captureID, !cancelRequested, !finalizing, isListening || analyzerTask != nil else {
      throw SpeechRecognitionError.notListening
    }

    finalizing = true
    do { return try await finishTranscript(id) }
    catch { await finishCapture(id, cancelAnalysis: true); throw error }
  }

  private func finishTranscript(_ id: UUID) async throws -> String {
    let finishingAnalyzer = analyzer, analysis = analyzerTask, results = resultsTask
    stopAudioCapture()
    inputContinuation?.finish()
    do {
      try await finishingAnalyzer?.finalizeAndFinishThroughEndOfInput()
      await analysis?.value
      await results?.value
    } catch {
      guard captureID == id, !cancelRequested else { throw CancellationError() }
      recognitionError = error
    }
    try checkCapture(id)

    let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalError = recognitionError
    await finishCapture(id, cancelAnalysis: false)
    guard !finalTranscript.isEmpty else {
      if let finalError { throw finalError }
      throw SpeechRecognitionError.noSpeechDetected
    }
    return finalTranscript
  }

  public func cancel() async {
    guard let id = captureID else { return }
    await finishCapture(id, cancelAnalysis: true)
  }

  private func finishCapture(_ id: UUID, cancelAnalysis: Bool) async {
    guard captureID == id else { return }
    cancelRequested = true
    stopAudioCapture()
    inputContinuation?.finish()
    if cleanupTask == nil {
      let start = sessionStartTask, finishingAnalyzer = cancelAnalysis ? analyzer : nil
      start?.cancel()
      if cancelAnalysis { analyzerTask?.cancel(); resultsTask?.cancel() }
      cleanupTask = Task {
        _ = try? await start?.value
        await SpeechAudioSession.shared.release(id)
        await finishingAnalyzer?.cancelAndFinishNow()
      }
    }
    await cleanupTask?.value
    guard captureID == id else { return }
    reset()
  }

  public func progress() -> (listening: Bool, transcript: String) {
    (isListening, transcript)
  }

  private func ensureModel(
    for transcriber: DictationTranscriber,
    locale: Locale,
    captureID id: UUID
  ) async throws {
    let status = await AssetInventory.status(forModules: [transcriber])
    try checkCapture(id)
    switch status {
    case .installed:
      break
    case .supported, .downloading:
      if let request = try await AssetInventory.assetInstallationRequest(
        supporting: [transcriber]
      ) {
        try checkCapture(id)
        try await request.downloadAndInstall()
        try checkCapture(id)
      }
    case .unsupported:
      throw SpeechRecognitionError.onDeviceRecognitionUnavailable(locale.identifier)
    @unknown default:
      throw SpeechRecognitionError.onDeviceRecognitionUnavailable(locale.identifier)
    }
    try checkCapture(id)
    _ = try await AssetInventory.reserve(locale: locale)
    try checkCapture(id)
  }

  private func checkCapture(_ id: UUID) throws {
    try Task.checkCancellation()
    guard captureID == id, !cancelRequested else { throw CancellationError() }
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
    captureID = nil
    cancelRequested = false
    finalizing = false
    sessionStartTask = nil
    cleanupTask = nil
    analyzerTask = nil
    resultsTask = nil
    inputContinuation = nil
    analyzer = nil
    recognitionError = nil
    isListening = false

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
