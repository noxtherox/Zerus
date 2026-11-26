import SwiftUI
import AppKit
import Markdown

struct MacNoteLinkTrigger: Equatable {
    let range: NSRange
    let query: String
    static func match(_ text: String, caret: NSRange) -> Self? {
        let raw = text as NSString
        guard caret.length == 0, caret.location <= raw.length else { return nil }
        let line = raw.paragraphRange(for: caret), before = raw.substring(with: NSRange(location: line.location, length: caret.location - line.location)) as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"(?:^|[\s(])(@([^@\[\]\n]{0,100}))$|(?:^|[^\[])(\[\[([^\[\]\n]{0,100}))$"#), let found = pattern.firstMatch(in: before as String, range: NSRange(location: 0, length: before.length)) else { return nil }
        let group = found.range(at: 1).location != NSNotFound ? 1 : 3, range = found.range(at: group), query = found.range(at: group + 1)
        return .init(range: NSRange(location: line.location + range.location, length: range.length), query: before.substring(with: query))
    }
    static func candidates(_ notes: [NoteDocument], query: String) -> [NoteDocument] {
        let query = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return Array(notes.filter { !$0.trashed && (query.isEmpty || ($0.title + " " + $0.path).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).contains(query)) }.sorted { left, right in
            let l = left.title.localizedCaseInsensitiveCompare(query) == .orderedSame, r = right.title.localizedCaseInsensitiveCompare(query) == .orderedSame
            return l != r ? l : left.path.localizedStandardCompare(right.path) == .orderedAscending
        }.prefix(8))
    }
}

@MainActor final class MacNoteLinkCompletion {
    final class Model: ObservableObject {
        var allNotes: [NoteDocument] = []
        @Published var query = "" { didSet { index = 0 } }
        @Published var index = 0
        var manual = false
        var allowsCreation = false
        var notes: [NoteDocument] { MacNoteLinkTrigger.candidates(allNotes, query: query) }
        var canCreate: Bool { allowsCreation && !query.trimmingCharacters(in: .whitespaces).isEmpty && !notes.contains { $0.title.localizedCaseInsensitiveCompare(query) == .orderedSame } }
        var choose: (NoteDocument?, String) -> Void = { _, _ in }
        var dismiss: () -> Void = {}
        var count: Int { notes.count + (canCreate ? 1 : 0) }
        func select(_ index: Int) { guard index >= 0, index < count else { return }; choose(index < notes.count ? notes[index] : nil, query) }
    }
    private var host: NSHostingView<Choices>?
    private let model = Model()
    var shown: Bool { host != nil }
    func hide() {
        if let host, let responder = host.window?.firstResponder as? NSView, responder.isDescendant(of: host), let editor = (host.superview as? NSScrollView)?.documentView { host.window?.makeFirstResponder(editor) }
        host?.removeFromSuperview(); host = nil; model.choose = { _, _ in }
    }
    func show(view: NSTextView, query: String, notes: [NoteDocument], canCreate: Bool, manual: Bool, choose: @escaping (NoteDocument?, String) -> Void) {
        guard let scroll = view.enclosingScrollView, let window = view.window else { return }
        model.allNotes = notes; model.manual = manual; model.allowsCreation = canCreate; model.query = query; model.index = 0; model.choose = choose; model.dismiss = { [weak self] in self?.hide() }
        if host == nil { let host = NSHostingView(rootView: Choices(model: model)); self.host = host; scroll.addSubview(host) }
        let height = min(scroll.bounds.height - 16, CGFloat((manual ? 100 : 66) + max(1, model.count) * 40)), width = min(CGFloat(390), scroll.bounds.width - 16)
        let screenRect = view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil), caret = scroll.convert(window.convertFromScreen(screenRect), from: nil)
        let y = scroll.isFlipped ? caret.maxY + 4 : caret.minY - height - 4
        host?.frame = NSRect(x: max(8, min(caret.minX, scroll.bounds.width - width - 8)), y: max(8, min(y, scroll.bounds.height - height - 8)), width: width, height: height)
    }
    func key(_ code: UInt16) -> Bool {
        guard shown else { return false }
        switch code {
        case 53: hide(); return true
        case 125: model.index = min(max(0, model.count - 1), model.index + 1); return true
        case 126: model.index = max(0, model.index - 1); return true
        case 36, 48: guard model.count > 0 else { hide(); return false }; model.select(model.index); return true
        default: return false
        }
    }
    private struct Choices: View {
        @ObservedObject var model: Model
        @FocusState private var focused: Bool
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text("Link a note").macFont(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 3)
                if model.manual {
                    TextField("Find a note", text: $model.query).textFieldStyle(.roundedBorder).focused($focused)
                        .onSubmit { model.select(model.index) }
                        .onKeyPress(.downArrow) { model.index = min(max(0, model.count - 1), model.index + 1); return .handled }
                        .onKeyPress(.upArrow) { model.index = max(0, model.index - 1); return .handled }
                        .onKeyPress(.escape) { model.dismiss(); return .handled }
                }
                ScrollViewReader { proxy in ScrollView { VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.notes.enumerated()), id: \.element.path) { index, note in
                    Button { model.select(index) } label: { VStack(alignment: .leading, spacing: 2) { SwiftUI.Text(note.title).macFont(.callout.bold()); SwiftUI.Text(note.path).macFont(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(5).background(model.index == index ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(MacBoxButtonStyle()).id(index)
                }
                if model.canCreate { Button { model.select(model.notes.count) } label: { Label("Create “" + model.query + "”", systemImage: "plus").macFont(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(model.index == model.notes.count ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(MacBoxButtonStyle()).id(model.notes.count) }
                if model.count == 0 { SwiftUI.Text("No matching notes.").macFont(.caption).foregroundStyle(.secondary).padding(8) }
                } }.onChange(of: model.index) { proxy.scrollTo(model.index, anchor: .center) } }
                SwiftUI.Text("↑↓ Choose · Return Insert · Esc Dismiss").macFont(.caption2).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(.quaternary) }.task { if model.manual { focused = true } }
        }
    }
}

extension VaultFiles {
    func createLinkTarget(title: String, folder: String) throws -> NoteDocument {
        let title = try NativeNoteRename.cleanTitle(title), snapshot = try scan()
        let matches = snapshot.notes.filter { !$0.trashed && $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
        if matches.count == 1 { return matches[0] }
        guard matches.isEmpty else { throw VaultFailure(message: "More than one note has this title. Choose a specific note from the suggestions.") }
        let directory = folder.isEmpty || folder.hasPrefix(".") ? "Inbox" : folder
        let filename = NativeNoteRename.suggestedFilename(title, path: "Untitled.md"), path = directory + "/" + filename
        guard !snapshot.notes.contains(where: { $0.path.caseInsensitiveCompare(path) == .orderedSame }) else { throw VaultFailure(message: "That filename already exists. Choose another title.") }
        let content = "---\nzerus-id: " + UUID().uuidString.lowercased() + "\n---\n# " + title + "\n\n"
        try write(path, data: Data(content.utf8), expected: nil)
        return .init(path: path, content: content, modified: Date())
    }
}

struct MacMissingNoteLink: Identifiable {
    let id = UUID()
    let title: String
    let folder: String
    let workspaceID: UUID
}
struct MacMissingNoteLinkView: View {
    @Bindable var workspace: MacWorkspace
    let request: MacMissingNoteLink
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SwiftUI.Text("Create linked note?").macFont(.title2.bold())
            SwiftUI.Text("“" + request.title + "” does not exist. Create it in " + request.folder + "?")
            if let issue { SwiftUI.Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Button("Cancel") { dismiss() }.disabled(saving); Spacer(); if saving { ProgressView().controlSize(.small) }; Button("Create and open") {
                saving = true
                Task { defer { saving = false }; do {
                    let note = try await workspace.createLinkedNote(title: request.title, folder: request.folder, workspaceID: request.workspaceID)
                    guard request.workspaceID == workspace.workspaceID else { return }
                    await workspace.openNote(note.path)
                    guard workspace.selection == note.path else { throw VaultFailure(message: workspace.issue ?? "The new note is kept. Save or recover the current editor before opening it.") }
                    dismiss()
                } catch { issue = error.localizedDescription } }
            }.disabled(saving) }
        }.padding(24).frame(width: 460).interactiveDismissDisabled(saving)
    }
}

/// A link draft is tied to one native editor revision and selection. No URL is
/// loaded while preparing or editing it.
struct MacLinkEditRequest {
    let baseline: String
    let token: UUID
    let range: NSRange
    let selection: NSRange
    let source: Bool
    let label: NSAttributedString
    let sourceLabel: String?
    let destination: String?
    let title: String?
    let canEditLabel: Bool

    struct SourceLink {
        let range: NSRange
        let destination: String
        let label: String
        let title: String?
    }
    static func sourceLinks(_ source: String) -> (links: [SourceLink], code: [NSRange]) {
        let rows = MacMarkdownLines(source).lines, raw = source as NSString
        func offset(_ location: SourceLocation) -> Int? {
            guard rows.indices.contains(location.line - 1), location.column > 0 else { return nil }
            let row = rows[location.line - 1], bytes = Array(row.text.utf8)
            guard location.column - 1 <= bytes.count,
                  let prefix = String(bytes: bytes.prefix(location.column - 1), encoding: .utf8) else { return nil }
            return row.offset + prefix.utf16.count
        }
        func span(_ node: any Markup) -> NSRange? {
            guard let range = node.range, let start = offset(range.lowerBound), let end = offset(range.upperBound), end >= start else { return nil }
            return NSRange(location: start, length: end - start)
        }
        var links: [SourceLink] = [], code: [NSRange] = []
        func walk(_ node: any Markup) {
            if node is CodeBlock || node is InlineCode {
                if let range = span(node) { code.append(range) }; return
            }
            if let link = node as? Markdown.Link, let destination = link.destination, let range = span(link) {
                let children = Array(link.children)
                let label: String
                if let first = children.first, let last = children.last,
                   let lower = first.range?.lowerBound, let upper = last.range?.upperBound,
                   let start = offset(lower), let end = offset(upper), end >= start {
                    label = raw.substring(with: NSRange(location: start, length: end - start))
                } else { label = link.plainText }
                links.append(.init(range: range, destination: destination, label: label, title: link.title))
                return
            }
            for child in node.children { walk(child) }
        }
        walk(Document(parsing: source))
        if let regex = try? NSRegularExpression(pattern: #"(?<!\\)\[\[[^\]\r\n]+\]\]"#) {
            for match in regex.matches(in: source, range: NSRange(location: 0, length: raw.length)) {
                guard !code.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      !links.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }),
                      let reference = NoteReference(wikilink: raw.substring(with: match.range)) else { continue }
                links.append(.init(range: match.range, destination: reference.url.absoluteString, label: reference.label, title: nil))
            }
        }
        return (links, code)
    }
    static func webMarkdownDestination(_ value: String) -> String {
        // Balanced parentheses already form a portable Markdown destination.
        var depth = 0, balanced = true
        for character in value { if character == "(" { depth += 1 }; if character == ")" { depth -= 1; if depth < 0 { balanced = false } } }
        guard !balanced || depth != 0 else { return value }
        return value.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    }
    static func titleSuffix(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "" }
        return " \"" + title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") + "\""
    }
}

struct MacInlineLinkEditView: View {
    let request: MacLinkEditRequest
    let notes: [NoteDocument]
    let apply: (String?, String) throws -> Void
    let cancel: () -> Void
    @AppStorage("zerus.mac.editor.linkOption") private var savedChoice = "note"
    @State private var noteDestination: Bool
    @State private var address: String
    @State private var label: String
    @State private var query = ""
    @State private var selectedPath: String?
    @State private var issue: String?
    @FocusState private var focused: Bool
    init(request: MacLinkEditRequest, notes: [NoteDocument], apply: @escaping (String?, String) throws -> Void, cancel: @escaping () -> Void) {
        self.request = request; self.notes = notes; self.apply = apply; self.cancel = cancel
        let reference = request.destination.flatMap(URL.init(string:)).flatMap(NoteReference.init(url:))
        _noteDestination = State(initialValue: reference != nil || request.destination == nil && UserDefaults.standard.string(forKey: "zerus.mac.editor.linkOption") != "web")
        _address = State(initialValue: reference == nil ? request.destination ?? "" : "")
        _label = State(initialValue: request.label.string)
        let matches = reference?.targets(in: notes) ?? []
        _selectedPath = State(initialValue: matches.count == 1 ? matches[0].path : nil)
    }
    private var matches: [NoteDocument] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return Array(notes.filter { note in !note.trashed && terms.allSatisfy { (note.title + " " + note.path).localizedStandardContains($0) } }.sorted {
            let title = $0.title.localizedStandardCompare($1.title)
            return title == .orderedSame ? $0.path.localizedStandardCompare($1.path) == .orderedAscending : title == .orderedAscending
        }.prefix(50))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwiftUI.Text(request.destination == nil ? "Insert link" : "Edit link").macFont(.headline)
            Picker("Link destination", selection: $noteDestination) { SwiftUI.Text("Web URL").tag(false); SwiftUI.Text("Vault note").tag(true) }.pickerStyle(.segmented)
            if noteDestination {
                TextField("Find a note", text: $query).focused($focused)
                ScrollView { VStack(alignment: .leading, spacing: 4) {
                    ForEach(matches, id: \.path) { note in
                        Button { selectedPath = note.path; issue = nil } label: {
                            HStack { Image(systemName: selectedPath == note.path ? "checkmark.circle.fill" : "doc.text"); VStack(alignment: .leading) { SwiftUI.Text(note.title); SwiftUI.Text(note.path).macFont(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Link to " + note.title + ", " + note.path)
                    }
                    if matches.isEmpty { SwiftUI.Text("No matching notes.").foregroundStyle(.secondary) }
                } }.frame(height: 150)
            } else { TextField("Web URL", text: $address).focused($focused).autocorrectionDisabled(true) }
            TextField("Display text", text: $label).disabled(!request.canEditLabel)
            if !request.canEditLabel { SwiftUI.Text("Your selected text and formatting will be kept.").macFont(.caption).foregroundStyle(.secondary) }
            if let issue { SwiftUI.Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if let destination = request.destination {
                    Button("Remove link") { save(nil) }
                    Button("Copy link") {
                        let reference = URL(string: destination).flatMap(NoteReference.init(url:))
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reference.map { $0.markdown(label: request.label.string) } ?? destination, forType: .string)
                    }
                }
                Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save link") {
                    if noteDestination {
                        guard let note = notes.first(where: { $0.path == selectedPath && !$0.trashed }) else { issue = "Choose a note from the vault."; return }
                        let target = note.stableID.map { "zerus:" + $0 } ?? (note.path as NSString).deletingPathExtension
                        save(NoteReference(target: target, label: note.title, explicitLabel: true).url.absoluteString, fallback: note.title)
                    } else { save(address) }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
        .task { if request.destination == nil { noteDestination = savedChoice != "web" }; focused = true }
        .onChange(of: noteDestination) { savedChoice = noteDestination ? "note" : "web"; focused = true }
    }
    private func save(_ destination: String?, fallback: String? = nil) {
        do { try apply(destination, label.isEmpty ? fallback ?? "" : label) }
        catch { issue = error.localizedDescription }
    }
}
