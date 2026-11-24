import SwiftUI
import AppKit

struct MacTableRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let path: String
    let source: String
    let range: NSRange?
    let table: MarkdownTable
}
struct MacTableEditor: View {
    let request: MacTableRequest
    let save: (String) throws -> Void
    @State private var table: MarkdownTable
    @State private var selectedRow = 0
    @State private var selectedColumn = 0
    private struct CellFocus: Hashable { let row: Int; let column: Int }
    @FocusState private var focusedCell: CellFocus?
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    init(request: MacTableRequest, save: @escaping (String) throws -> Void) { self.request = request; self.save = save; _table = State(initialValue: request.table) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("Edit table").font(.title2.bold()); Spacer(); Text("\(table.rows.count - 1) rows · \(table.columns) columns").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Add row") { finishCellEditing(); table.insertRow(at: table.rows.count) }
                Button("Add column") { finishCellEditing(); table.insertColumn(at: table.columns) }
                Menu("Selected cell") {
                    Button("Insert row above") { finishCellEditing(); table.insertRow(at: selectedRow) }
                    Button("Insert row below") { finishCellEditing(); table.insertRow(at: selectedRow + 1) }
                    Button("Insert column before") { finishCellEditing(); table.insertColumn(at: selectedColumn) }
                    Button("Insert column after") { finishCellEditing(); table.insertColumn(at: selectedColumn + 1) }
                    Divider()
                    Button("Move row up") { moveRow(-1) }.disabled(selectedRow == 0)
                    Button("Move row down") { moveRow(1) }.disabled(selectedRow + 1 >= table.rows.count)
                    Button("Move column left") { moveColumn(-1) }.disabled(selectedColumn == 0)
                    Button("Move column right") { moveColumn(1) }.disabled(selectedColumn + 1 >= table.columns)
                    Divider()
                    Button("Remove row") { finishCellEditing(); table.removeRow(at: selectedRow); selectedRow = min(selectedRow, table.rows.count - 1) }.disabled(table.rows.count < 2)
                    Button("Remove column") { finishCellEditing(); table.removeColumn(at: selectedColumn); selectedColumn = min(selectedColumn, table.columns - 1) }.disabled(table.columns < 2)
                    Divider()
                    ForEach(MarkdownTable.Alignment.allCases) { alignment in Button("Align " + alignment.rawValue) { table.alignments[selectedColumn] = alignment } }
                    Button("Make column narrower") { table.setWidth((table.widths?[selectedColumn] ?? 160) - 40, column: selectedColumn) }
                    Button("Make column wider") { table.setWidth((table.widths?[selectedColumn] ?? 160) + 40, column: selectedColumn) }
                    Button("Reset column widths") { table.resetWidths() }
                }
                Spacer()
                Button("Paste spreadsheet") { if let value = NSPasteboard.general.string(forType: .string), let pasted = MarkdownTable.spreadsheet(value) { finishCellEditing(); table = pasted; selectedRow = 0; selectedColumn = 0 } else { issue = "Copy tab-separated cells from a spreadsheet first." } }
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0) {
                    ForEach(table.rows.indices, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<table.columns, id: \.self) { column in
                                TextField("", text: Binding(get: { table.rows[row][column] }, set: { table.rows[row][column] = $0 }))
                                    .font(.system(size: 13, weight: row == 0 ? .semibold : .regular)).textFieldStyle(.plain).padding(9)
                                    .frame(width: CGFloat(table.widths?[column] ?? 180), alignment: .leading)
                                    .background(selectedRow == row && selectedColumn == column ? Color.accentColor.opacity(0.09) : row == 0 ? Color.secondary.opacity(0.07) : .clear)
                                    .border(.quaternary, width: 0.5)
                                    .focused($focusedCell, equals: CellFocus(row: row, column: column))
                                    .accessibilityLabel("Row \(row + 1), column \(column + 1)")
                            }
                        }
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            Text("Cells use inline Markdown. Widths and alignment remain portable in the saved table.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Copy Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(table.markdown, forType: .string) }
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save table") { finishCellEditing(); do { try save(table.markdown); dismiss() } catch { issue = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 760, minHeight: 500)
            .onChange(of: focusedCell) { _, cell in
                if let cell { selectedRow = cell.row; selectedColumn = cell.column }
            }
    }
    private func finishCellEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusedCell = nil
    }
    private func moveRow(_ offset: Int) {
        finishCellEditing()
        let destination = selectedRow + offset
        if table.moveRow(from: selectedRow, to: destination) {
            selectedRow = destination; focusedCell = CellFocus(row: destination, column: selectedColumn)
        }
    }
    private func moveColumn(_ offset: Int) {
        finishCellEditing()
        let destination = selectedColumn + offset
        if table.moveColumn(from: selectedColumn, to: destination) {
            selectedColumn = destination; focusedCell = CellFocus(row: selectedRow, column: destination)
        }
    }
}
@MainActor final class MacTableChange {
    var scope: UUID { request.workspaceID }
    let request: MacTableRequest
    let replacement: String
    var result: Result<Void, Error>?
    init(request: MacTableRequest, replacement: String) { self.request = request; self.replacement = replacement }
}
struct MacCodeRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let path: String
    let source: String
    let range: NSRange?
    let code: FencedCode?
    func replacing(body: String, info: String) -> String {
        if let range, let block = MacCodeBlock.blocks(in: source).first(where: { $0.range == range }) {
            return block.replacing(body: body, info: info)
        }
        let original = code ?? FencedCode.blocks(in: "```\n\n```").first!.code
        return original.replacing(body: body, info: info).markdown
    }
}
/// The attachment chooser commits through the editor, preserving its Undo history.
@MainActor final class MacAttachmentImport {
    let scope: UUID
    let path: String
    let source: String
    let fragment: NativeClipboardFragment
    var task: Task<Void, Error>?
    init(scope: UUID, path: String, source: String, fragment: NativeClipboardFragment) {
        self.scope = scope; self.path = path; self.source = source; self.fragment = fragment
    }
}

struct MacEditorCommand {
    let scope: UUID
    let path: String
    let action: String
}
/// A synchronous, scoped command lets the sheet keep its text if the editor rejects it.
@MainActor final class MacCodeChange {
    var scope: UUID { request.workspaceID }
    let request: MacCodeRequest
    let replacement: String
    var result: Result<Void, Error>?
    init(request: MacCodeRequest, replacement: String) { self.request = request; self.replacement = replacement }
}
struct MacCodeEditor: View {
    let request: MacCodeRequest
    let save: (String) throws -> Void
    @State private var language = ""
    @State private var code = ""
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Code block").font(.headline)
            TextField("Language (optional)", text: $language)
            TextEditor(text: $code).font(.system(.body, design: .monospaced)).autocorrectionDisabled(true).frame(minHeight: 250, maxHeight: .infinity)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Copy code") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save code") {
                    do { try save(request.replacing(body: code, info: language)); dismiss() }
                    catch { issue = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 720, height: 520).onAppear { language = request.code?.info ?? ""; code = request.code?.body ?? "" }
    }
}
