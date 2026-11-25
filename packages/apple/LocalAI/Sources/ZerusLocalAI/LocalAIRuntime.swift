import Foundation
import MLX
import ZerusLocalAICore

/// What this device can run.
public struct LocalAICapabilities: Sendable, Equatable {
    /// Embedding model (semantic search). Needs a passing MLX self-test.
    public let semanticSearch: Bool
    /// Language model (Ask, summaries, edits). Also needs ≥6 GB RAM.
    public let languageModel: Bool
    /// Why something is unavailable, for Settings.
    public let limitation: String?
}

/// Owns the loaded MLX models for the app process. Models load lazily from
/// verified folders in the model store; the language model can be unloaded
/// on memory pressure or after inactivity and reloads on next use.
public actor LocalAIRuntime {
    public enum Failure: LocalizedError {
        case notInstalled(LocalAIModelSpec)
        case unsupportedDevice(String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled(let spec): "\(spec.displayName) isn't downloaded yet. Download it in Settings → On-device AI."
            case .unsupportedDevice(let reason): reason
            }
        }
    }

    /// iPhones report a little under their nominal RAM (6 GB ≈ 5.6–5.8 GB).
    public static let languageModelMinimumMemory: UInt64 = 5_500_000_000

    public let store: LocalAIModelStore
    public let embeddingSpec: LocalAIModelSpec
    public let languageSpec: LocalAIModelSpec
    private let defaults: UserDefaults
    private var loadedEmbedder: MLXEmbedder?
    private var loadedLanguageModel: MLXLanguageModel?
    private var embedderLoad: Task<MLXEmbedder, Error>?
    private var languageLoad: Task<MLXLanguageModel, Error>?

    public init(
        store: LocalAIModelStore, embeddingSpec: LocalAIModelSpec = .embeddingGemma300M,
        languageSpec: LocalAIModelSpec = .qwen35_2B, defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.embeddingSpec = embeddingSpec
        self.languageSpec = languageSpec
        self.defaults = defaults
        MLX.Memory.cacheLimit = 64 << 20
    }

    // MARK: Capabilities

    public func capabilities() -> LocalAICapabilities {
        let selfTest = LocalAISelfTest(defaults: defaults).result
        let memory = ProcessInfo.processInfo.physicalMemory
        switch selfTest {
        case .failed:
            return .init(semanticSearch: false, languageModel: false,
                         limitation: "On-device AI isn't supported on this device. Keyword search stays available.")
        case .notRun:
            return .init(semanticSearch: false, languageModel: false, limitation: "Checking whether this device supports on-device AI…")
        case .passed:
            let enough = memory >= Self.languageModelMinimumMemory
            return .init(semanticSearch: true, languageModel: enough,
                         limitation: enough ? nil : "Ask, summaries and edits need a device with at least 6 GB of memory. Semantic search is available.")
        }
    }

    /// Runs the MLX self-test once per app and OS version (see `LocalAISelfTest`).
    @discardableResult
    public func ensureSelfTest() -> Bool {
        var test = LocalAISelfTest(defaults: defaults)
        if case .notRun = test.result { test.run() }
        return test.result == .passed
    }

    // MARK: Models

    public func embedder() async throws -> MLXEmbedder {
        if let loadedEmbedder { return loadedEmbedder }
        if let embedderLoad { return try await embedderLoad.value }
        guard ensureSelfTest() else { throw Failure.unsupportedDevice(capabilities().limitation ?? "") }
        guard store.state(of: embeddingSpec) == .installed else { throw Failure.notInstalled(embeddingSpec) }
        let spec = embeddingSpec, directory = store.directory(for: spec)
        let task = Task { try await MLXEmbedder(spec: spec, directory: directory) }
        embedderLoad = task
        defer { embedderLoad = nil }
        let embedder = try await task.value
        loadedEmbedder = embedder
        return embedder
    }

    public func languageModel() async throws -> MLXLanguageModel {
        if let loadedLanguageModel { return loadedLanguageModel }
        if let languageLoad { return try await languageLoad.value }
        guard ensureSelfTest(), capabilities().languageModel else {
            throw Failure.unsupportedDevice(capabilities().limitation ?? "")
        }
        guard store.state(of: languageSpec) == .installed else { throw Failure.notInstalled(languageSpec) }
        let spec = languageSpec, directory = store.directory(for: spec)
        let task = Task { try await MLXLanguageModel(spec: spec, directory: directory) }
        languageLoad = task
        defer { languageLoad = nil }
        let model = try await task.value
        loadedLanguageModel = model
        return model
    }

    public var isLanguageModelLoaded: Bool { loadedLanguageModel != nil }

    /// Frees the language model (~1.2–2 GB); call on memory warnings, when
    /// the app goes to the background, or after inactivity.
    public func unloadLanguageModel() {
        loadedLanguageModel = nil
        MLX.Memory.clearCache()
    }

    public func unloadAll() {
        loadedLanguageModel = nil
        loadedEmbedder = nil
        MLX.Memory.clearCache()
    }
}

/// A tiny MLX workload (float and 4-bit quantized matrix products, the
/// kernels the models use) run once per app build and OS version. Some GPUs
/// fail to compile MLX kernels (A13: ml-explore/mlx-swift#526); a "running"
/// marker left behind by a crash also counts as a failure, so a crashing
/// device is not retried on every launch.
public struct LocalAISelfTest {
    public enum Result: Equatable { case notRun, passed, failed }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        key = "zerus.localAI.selfTest.\(build).\(os)"
    }

    public var result: Result {
        switch defaults.string(forKey: key) {
        case "passed": .passed
        case "failed", "running": .failed
        default: .notRun
        }
    }

    public mutating func run() {
        defaults.set("running", forKey: key)
        defaults.synchronize()
        defaults.set(Self.workload() ? "passed" : "failed", forKey: key)
    }

    /// Clears a stored result (e.g. "Try again" in Settings).
    public func reset() { defaults.removeObject(forKey: key) }

    static func workload() -> Bool {
        do {
            return try withError {
                let a = MLXArray((0 ..< 64 * 64).map { Float($0 % 7) / 7 }, [64, 64])
                let product = matmul(a, a.T)
                let (w, scales, biases) = quantized(a, groupSize: 64, bits: 4)
                let q = quantizedMatmul(a, w, scales: scales, biases: biases, transpose: true, groupSize: 64, bits: 4)
                let error = abs(product - q).max()
                eval(product, q, error)
                // 4-bit rounding error stays small for this input.
                return error.item(Float.self) < 2 && product.sum().item(Float.self).isFinite
            }
        } catch {
            return false
        }
    }
}
