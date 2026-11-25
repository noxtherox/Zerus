import Foundation
import MLX
import SwiftUI
import ZerusLocalAI
import ZerusLocalAICore

// iOS probe for the local AI benchmark: measures the chosen models on a real
// iPhone (indexing speed, retrieval, TTFT, tokens/s, memory footprint).
// Launch with "--autorun" (or "--autorun --force-llm") to start immediately.
// Results land in Documents/ (readable via devicectl or the Files app).

@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

@MainActor
final class ProbeLog: ObservableObject {
    static let shared = ProbeLog()
    @Published var lines: [String] = []
    @Published var running = false
}

func log(_ s: String) {
    let stamped = String(format: "[%6.1fs] ", ProcessInfo.processInfo.systemUptime - probeStart) + s
    print(stamped)
    appendToFile(stamped + "\n", "probe-log.txt")
    Task { @MainActor in ProbeLog.shared.lines.append(stamped) }
}

nonisolated(unsafe) var probeStart = ProcessInfo.processInfo.systemUptime

let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

func appendToFile(_ text: String, _ name: String) {
    let url = documents.appendingPathComponent(name)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    } else {
        try? Data(text.utf8).write(to: url)
    }
}

func save(_ object: JSON, _ name: String) {
    guard let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: documents.appendingPathComponent(name))
    log("saved \(name)")
}

// MARK: - Memory

func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

/// Samples the process footprint every 50 ms and keeps the maximum.
final class FootprintSampler: @unchecked Sendable {
    private var peak: UInt64 = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "footprint")

    func start() {
        queue.sync { peak = physFootprint() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.peak = max(self.peak, physFootprint())
        }
        t.resume()
        timer = t
    }

    func peakSoFar() -> Double { queue.sync { Double(peak) / 1_048_576 } }

    func stop() -> Double {
        timer?.cancel()
        return queue.sync { Double(peak) / 1_048_576 }
    }
}

func mb(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }

// MARK: - Run

func runProbe(forceLLM: Bool) async {
    probeStart = ProcessInfo.processInfo.systemUptime
    try? FileManager.default.removeItem(at: documents.appendingPathComponent("probe-log.txt"))
    MLX.Memory.cacheLimit = 32 * 1_048_576

    var device = utsname()
    uname(&device)
    let machine = withUnsafeBytes(of: &device.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    let ram = ProcessInfo.processInfo.physicalMemory
    let info: JSON = [
        "machine": machine, "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "ram_mb": mb(ram), "available_at_start_mb": mb(UInt64(os_proc_available_memory())),
        "footprint_at_start_mb": mb(physFootprint()),
    ]
    log("device \(info)")
    save(info, "probe-device.json")

    // Production self-test (the gate the apps use), then models from the
    // app's verified store, downloaded with the app's downloader.
    var selfTest = LocalAISelfTest()
    selfTest.reset()
    selfTest.run()
    log("MLX self-test: \(selfTest.result)")
    guard selfTest.result == .passed else { return }
    if let store = try? LocalAIModelStore.standard() { evalModelStoreRoot = store.root }

    let root = Bundle.main.resourceURL!
    guard let fixtures = try? Fixtures(root: root) else {
        log("fixtures missing")
        return
    }

    // 1. Embeddings: index the fixtures and run the retrieval queries.
    do {
        let sampler = FootprintSampler()
        sampler.start()
        var report = try await runRetrieval(fixtures: fixtures, extraNotes: [])
        report["footprint_peak_mb"] = sampler.stop()
        report["available_after_mb"] = mb(UInt64(os_proc_available_memory()))
        save(report, "probe-retrieval.json")
    } catch {
        log("retrieval failed: \(error)")
    }
    MLX.Memory.clearCache()

    // 2. LLM (gated to >= 6 GB devices unless forced).
    let llmAllowed = ram >= 5_500_000_000
    guard llmAllowed || forceLLM else {
        log("LLM skipped: \(Int(mb(ram))) MB RAM is below the 6 GB floor (use --force-llm)")
        return
    }
    guard let spec = llmSpecs.first(where: { $0.key == "qwen3.5-2b" }) else { return }
    let sampler = FootprintSampler()
    sampler.start()
    do {
        log("loading \(spec.repo)")
        let llm = try await LLM(spec)
        log(String(format: "loaded in %.1fs, footprint %.0f MB, available %.0f MB",
                   llm.loadSeconds, mb(physFootprint()), mb(UInt64(os_proc_available_memory()))))
        Fixtures.taskLimit = 6
        var results: [TaskResult] = []
        for (name, run) in [
            ("route", runRoute), ("ask", runAsk), ("summarize", runSummarize), ("edit", runEdits),
        ] as [(String, (LLM, Fixtures) async throws -> [TaskResult])] {
            let part = try await run(llm, fixtures)
            results += part
            log("\(name): \(part.filter(\.pass).count)/\(part.count), footprint peak so far \(Int(sampler.peakSoFar())) MB")
            save([
                "model": spec.key, "stage": name, "load_s": llm.loadSeconds,
                "perf": llm.stats.summary, "footprint_peak_mb": sampler.peakSoFar(),
                "available_now_mb": mb(UInt64(os_proc_available_memory())),
                "passed": results.filter(\.pass).count, "total": results.count,
                "results": results.map(\.json),
            ], "probe-llm.json")
        }
    } catch {
        log("LLM failed: \(error)")
    }
    log(String(format: "done; LLM footprint peak %.0f MB", sampler.stop()))
}

struct ProbeView: View {
    @ObservedObject var state = ProbeLog.shared
    @State private var forceLLM = CommandLine.arguments.contains("--force-llm")

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Run LLM below 6 GB", isOn: $forceLLM)
                Button(state.running ? "Running…" : "Run probe") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.running)
                ScrollView {
                    Text(state.lines.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .navigationTitle("Zerus AI Probe")
        }
        .onAppear {
            if CommandLine.arguments.contains("--autorun"), !state.running { start() }
        }
    }

    private func start() {
        state.running = true
        UIApplication.shared.isIdleTimerDisabled = true
        let force = forceLLM
        let cpu = CommandLine.arguments.contains("--cpu")
        Task.detached {
            if cpu {
                compile(enable: false)  // MLX cannot JIT-compile CPU kernels on iOS
                await Device.withDefaultDevice(.cpu) { await runProbe(forceLLM: force) }
            } else {
                await runProbe(forceLLM: force)
            }
            await MainActor.run { ProbeLog.shared.running = false }
        }
    }
}
