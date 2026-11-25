import SwiftUI
import UniformTypeIdentifiers

private struct MacCalendarDay: Identifiable { let id = UUID(); let date: Date; let name: String }
private struct MacCollectionRelation: Identifiable { let id = UUID(); let path: String; let name: String }

/// Resolve the field inventory once per collection update. Child state changes
/// and each card reuse it instead of scanning every note's schema repeatedly.
struct MacCollectionViews: View {
    @Bindable var store: MacWorkspace
    var noteMenu: (NoteDocument) -> AnyView
    var body: some View {
        let fields = store.collectionFields
        MacCollectionBody(selection: store.collectionSelection, store: store, noteMenu: noteMenu, fields: fields)
    }
}

private struct MacCollectionBody: View {
    @ObservedObject var selection: MacCollectionSelectionState
    @Environment(\.macTheme) private var theme
    @AppStorage("zerus.mac.dateFormat") private var dateFormat = "DD/MM/YYYY"
    @Bindable var store: MacWorkspace
    var noteMenu: (NoteDocument) -> AnyView
    @State private var edit: MacPropertyEdit?
    @State private var relation: MacCollectionRelation?
    @State private var plan: NativeBulkPlan?
    @State private var review = false
    @State private var reviewScope: MacBoardScope?
    @State private var month = Calendar.current.startOfDay(for: Date())
    @State private var moving = false
    @State private var selectedDay: MacCalendarDay?
    @State private var collapsedGroups = Set<String>()
    private struct GalleryScope: Equatable { let workspace: UUID; let folder: String; let folderCollection: Bool; let property: String?; let mode: String }
    private var galleryScope: GalleryScope { .init(workspace: store.workspaceID, folder: store.destination, folderCollection: store.folderCollection, property: grouping?.id, mode: store.viewMode) }
    let fields: [NativePropertyDefinition]
    private var groupable: [NativePropertyDefinition] { fields.filter { (store.viewMode == "Gallery" || $0.type != .relation) && $0.type != .unsupported && !($0.type == .list && $0.multiple) } }
    private var grouping: NativePropertyDefinition? { groupable.first { $0.name.caseInsensitiveCompare(store.collectionLayout.groupBy ?? "") == .orderedSame } }
    private var calendarProperty: NativePropertyDefinition? { fields.first { $0.type == .date && $0.name.caseInsensitiveCompare(store.collectionLayout.dateProperty ?? "") == .orderedSame } }
    private var visibleFields: [NativePropertyDefinition] { store.collectionLayout.visibleProperties.compactMap { name in fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } } }
    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            Group {
                if store.viewMode == "Kanban" { board }
                else if store.viewMode == "Table" { table }
                else if store.viewMode == "Calendar" { calendar }
                else { gallery }
            }.modifier(MacCollectionKeyboard(store: store))
        }
        .onChange(of: galleryScope) { collapsedGroups = []; plan = nil; review = false; reviewScope = nil }
        .macSheet(item: $selectedDay) { day in
            let snapshot = MacCollectionValues.calendar(notes: store.collection, name: day.name, month: month)
            let order = day.name == calendarProperty?.name ? snapshot.order : calendarOrder
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day().year()).font(.title2); Spacer(); Button("Done") { selectedDay = nil } }
                ScrollView { LazyVStack(spacing: 10) { ForEach(snapshot.dated[MacCollectionValues.wireDate(day.date)] ?? []) { note in
                    HStack { Button { selectedDay = nil; activate(note, order: order) } label: { VStack(alignment: .leading, spacing: 5) { Text(note.title); propertySummary(note) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selectedPaths.contains(note.path) ? .isSelected : []).overlay(MacAlternateOpen { selectedDay = nil; openInTab(note) }.accessibilityHidden(true)); Spacer(); Button("Edit date…") { selectedDay = nil; if let field = fields.first(where: { $0.name == day.name }) { editCell(note, field) } } }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                } } }
            }.padding(24).frame(width: 560, height: 430)
        }
        .macSheet(item: $edit) { MacPropertyEditor(store: store, edit: $0) }
        .macSheet(item: $relation) { MacRelationEditor(store: store, name: $0.name, path: $0.path) }
        .confirmationDialog(plan?.label ?? "Move notes?", isPresented: $review) {
            if plan?.hasChanges == true { Button("Apply changes") { Task { await commit() } } }
            else { Button("Close", role: .cancel) {} }
        } message: { Text("Updates these notes:\n" + (plan?.changedNotes.joined(separator: "\n") ?? "") + (plan?.issues.isEmpty == false ? "\n\nSkipped:\n" + plan!.issues.map { $0.path + ": " + $0.reason }.joined(separator: "\n") : "")) }
    }
    private var controls: some View {
        HStack(spacing: 14) {
            MacViewModeMenu(store: store)
            if store.viewMode == "Kanban" || store.viewMode == "Gallery" {
                Picker("Group by", selection: Binding(get: { grouping?.name ?? "" }, set: { name in update { $0.groupBy = name.isEmpty ? nil : name } })) {
                    Text("No grouping").tag(""); ForEach(groupable) { Text($0.name).tag($0.name) }
                }.frame(maxWidth: 280)
            }
            if store.viewMode == "Calendar" {
                Picker("Date property", selection: Binding(get: { calendarProperty?.name ?? "" }, set: { name in update { $0.dateProperty = name.isEmpty ? nil : name } })) {
                    Text("Choose date").tag(""); ForEach(fields.filter { $0.type == .date }) { Text($0.name).tag($0.name) }
                }.frame(maxWidth: 280)
            }
            Menu {
                ForEach(fields) { field in Toggle(field.name, isOn: Binding(get: { store.collectionLayout.visibleProperties.contains(field.name) }, set: { enabled in update { layout in if enabled { layout.visibleProperties.append(field.name) } else { layout.visibleProperties.removeAll { $0 == field.name } } } })) }
            } label: { Label("Properties", systemImage: "slider.horizontal.3") }.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            if moving { ProgressView().controlSize(.small) }
        }.padding(.horizontal, 16).padding(.vertical, 7)
    }
    private func update(_ transform: (inout MacCollectionLayout) -> Void) {
        var next = store.collectionLayout; transform(&next)
        Task { await store.updateCollectionLayout(next) }
    }
    private func activate(_ note: NoteDocument, order: [String]? = nil) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? [], origin = store.workspaceID
        Task { guard origin == store.workspaceID else { return }; await store.activateCollectionNote(note.path, modifiers: modifiers, order: order) }
    }
    private func openInTab(_ note: NoteDocument) {
        let origin = store.workspaceID
        Task { guard origin == store.workspaceID else { return }; await store.openNote(note.path, newTab: true) }
    }
    // Board cards share the rendered board's column snapshot. Rebuilding it in
    // each menu would reparse every member note for every visible card.
    private func card(_ note: NoteDocument, order: [String]? = nil, boardColumns: [String?] = []) -> some View {
        Button { activate(note, order: order) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack { if store.selecting { Image(systemName: store.selectedPaths.contains(note.path) ? "checkmark.circle.fill" : "circle") }; Text(note.title).font(.headline).lineLimit(2); Spacer(minLength: 0) }
                MacCollectionCover(note: note, io: store.io, workspaceID: store.workspaceID, fileDates: store.collectionFileDates)
                MacCollectionExcerpt(note: note, workspaceID: store.workspaceID, lines: 3).font(.caption).foregroundStyle(.secondary)
                propertySummary(note)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(store.selectedPaths.contains(note.path) ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selectedPaths.contains(note.path) ? .isSelected : [])
            .modifier(MacGalleryAlternateOpenTarget(shared: store.viewMode == "Gallery") { openInTab(note) })
            .contextMenu { noteMenu(note); if store.viewMode == "Calendar", let name = store.collectionLayout.dateProperty, let field = fields.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { Button("Edit date…") { editCell(note, field) } }; if let grouping, store.viewMode == "Kanban" { Menu("Move to column") { ForEach(boardColumns.indices, id: \.self) { index in let column = boardColumns[index]; Button(columnTitle(column, field: grouping)) { move(paths: store.boardSelection(for: note), field: grouping, column: column) } } } } }
            .overlay(alignment: .topTrailing) {
                if store.viewMode == "Kanban", let field = grouping {
                    Menu { ForEach(boardColumns.indices, id: \.self) { index in let column = boardColumns[index]; Button(columnTitle(column, field: field)) { move(paths: store.boardSelection(for: note), field: field, column: column) } } } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20).background(.background, in: Circle()) }.menuStyle(.borderlessButton).fixedSize().padding(5).help("Move \(note.title) to column").accessibilityLabel("Move " + note.title + " to column")
                }
            }

    }
    private func propertySummary(_ note: NoteDocument, lineLimit: Int = 2) -> some View {
        ForEach(visibleFields) { field in
            if let value = MacCollectionValues.value(note, name: field.name) {
                let text = field.name + ": " + display(value, field: field)
                Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(lineLimit).help(text)
            }
        }
    }
    private enum GalleryAnchor: Hashable { case start }
    private var gridScope: MacNoteListScope {
        .init(workspace: store.workspaceID, destination: store.destination, folder: store.folderCollection, query: store.query, filters: store.filters, hideSubtypes: store.hideSubtypes)
    }
    private var gallery: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(GalleryAnchor.start)
                    if store.collection.isEmpty {
                        ContentUnavailableView("No notes match this view", systemImage: "square.grid.2x2")
                    } else if let grouping {
                        LazyVStack(spacing: 0) {
                            ForEach(store.galleryGroups(name: grouping.name, relations: grouping.type == .relation)) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        if !collapsedGroups.insert(group.id).inserted { collapsedGroups.remove(group.id) }
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down").frame(width: 12)
                                            Text(galleryLabel(group, field: grouping)).font(.headline)
                                            Text("\(group.notes.count)").font(.caption).foregroundStyle(.secondary)
                                            Spacer(minLength: 0)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(MacBoxButtonStyle()).accessibilityValue(collapsedGroups.contains(group.id) ? "Collapsed" : "Expanded")
                                    if !collapsedGroups.contains(group.id) {
                                        let order = group.notes.map(\.path)
                                        MacProgressiveNoteGrid(notes: group.notes, scope: gridScope) { card($0, order: order) }.id(grouping.id + ":" + group.id)
                                    }
                                }.padding(16)
                            }
                        }
                    } else { MacProgressiveNoteGrid(notes: store.collection, scope: gridScope) { card($0) }.padding(16) }
                }
            }
            .modifier(MacGalleryAlternateOpenHost())
            .onChange(of: gridScope) { _, _ in reader.scrollTo(GalleryAnchor.start, anchor: .top) }
            .onChange(of: galleryScope) { _, _ in reader.scrollTo(GalleryAnchor.start, anchor: .top) }
        }
    }
    private func galleryLabel(_ group: MacCollectionGroup, field: NativePropertyDefinition) -> String {
        guard let value = group.value else { return "No value" }
        if let flag = group.checkbox { return flag ? "Checked" : "Unchecked" }
        if field.type == .relation {
            return group.relationPath.flatMap { path in store.notes.first { $0.path == path }?.title } ?? value
        }
        return display(.text(value), field: field)
    }
    private func columnTitle(_ column: String?, field: NativePropertyDefinition) -> String { column.map { display(.text($0), field: field) } ?? "No value" }
    private var board: some View {
        Group {
            if let field = grouping, let snapshot = store.boardSnapshot {
                let scope = snapshot.scope, groups = snapshot.groups
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 15) {
                        ForEach(groups.indices, id: \.self) { index in
                            let column = groups[index].value, notes = groups[index].notes
                            let order = notes.map(\.path)
                            LazyVStack(alignment: .leading, spacing: 10) {
                                HStack { Text(columnTitle(column, field: field)).font(.headline); Text("\(notes.count)").foregroundStyle(.secondary); Spacer(); Button { reorder(field, index, -1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0).help("Move column left"); Button { reorder(field, index, 1) } label: { Image(systemName: "chevron.right") }.disabled(index == groups.count - 1).help("Move column right") }.buttonStyle(MacBoxButtonStyle()).disabled(moving || store.busy)
                                    .draggable(MacBoardTransfer(scope: scope, item: .column(column)))
                                    .accessibilityLabel(columnTitle(column, field: field) + " column, \(notes.count) notes")
                                ForEach(notes) { note in
                                    card(note, order: order, boardColumns: scope.columns).draggable(MacBoardTransfer(scope: scope, item: .notes(store.boardSelection(for: note))))
                                }
                                Color.clear.frame(height: 70)
                            }.padding(12).frame(width: 245).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle()).id(column ?? "__no_value__")
                                // The highlight lives in the column's own state, so hovering
                                // during a drag re-renders one column outline, not the board.
                                .modifier(MacBoardColumnDrop { transfer in
                                    guard !moving, store.acceptsBoardDrop(transfer, target: column, scope: scope) else { return false }
                                    receive(transfer, target: column, scope: scope)
                                    return true
                                })

                        }
                    }.padding(16)
                }
            } else { ContentUnavailableView("Choose a grouping property", systemImage: "rectangle.split.3x1", description: Text("Use Group by to create columns from a single-value property.")) }
        }
    }
    private func reorder(_ field: NativePropertyDefinition, _ index: Int, _ offset: Int) {
        guard !moving, !store.busy, let scope = store.boardScope, scope.columns.indices.contains(index + offset) else { return }
        receive(.init(scope: scope, item: .column(scope.columns[index])), target: scope.columns[index + offset], scope: scope)
    }
    private func receive(_ transfer: MacBoardTransfer, target: String?, scope: MacBoardScope) {
        guard !moving, !store.busy else { return }
        if case .notes(let paths) = transfer.item, paths.count == 1 {
            // One card moves at once; its note is written in the background.
            store.moveBoardCard(transfer, target: target, scope: scope) { prepared in plan = prepared; reviewScope = scope; review = true }
            return
        }
        moving = true
        Task { @MainActor in
            defer { moving = false }
            do {
                switch transfer.item {
                case .column: try await store.reorderBoardDrop(transfer, target: target, scope: scope)
                case .notes(let paths):
                    let prepared = try await store.prepareBoardDrop(transfer, target: target, scope: scope)
                    if paths.count > 1 || !prepared.issues.isEmpty { plan = prepared; reviewScope = scope; review = true }
                    else { try await store.commitBoardDrop(prepared, scope: scope) }
                }
            } catch { if scope.workspace == store.workspaceID { store.issue = error.localizedDescription } }
        }
    }
    private func move(paths: Set<String>, field: NativePropertyDefinition, column: String?) {
        guard let scope = store.boardScope, scope.field == field.name else { return }
        let transfer = MacBoardTransfer(scope: scope, item: .notes(paths))
        // Menu choices use the same live admission as pointer drops. Choosing
        // the current column is a no-op, not a stale-board error.
        guard store.acceptsBoardDrop(transfer, target: column, scope: scope) else { return }
        receive(transfer, target: column, scope: scope)
    }
    private func commit() async {
        guard let plan, let scope = reviewScope else { return }; moving = true; defer { moving = false }
        do { try await store.commitBoardDrop(plan, scope: scope) }
        catch { if scope.workspace == store.workspaceID { store.issue = error.localizedDescription } }
    }
    /// Column widths fill the pane: the name takes 1.6 shares, each property
    /// one share. Narrow windows keep the minimums and scroll horizontally.
    private struct TableLayout {
        static let check: CGFloat = 34, folder: CGFloat = 150, modified: CGFloat = 84
        let name: CGFloat, field: CGFloat, showsFolder: Bool, total: CGFloat
        init(width: CGFloat, fields: Int, showsFolder: Bool) {
            let dividers = CGFloat(fields + (showsFolder ? 3 : 2))
            let fixed = Self.check + Self.modified + (showsFolder ? Self.folder : 0) + dividers
            let share = max(width - fixed, 0) / (1.6 + CGFloat(fields))
            name = max(share * 1.6, 220); field = max(share, 150); self.showsFolder = showsFolder
            total = fixed + name + field * CGFloat(fields)
        }
    }
    private var table: some View {
        let notes = store.collection
        // A type or folder view would repeat its own name on every row.
        let showsFolder = Set(notes.lazy.map(\.folder)).count > 1
        return GeometryReader { proxy in
            let layout = TableLayout(width: proxy.size.width - 32, fields: visibleFields.count, showsFolder: showsFolder)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(notes) { note in tableRow(note, layout) }
                        if notes.isEmpty { Text("No notes match this view").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(28) }
                    } header: { tableHeader(layout, notes: notes) }
                }
                .frame(width: layout.total)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(gridLine))
                .padding(16).padding(.bottom, selection.selecting || !selection.paths.isEmpty ? 64 : 0)
            }
        }
    }
    private var gridLine: Color { theme.color(.text).opacity(0.1) }
    private var columnDivider: some View { Rectangle().fill(gridLine).frame(width: 1) }
    private func tableHeader(_ layout: TableLayout, notes: [NoteDocument]) -> some View {
        let all = !notes.isEmpty && notes.allSatisfy { selection.paths.contains($0.path) }
        let sort = store.filters.sort
        return HStack(spacing: 0) {
            Button { if all { store.clearCollectionSelection() } else { store.selectAllCollectionNotes() } } label: {
                Image(systemName: all ? "checkmark.square.fill" : selection.paths.isEmpty ? "square" : "minus.square.fill")
                    .foregroundStyle(selection.paths.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.color(.accent)))
                    .frame(width: TableLayout.check).frame(maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).help(all ? "Deselect all" : "Select all").accessibilityLabel(all ? "Deselect all notes" : "Select all notes")
            columnDivider
            sortHeader("Name", width: layout.name, arrow: sort == .titleAscending ? "arrow.up" : sort == .titleDescending ? "arrow.down" : nil) {
                setSort(sort == .titleAscending ? .titleDescending : .titleAscending)
            }
            if layout.showsFolder { columnDivider; headerLabel("Folder").frame(width: TableLayout.folder, alignment: .leading) }
            ForEach(visibleFields) { field in columnDivider; headerLabel(field.name).frame(width: layout.field, alignment: .leading) }
            columnDivider
            sortHeader("Modified", width: TableLayout.modified, trailing: true, arrow: sort == .updatedDescending ? "arrow.down" : sort == .updatedAscending ? "arrow.up" : nil) {
                setSort(sort == .updatedDescending ? .updatedAscending : .updatedDescending)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Rectangle().fill(gridLine).frame(height: 1) }
    }
    private func headerLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 8)
    }
    private func sortHeader(_ title: String, width: CGFloat, trailing: Bool = false, arrow: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if trailing { Spacer(minLength: 0) }
                Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                if let arrow { Image(systemName: arrow).font(.system(size: 9, weight: .bold)).foregroundStyle(theme.color(.text)) }
                if !trailing { Spacer(minLength: 0) }
            }.padding(.horizontal, 10).padding(.vertical, 8).frame(width: width)
        }.buttonStyle(MacBoxButtonStyle()).help("Sort by \(title.lowercased())")
    }
    private func setSort(_ sort: NativeNoteSort) { var next = store.filters; next.sort = sort; store.changeCollectionFilters(next) }
    private func tableRow(_ note: NoteDocument, _ layout: TableLayout) -> some View {
        let selected = selection.paths.contains(note.path)
        return HStack(spacing: 0) {
            Button { toggleSelection(note) } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? AnyShapeStyle(theme.color(.accent)) : AnyShapeStyle(.tertiary))
                    .padding(.top, 10).frame(width: TableLayout.check).frame(maxHeight: .infinity, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel((selected ? "Deselect " : "Select ") + note.title)
            columnDivider
            Button { activate(note) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if note.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(theme.color(.accent)).accessibilityLabel("Pinned") }
                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 9).frame(width: layout.name, alignment: .leading).frame(maxHeight: .infinity, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(selected ? .isSelected : []).overlay(MacAlternateOpen { openInTab(note) }.accessibilityHidden(true))
            if layout.showsFolder {
                columnDivider
                Text(note.folder.isEmpty ? "Inbox" : note.folder).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 10).frame(width: TableLayout.folder, alignment: .leading).frame(maxHeight: .infinity, alignment: .top)
            }
            ForEach(visibleFields) { field in
                columnDivider
                Button { editCell(note, field) } label: {
                    tableValue(note, field).padding(.horizontal, 10).padding(.vertical, 9)
                        .frame(width: layout.field, alignment: .leading).frame(maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
                }.buttonStyle(MacBoxButtonStyle()).disabled(note.trashed).help("Edit \(field.name) for \(note.title)")
            }
            columnDivider
            Text(note.modified, format: .dateTime.day().month(.abbreviated)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 10).frame(width: TableLayout.modified, alignment: .trailing).frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(selected ? theme.color(.accent).opacity(0.12) : store.selection == note.path ? theme.color(.text).opacity(0.05) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(gridLine).frame(height: 1) }
        .contextMenu { noteMenu(note) }
    }
    private func toggleSelection(_ note: NoteDocument) {
        let modifiers = (NSApp.currentEvent?.modifierFlags ?? []).union(.command), origin = store.workspaceID
        // A checkbox enters selection mode, so later row clicks keep selecting.
        store.selecting = true
        Task { guard origin == store.workspaceID else { return }; await store.activateCollectionNote(note.path, modifiers: modifiers) }
    }
    /// Relations and lists read as chips like the property pane; empty cells
    /// say so instead of showing a dash that looks like data.
    @ViewBuilder private func tableValue(_ note: NoteDocument, _ field: NativePropertyDefinition) -> some View {
        if let value = MacCollectionValues.value(note, name: field.name), !value.display.isEmpty {
            switch field.type {
            case .relation, .list:
                let labels = field.type == .relation ? value.selections.map(relationTitle) : value.selections
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(labels.prefix(6).enumerated()), id: \.offset) { _, label in
                        Text(label).font(.system(size: 12)).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(theme.color(.text).opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                    }
                    if labels.count > 6 { Text("+\(labels.count - 6) more").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            case .checkbox:
                Image(systemName: value.display == "true" ? "checkmark.square.fill" : "square").foregroundStyle(value.display == "true" ? AnyShapeStyle(theme.color(.accent)) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(value.display == "true" ? "Checked" : "Unchecked")
            default:
                Text(display(value, field: field)).font(.system(size: 12.5)).lineLimit(3).multilineTextAlignment(.leading)
            }
        } else {
            Text("No value").font(.system(size: 12.5)).foregroundStyle(.tertiary)
        }
    }
    private func relationTitle(_ text: String) -> String {
        guard let reference = NoteReference(wikilink: "[[" + text + "]]") else { return "Unavailable note" }
        return reference.targets(in: store.notes).first?.title ?? (reference.explicitLabel ? reference.label : "Unavailable note")
    }
    private func editCell(_ note: NoteDocument, _ field: NativePropertyDefinition) {
        let actual = (try? store.schema?.effective(notePath: note.path))?.first { $0.id == field.id }
        if actual?.type == .relation { relation = .init(path: note.path, name: field.name) }
        else { edit = .init(name: field.name, value: MacCollectionValues.value(note, name: field.name), definition: actual, path: note.path, expected: note.content, workspaceID: store.workspaceID) }
    }
    private func display(_ value: NativePropertyValue, field: NativePropertyDefinition) -> String {
        if field.type == .date { return MacNumericDateFormat.validated(dateFormat).display(value.display) }
        guard field.type == .relation else { return value.display }
        return value.selections.map(relationTitle).joined(separator: ", ")
    }
    private var calendarOrder: [String] {
        guard let name = calendarProperty?.name else { return [] }
        return MacCollectionValues.calendar(notes: store.collection, name: name, month: month).order
    }
    private var calendar: some View {
        Group {
            if let field = calendarProperty {
                let name = field.name
                let snapshot = MacCollectionValues.calendar(notes: store.collection, name: name, month: month)
                let dated = snapshot.dated, order = snapshot.order
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }; Text(month, format: .dateTime.month(.wide).year()).font(.headline); Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }; Button("Today") { month = Date() } }.buttonStyle(MacBoxButtonStyle())
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) { ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { Text($0).font(.caption.bold()).frame(width: 130, height: 32) } }
                                ForEach(0..<6, id: \.self) { row in HStack(spacing: 0) { ForEach(0..<7, id: \.self) { column in dayCell(index: row * 7 + column, name: name, dated: dated, order: order) } }.fixedSize(horizontal: false, vertical: true) }
                            }.frame(width: 910)
                            LazyVStack(alignment: .leading, spacing: 10) { Text("Undated").font(.headline); ForEach(dated[""] ?? []) { card($0, order: order) } }.padding(12).frame(width: 220).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(16)
                }
            } else { ContentUnavailableView("Choose a date property", systemImage: "calendar", description: Text("Notes appear on their property’s date. Notes without a date stay in Undated.")) }
        }
    }
    private func dayCell(index: Int, name: String, dated: [String: [NoteDocument]], order: [String]) -> some View {
        let calendar = Calendar.current, start = calendar.dateInterval(of: .month, for: month)!.start
        let leading = (calendar.component(.weekday, from: start) + 5) % 7
        let date = calendar.date(byAdding: .day, value: index - leading, to: start)!
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let notes = dated[MacCollectionValues.wireDate(date)] ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if inMonth {
                Button { selectedDay = .init(date: date, name: name) } label: { HStack { Text(date, format: .dateTime.day()); Spacer(); if notes.count > 2 { Text("\(notes.count) notes").font(.caption2) } } }.buttonStyle(MacBoxButtonStyle()).font(.caption).foregroundStyle(calendar.isDateInToday(date) ? Color.accentColor : .secondary)
                ForEach(Array(notes.prefix(2))) { note in
                    Button { activate(note, order: order) } label: { VStack(alignment: .leading, spacing: 3) { Text(note.title).font(.caption2).lineLimit(2); propertySummary(note, lineLimit: 1) }.padding(5).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(store.selectedPaths.contains(note.path) ? 0.25 : 0.1), in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selectedPaths.contains(note.path) ? .isSelected : [])
                        .overlay(MacAlternateOpen { openInTab(note) }.accessibilityHidden(true))
                        .contextMenu { noteMenu(note); Button("Edit date…") { if let field = fields.first(where: { $0.name == name }) { editCell(note, field) } } }
                }
            }
            Spacer(minLength: 4)
        }.padding(7).frame(width: 130).frame(minHeight: 115, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: .textBackgroundColor)).contentShape(Rectangle()).border(.quaternary)

    }
    private func shiftMonth(_ offset: Int) { month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month }
}

/// Drop target and highlight for one board column. Keeping the targeted state
/// here avoids invalidating the whole collection body on every hover change.
private struct MacBoardColumnDrop: ViewModifier {
    let perform: (MacBoardTransfer) -> Bool
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
            .dropDestination(for: MacBoardTransfer.self) { items, _ in
                targeted = false
                guard items.count == 1, let transfer = items.first else { return false }
                return perform(transfer)
            } isTargeted: { active in if targeted != active { targeted = active } }
    }
}

/// Switches the collection between its layouts. Shared by the wide toolbar
/// and the narrow list header.
struct MacViewModeMenu: View {
    @Bindable var store: MacWorkspace
    static let modes = [("List", "list.bullet"), ("Gallery", "square.grid.2x2"), ("Kanban", "rectangle.split.3x1"), ("Table", "tablecells"), ("Calendar", "calendar")]
    var body: some View {
        Menu {
            ForEach(Self.modes, id: \.0) { mode, icon in
                Button { Task { await store.updateCollectionLayout(store.collectionLayout, mode: mode) } } label: { Label(mode, systemImage: icon) }
            }
            if store.folderCollection { Divider(); Toggle("Hide subtype notes", isOn: $store.hideSubtypes) }
        } label: {
            Label(store.viewMode, systemImage: Self.modes.first { $0.0 == store.viewMode }?.1 ?? "list.bullet").fontWeight(.semibold)
        }.menuStyle(.borderlessButton).fixedSize().help("Change layout")
    }
}
