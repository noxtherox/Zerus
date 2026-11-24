import SwiftUI
import PDFKit

struct MacPDFView: View {
    @StateObject private var reader: MacPDFReader
    @State private var query = ""
    @State private var page = "1"
    @State private var matchCase = false
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    init(url: URL) { _reader = StateObject(wrappedValue: MacPDFReader(url: url)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Find in PDF", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 240).onSubmit { reader.moveMatch(1) }
                Toggle("Match case", isOn: $matchCase).toggleStyle(.checkbox).font(.caption)
                Button { reader.moveMatch(-1) } label: { Image(systemName: "chevron.up") }.help("Previous match").disabled(reader.matches.isEmpty)
                Button { reader.moveMatch(1) } label: { Image(systemName: "chevron.down") }.help("Next match").disabled(reader.matches.isEmpty)
                Text(reader.searchStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("−") { reader.view.zoomOut(nil) }.help("Zoom out")
                Button("+") { reader.view.zoomIn(nil) }.help("Zoom in")
                Button("Fit") { reader.view.autoScales = true }
            }.padding(10).disabled(reader.locked)
            HStack(spacing: 10) {
                Button("Previous page") { reader.view.goToPreviousPage(nil) }.disabled(reader.currentPage <= 1)
                TextField("Page", text: $page).frame(width: 45).textFieldStyle(.roundedBorder).onSubmit { reader.goToPage(page); page = String(reader.currentPage) }
                Text("of \(reader.document?.pageCount ?? 0)").font(.caption)
                Button("Next page") { reader.view.goToNextPage(nil) }.disabled(reader.currentPage >= (reader.document?.pageCount ?? 0))
                Spacer()

            }.padding(.horizontal, 10).padding(.bottom, 10).disabled(reader.locked)
            Divider()
            if reader.locked {
                VStack(spacing: 14) {
                    Image(systemName: "lock.doc").font(.largeTitle).foregroundStyle(.secondary)
                    Text("This PDF requires a password").font(.headline)
                    SecureField("PDF password", text: $password).textFieldStyle(.roundedBorder)
                        .focused($passwordFocused).onSubmit { unlock() }
                    Button("Unlock PDF") { unlock() }.disabled(password.isEmpty)
                    if let issue = reader.unlockIssue { Text(issue).font(.callout).foregroundStyle(.red) }
                    Text("The password is used only for this open preview. The original PDF stays encrypted.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 380).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { passwordFocused = true }
            } else if reader.document != nil { MacPDFSurface(reader: reader) }
            else { ContentUnavailableView("PDF unavailable", systemImage: "doc", description: Text("Open externally to check this file.")) }
        }
        .onChange(of: reader.currentPage) { page = String(reader.currentPage) }
        .onChange(of: query) { reader.cancelSearch() }
        .onChange(of: matchCase) { reader.cancelSearch() }
        .task(id: "\(reader.locked):\(matchCase):\(query)") {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); reader.search(query, matchCase: matchCase) } catch {}
        }
        .onDisappear { password = ""; reader.cancelSearch() }
    }
    private func unlock() {
        let attempt = password; password = ""
        if !reader.unlock(password: attempt) { passwordFocused = true }
    }
}
@MainActor final class MacPDFReader: NSObject, ObservableObject {
    let view = PDFView()
    let document: PDFDocument?
    @Published private(set) var locked: Bool
    @Published private(set) var unlockIssue: String?
    @Published private(set) var matches: [PDFSelection] = []
    @Published private(set) var matchIndex = -1
    @Published private(set) var currentPage = 1
    @Published private(set) var searching = false
    private var hasQuery = false
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private var pageObserver: NSObjectProtocol?
    var searchStatus: String {
        if searching { return "Searching… \(matches.count) matches" }
        if !hasQuery { return "" }
        return matches.isEmpty ? "No matches" : "\(matchIndex + 1) of \(matches.count)"
    }
    init(url: URL) {
        document = PDFDocument(url: url)
        locked = document?.isLocked == true
        super.init()
        view.autoScales = true; view.document = locked ? nil : document
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, let current = self.view.currentPage, let document = self.document else { return }; self.currentPage = document.index(for: current) + 1 }
        }
    }
    deinit { searchTask?.cancel(); if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) } }
    @discardableResult func unlock(password: String) -> Bool {
        guard let document else { unlockIssue = "This PDF could not be opened."; return false }
        guard document.isLocked else { return true }
        guard document.unlock(withPassword: password) else {
            unlockIssue = "The password did not unlock this PDF. Try again."; return false
        }
        unlockIssue = nil; locked = false
        view.document = document; view.autoScales = true
        if let first = document.page(at: 0) { view.go(to: first) }
        return true
    }
    func cancelSearch() {
        searchID = UUID(); searchTask?.cancel(); searchTask = nil
        hasQuery = false; matches = []; matchIndex = -1; searching = false
        view.highlightedSelections = []; view.clearSelection()
    }
    func search(_ query: String, matchCase: Bool) {
        cancelSearch()
        let needle = Self.normalizedQuery(query, matchCase: matchCase)
        guard needle.unicodeScalars.contains(where: { $0.value != 0x20 }),
              let document, !document.isLocked else { return }
        hasQuery = true; searching = true
        let id = searchID, count = document.pageCount
        searchTask = Task { [weak self] in
            defer {
                if let self, self.searchID == id { self.searching = false; self.searchTask = nil }
            }
            for index in 0..<count {
                guard !Task.isCancelled, let self, self.searchID == id,
                      let page = self.document?.page(at: index) else { return }
                guard let text = page.string, !text.isEmpty else { await Task.yield(); continue }
                // PDFKit objects stay on the main actor. Normalize and match
                // one page of value text off-main, with cancellable work.
                let worker = Task.detached(priority: .userInitiated) {
                    try Self.matchRanges(text, needle: needle, matchCase: matchCase)
                }
                let ranges: [NSRange]
                do {
                    ranges = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                } catch { return }
                guard !Task.isCancelled, self.searchID == id else { return }
                let selections = ranges.compactMap { page.selection(for: $0) }
                for selection in selections { selection.color = .systemYellow.withAlphaComponent(0.5) }
                self.matches.append(contentsOf: selections)
                self.view.highlightedSelections = self.matches
                if self.matchIndex == -1 { self.moveMatch(1) }
                await Task.yield()
            }
        }
    }
    // Match the desktop's NFKD and ECMAScript whitespace rules. Source offsets
    // refer to original Unicode scalars, not the expanded compatibility text.
    nonisolated private static func searchWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }
    nonisolated private static func normalizedQuery(_ value: String, matchCase: Bool) -> String {
        let decomposed = value.decomposedStringWithCompatibilityMapping
        let folded = matchCase ? decomposed : decomposed.lowercased()
        var result = "", space = false
        for scalar in folded.unicodeScalars {
            if searchWhitespace(scalar) {
                if !space { result.append(" ") }; space = true
            } else { result.unicodeScalars.append(scalar); space = false }
        }
        return result
    }
    nonisolated private static func matchRanges(_ text: String, needle: String, matchCase: Bool) throws -> [NSRange] {
        var units: [UInt16] = [], starts: [Int] = [], ends: [Int] = []
        var offset = 0, processed = 0, space = false
        for scalar in text.unicodeScalars {
            if processed % 1024 == 0 { try Task.checkCancellation() }; processed += 1
            let end = offset + (scalar.value > 0xFFFF ? 2 : 1)
            let decomposed = String(scalar).decomposedStringWithCompatibilityMapping
            let folded = matchCase ? decomposed : decomposed.lowercased()
            for part in folded.unicodeScalars {
                let whitespace = searchWhitespace(part)
                if !whitespace || !space {
                    for unit in (whitespace ? " " : String(part)).utf16 {
                        units.append(unit); starts.append(offset); ends.append(end)
                    }
                }
                space = whitespace
            }
            offset = end
        }
        let normalized = String(decoding: units, as: UTF16.self) as NSString
        var result: [NSRange] = [], cursor = 0
        while cursor < normalized.length {
            try Task.checkCancellation()
            let found = normalized.range(of: needle, options: .literal, range: NSRange(location: cursor, length: normalized.length - cursor))
            guard found.location != NSNotFound else { break }
            let start = starts[found.location], end = ends[NSMaxRange(found) - 1]
            result.append(NSRange(location: start, length: end - start))
            cursor = NSMaxRange(found)
        }
        return result
    }
    func moveMatch(_ direction: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + direction + matches.count) % matches.count
        let selection = matches[matchIndex]; view.setCurrentSelection(selection, animate: true); view.go(to: selection)
    }
    func goToPage(_ input: String) {
        guard let index = Int(input), index > 0, let page = document?.page(at: index - 1) else { return }
        view.go(to: page)
    }
}
private struct MacPDFSurface: NSViewRepresentable {
    let reader: MacPDFReader
    func makeNSView(context: Context) -> PDFView { reader.view }
    func updateNSView(_ view: PDFView, context: Context) {}
}
