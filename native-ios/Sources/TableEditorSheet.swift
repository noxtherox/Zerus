import SwiftUI
import UIKit

enum TableCellContent {
    static func rich(_ text: String) -> AttributedString {
        if NativeCellMarkdown.supports(text) { return NativeCellMarkdown.preview(text) }
        return (try? AttributedString(markdown: NoteReference.inlineMarkdown(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    static func plain(_ text: String) -> String { String(rich(text).characters) }
    static func imageReferences(_ text: String) -> [String] { Array(Set(rich(text).runs.compactMap { $0.imageURL?.relativeString })).sorted() }
    static func links(_ text: String) -> [URL] {
        Array(Set(rich(text).runs.compactMap { run in
            run.link ?? run.imageURL.flatMap { URL(string: "zerus-image:" + ($0.relativeString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")) }
        }))
    }
    static func drawn(_ text: String, header: Bool, alignment: MarkdownTable.Alignment) -> NSAttributedString {
        let parsed = rich(text), output = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment == .right ? .right : alignment == .center ? .center : .left
        paragraph.lineBreakMode = .byTruncatingTail
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var traits: UIFontDescriptor.SymbolicTraits = header ? [.traitBold] : []
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            let base = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: .current)
            let descriptor = intent.contains(.code) ? base.fontDescriptor.withDesign(.monospaced) ?? base.fontDescriptor : base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            var attributes: [NSAttributedString.Key: Any] = [.font: UIFont(descriptor: descriptor, size: 0), .foregroundColor: run.link == nil ? NativeThemeUIKit.text : NativeThemeUIKit.link, .paragraphStyle: paragraph]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }
}

final class TableAttachment: MarkdownAttachment, ImagePresentingTextAttachment {
    let table: MarkdownTable
    private var images: [String: UIImage]
    private(set) var presentationRevision: UInt64 = 0
    func updateImages(_ images: [String: UIImage]) {
        guard MarkdownText.imageIdentities(self.images) != MarkdownText.imageIdentities(images) else { return }
        self.images = images; presentationRevision &+= 1
    }
    init(table: MarkdownTable, width: CGFloat, images: [String: UIImage]) {
        self.table = table; self.images = images
        super.init(markdown: table.markdown, editLabel: "Edit table", summary: "\(table.rows.count - 1) rows, \(table.columns) columns. " + table.rows[0].map(TableCellContent.plain).joined(separator: ", "))
        refreshPresentation(width: width)
    }
    func refreshPresentation(width: CGFloat) {
        let width = max(140, min(width, 700)), count = min(4, table.columns)
        let cellWidth = width / CGFloat(count), padding: CGFloat = 10
        let cellHeight = max(52, min(100, UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: .current).lineHeight * 2 + padding * 2))
        let visible = table.rows.prefix(5), caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: .current)
        let label = "\(table.rows.count - 1) rows × \(table.columns) columns · Tap to edit"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let captionAttributes: [NSAttributedString.Key: Any] = [.font: caption, .foregroundColor: NativeThemeUIKit.accent, .paragraphStyle: paragraph]
        let captionWidth = width - padding * 2
        let captionHeight = ceil((label as NSString).boundingRect(
            with: CGSize(width: captionWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: captionAttributes, context: nil).height) + 2
        let height = CGFloat(visible.count) * cellHeight + captionHeight + 28
        image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            NativeThemeUIKit.codeSurface.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 12).fill()
            for (rowIndex, row) in visible.enumerated() {
                for column in 0..<count {
                    let rect = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(rowIndex) * cellHeight, width: cellWidth, height: cellHeight)
                    if rowIndex == 0 { UIColor.tertiarySystemFill.setFill(); context.fill(rect) }
                    if let reference = TableCellContent.imageReferences(row[column]).first, let image = images[reference] {
                        let area = rect.insetBy(dx: padding, dy: padding), scale = min(area.width / image.size.width, area.height / image.size.height)
                        image.draw(in: CGRect(x: area.midX - image.size.width * scale / 2, y: area.midY - image.size.height * scale / 2, width: image.size.width * scale, height: image.size.height * scale))
                    } else {
                        TableCellContent.drawn(row[column], header: rowIndex == 0, alignment: table.alignments[column]).draw(with: rect.insetBy(dx: padding, dy: padding), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                    }
                    UIColor.separator.setStroke(); context.cgContext.setLineWidth(0.5); context.cgContext.stroke(rect)
                }
            }
            (label as NSString).draw(in: CGRect(x: padding, y: height - captionHeight - 14, width: captionWidth, height: captionHeight), withAttributes: captionAttributes)
        }
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
    }
    required init?(coder: NSCoder) { return nil }
}

struct TableEditRequest: Identifiable {
    let id = UUID()
    let table: MarkdownTable
    let save: (MarkdownTable) -> Bool
}

private struct TableCellSelection: Identifiable {
    let row: Int
    let column: Int
    var id: String { "\(row):\(column)" }
}

struct TableEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: TableEditRequest
    let images: [String: UIImage]
    var onLink: (URL) -> Void = { _ in }
    @State private var table: MarkdownTable
    @State private var selected: TableCellSelection?
    @State private var query = ""
    @State private var rowPage = 0
    @State private var columnPage = 0
    @State private var undo: [MarkdownTable] = []
    @State private var redo: [MarkdownTable] = []
    @State private var error: String?
    @State private var pasteSheet = false
    private let pageRows = 20, pageColumns = 8
    init(request: TableEditRequest, images: [String: UIImage] = [:], onLink: @escaping (URL) -> Void = { _ in }) {
        self.request = request; self.images = images; self.onLink = onLink; _table = State(initialValue: request.table)
    }
    private var matchingRows: [Int] {
        table.rows.indices.dropFirst().filter { query.isEmpty || table.rows[$0].contains { TableCellContent.plain($0).localizedCaseInsensitiveContains(query) } }
    }
    private var visibleRows: [Int] { Array(matchingRows.dropFirst(rowPage * pageRows).prefix(pageRows)) }
    private var visibleColumns: Range<Int> {
        let start = min(columnPage * pageColumns, max(0, table.columns - 1))
        return start..<min(start + pageColumns, table.columns)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("\(table.rows.count - 1) rows · \(table.columns) columns").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add row", systemImage: "plus") {
                        change { $0.insertRow(at: $0.rows.count) }; query = ""; rowPage = max(0, (table.rows.count - 2) / pageRows)
                    }.labelStyle(.iconOnly).accessibilityIdentifier("table.addRow")
                }.padding()
                if let error { Text(error).font(.callout).foregroundStyle(.orange).padding(.horizontal).padding(.bottom, 10) }
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 1) {
                        gridRow(0)
                        ForEach(visibleRows, id: \.self) { gridRow($0) }
                    }.padding(16)
                }.background(Accent.paper)
                if matchingRows.isEmpty { Text(query.isEmpty ? "Add a row to start collecting." : "No matching rows.").foregroundStyle(.secondary).padding() }
                HStack {
                    Button { rowPage -= 1 } label: { Image(systemName: "chevron.left") }.disabled(rowPage == 0).accessibilityLabel("Previous rows")
                    Spacer()
                    Text(matchingRows.isEmpty ? "0 rows" : "Rows \(rowPage * pageRows + 1)–\(min((rowPage + 1) * pageRows, matchingRows.count)) of \(matchingRows.count)").font(.caption).monospacedDigit()
                    Spacer()
                    Button { rowPage += 1 } label: { Image(systemName: "chevron.right") }.disabled((rowPage + 1) * pageRows >= matchingRows.count).accessibilityLabel("Next rows")
                }.padding(.horizontal).padding(.vertical, 12)
                if table.columns > pageColumns {
                    HStack {
                        Button("Previous columns") { columnPage -= 1 }.disabled(columnPage == 0)
                        Spacer()
                        Text("\(visibleColumns.lowerBound + 1)–\(visibleColumns.upperBound)").monospacedDigit()
                        Spacer()
                        Button("Next columns") { columnPage += 1 }.disabled(visibleColumns.upperBound >= table.columns)
                    }.font(.caption).padding(.horizontal).padding(.bottom, 12)
                }
            }
            .navigationTitle("Table").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find in table")
            .onChange(of: query) { _, _ in rowPage = 0 }
            .interactiveDismissDisabled(table != request.table)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("table.save") }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button("Add column", systemImage: "rectangle.split.3x1") { change { $0.insertColumn(at: $0.columns) }; columnPage = (table.columns - 1) / pageColumns }
                        Button("Undo", systemImage: "arrow.uturn.backward") { if let prior = undo.popLast() { redo.append(table); table = prior; resetPages() } }.disabled(undo.isEmpty)
                        Button("Redo", systemImage: "arrow.uturn.forward") { if let next = redo.popLast() { undo.append(table); table = next; resetPages() } }.disabled(redo.isEmpty)
                        Button("Reset column widths") { change { $0.resetWidths() } }
                        Button("Paste a spreadsheet", systemImage: "doc.on.clipboard") { pasteSheet = true }
                        Button("Copy Markdown", systemImage: "doc.on.doc") { UIPasteboard.general.string = table.markdown }
                        ShareLink(item: table.markdown) { Label("Share table", systemImage: "square.and.arrow.up") }
                    } label: { Label("Table actions", systemImage: "ellipsis.circle") }
                }
            }
            .sheet(item: $selected) { selection in
                TableCellEditor(table: table, row: selection.row, column: selection.column, images: images) { value, alignment, width in
                    let widthChanged = width != table.widths?[selection.column]
                    change {
                        $0.rows[selection.row][selection.column] = value
                        $0.alignments[selection.column] = alignment
                        if widthChanged { if let width { $0.setWidth(width, column: selection.column) } }
                    }
                }
            }
            .sheet(isPresented: $pasteSheet) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "tablecells").font(.largeTitle).foregroundStyle(Accent.color)
                        Text("Paste a spreadsheet").font(.title2.bold())
                        Text("Copied rows replace this table. The first row becomes the header; you can undo the replacement before saving.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                        PasteButton(payloadType: String.self) { values in
                            guard let value = values.first, let replacement = MarkdownTable.spreadsheet(value) else { error = "Copy cells from a spreadsheet, including at least two columns."; pasteSheet = false; return }
                            change { $0 = replacement }; resetPages(); pasteSheet = false
                        }
                    }.padding(30).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pasteSheet = false } } }
                }.presentationDetents([.medium, .large])
            }
        }
    }
    private func gridRow(_ row: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(visibleColumns), id: \.self) { column in
                Button { selected = TableCellSelection(row: row, column: column) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TableCellContent.rich(table.rows[row][column])).font(row == 0 ? .headline : .body)
                        ForEach(TableCellContent.imageReferences(table.rows[row][column]), id: \.self) { reference in
                            if let image = images[reference] { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 64) }
                            else { Image(systemName: "photo").foregroundStyle(.secondary) }
                        }
                    }.allowsHitTesting(false)
                        .lineLimit(3).frame(maxWidth: .infinity, minHeight: 48, alignment: table.alignments[column] == .right ? .trailing : table.alignments[column] == .center ? .center : .leading)
                        .padding(12).frame(width: CGFloat(table.widths?[column] ?? 180))
                        .background(row == 0 ? Color(uiColor: NativeThemeUIKit.tableHeader) : Accent.card)
                }.buttonStyle(.plain).accessibilityLabel("\(row == 0 ? "Header" : "Row \(row)"), column \(column + 1): \(TableCellContent.plain(table.rows[row][column]))")
                .accessibilityIdentifier("table.cell.\(row).\(column)")
                .contextMenu {
                    Button("Edit cell") { selected = TableCellSelection(row: row, column: column) }
                    ForEach(TableCellContent.links(table.rows[row][column]), id: \.self) { url in
                        Button(url.scheme == "zerus-image" ? "Open image" : "Open \(NoteReference(url: url)?.label ?? url.host ?? url.relativeString)", systemImage: "link") { save(follow: url) }
                    }
                    Button("Insert row above") { change { $0.insertRow(at: row) }; resetPages() }
                    Button("Insert row below") { change { $0.insertRow(at: row + 1) }; resetPages() }
                    Button("Insert column before") { change { $0.insertColumn(at: column) }; resetPages() }
                    Button("Insert column after") { change { $0.insertColumn(at: column + 1) }; resetPages() }
                    Button("Delete row", role: .destructive) { change { $0.removeRow(at: row) }; resetPages() }.disabled(table.rows.count <= 1)
                    Button("Delete column", role: .destructive) { change { $0.removeColumn(at: column) }; resetPages() }.disabled(table.columns <= 1)
                }
            }
        }
    }
    private func change(_ action: (inout MarkdownTable) -> Void) {
        let prior = table; action(&table)
        if prior != table { undo.append(prior); if undo.count > 30 { undo.removeFirst() }; redo = []; error = nil }
    }
    private func resetPages() { rowPage = 0; columnPage = 0; query = "" }
    private func save(follow url: URL? = nil) {
        if request.save(table) { if let url { onLink(url) }; dismiss() }
        else { error = "The note changed while the table was open. Your edits are kept here; copy or share the table before reopening it." }
    }
}

private struct TableCellEditor: View {
    @Environment(\.dismiss) private var dismiss
    let column: Int
    let images: [String: UIImage]
    let save: (String, MarkdownTable.Alignment, Int?) -> Void
    @State private var value: String
    @State private var alignment: MarkdownTable.Alignment
    @State private var width: Int?
    @State private var source: Bool
    @State private var issue: String?
    @State private var link: NativeCellLinkRequest?
    @StateObject private var editorActions = NativeCellEditorActions()
    init(table: MarkdownTable, row: Int, column: Int, images: [String: UIImage], save: @escaping (String, MarkdownTable.Alignment, Int?) -> Void) {
        self.column = column; self.images = images; self.save = save
        _value = State(initialValue: table.rows[row][column]); _alignment = State(initialValue: table.alignments[column]); _width = State(initialValue: table.widths?[column])
        _source = State(initialValue: !NativeCellMarkdown.supports(table.rows[row][column]))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Cell content") {
                    Toggle("Markdown source", isOn: $source).disabled(issue != nil || !NativeCellMarkdown.supports(value)).accessibilityIdentifier("table.cell.source")
                    NativeCellTextEditor(markdown: value, source: source, images: images, changed: { value = $0 }, issue: { issue = $0 }, link: { link = $0 }, actions: editorActions).frame(minHeight: 160, idealHeight: 220).background(Accent.editor)
                    if let issue { Text(issue).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("table.cell.issue") }
                    Text(source ? "Source editing preserves this cell’s Markdown. Keep its content on one line." : "Select text to format it, or choose a style before typing. Return dismisses the keyboard.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Preview") {
                    Text(TableCellContent.rich(value)).allowsHitTesting(false)
                    ForEach(TableCellContent.imageReferences(value), id: \.self) { reference in
                        if let image = images[reference] { Image(uiImage: image).resizable().scaledToFit() }
                    }
                }
                Section("Column \(column + 1)") {
                    Picker("Alignment", selection: $alignment) { ForEach(MarkdownTable.Alignment.allCases) { Text($0.rawValue).tag($0) } }
                    Stepper("Width: \(width ?? 180) pt", value: Binding(get: { width ?? 180 }, set: { width = $0 }), in: 80...720, step: 20)
                }
            }
            .navigationTitle("Edit cell").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let committed = editorActions.commit() { save(committed, alignment, width); dismiss() } }.disabled(issue != nil || value.contains("\n") || value.contains("\r")).accessibilityIdentifier("table.cell.done") }
            }
            .sheet(item: $link) { NativeCellLinkSheet(request: $0) }
        }
    }
}

private struct NativeCellLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    let request: NativeCellLinkRequest
    @State private var label: String
    @State private var address: String
    @State private var note: Bool
    @State private var noteURL: URL?
    @State private var choosingNote = false
    @State private var issue: String?
    init(request: NativeCellLinkRequest) {
        self.request = request; _label = State(initialValue: request.label)
        _address = State(initialValue: NoteReference(url: request.url ?? URL(string: "about:blank")!) == nil ? request.url?.relativeString ?? "" : "")
        _note = State(initialValue: request.url.flatMap(NoteReference.init(url:)) != nil)
        _noteURL = State(initialValue: request.url.flatMap(NoteReference.init(url:)) == nil ? nil : request.url)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text", text: $label).accessibilityIdentifier("table.cell.link.label")
                    Picker("Destination", selection: $note) { Text("Web address").tag(false); Text("Note").tag(true) }
                    if note {
                        Button { choosingNote = true } label: { Label(noteURL.flatMap(NoteReference.init(url:))?.label ?? "Choose a note", systemImage: "doc.text") }.accessibilityIdentifier("table.cell.link.note")
                    } else {
                        TextField("https://example.com", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("table.cell.link.address")
                    }
                }
                if request.url != nil { Section { Button("Remove link") { commit(nil) }.accessibilityIdentifier("table.cell.link.remove") } }
                if let issue { Section { Text(issue).foregroundStyle(.orange) } }
            }.navigationTitle("Cell link").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if note { if let url = noteURL { commit(url) } else { issue = "Choose a note first." } }
                        else if let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? ""), !["https", "http"].contains(url.scheme?.lowercased() ?? "") || url.host?.isEmpty == false { commit(url) }
                        else { issue = "Enter a complete web, email or telephone address." }
                    }.disabled(label.isEmpty || label.contains("\n") || label.contains("\r") || (note && label.contains("]]"))).accessibilityIdentifier("table.cell.link.save") }
                }
                .sheet(isPresented: $choosingNote) {
                    NotePicker(title: "Link to a note", multiple: false, selected: []) { ids in
                        guard let chosen = vault.notes.first(where: { ids.contains($0.id) }) else { return }
                        let target = chosen.stableID.map { "zerus:" + $0 } ?? chosen.path
                        noteURL = NoteReference(wikilink: "[[" + target + "|" + chosen.title + "]]")?.url
                        if label.isEmpty { label = chosen.title }
                    }
                }
        }
    }
    private func commit(_ url: URL?) {
        if request.apply(label, url) { dismiss() }
        else { issue = "The cell changed while this link was open. Cancel and select its text again." }
    }
}
