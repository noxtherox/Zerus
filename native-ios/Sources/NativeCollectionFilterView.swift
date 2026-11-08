import SwiftUI

struct NativeCollectionFilterButton: View {
    @Binding var filters: NativeCollectionFilters
    let notes: [NoteDocument]
    var archiveOnly = false
    var fileTypes = false
    var otherFiles: [String] = []
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Label(filters.activeCount == 0 ? "Sort and filter" : "Sort and filter · \(filters.activeCount)", systemImage: filters.activeCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .font(.body).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("collection.filters")
            .sheet(isPresented: $presented) { NativeCollectionFilterView(filters: $filters, notes: notes, archiveOnly: archiveOnly, fileTypes: fileTypes, otherFiles: otherFiles) }
    }
}

struct NativeCollectionFilterView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: NativeCollectionFilters
    let notes: [NoteDocument]
    let archiveOnly: Bool
    let fileTypes: Bool
    var otherFiles: [String] = []
    @State private var schema: NativeSchemaSnapshot?
    private enum Route: Hashable { case chooseProperty, editProperty(String) }
    @State private var path: [Route] = []
    private var folders: [String] { Array(Set(notes.map(\.folder) + otherFiles.map { let parent = ($0 as NSString).deletingLastPathComponent; return parent.isEmpty ? "Inbox" : parent })).sorted() }
    private var options: [NativeCollectionPropertyOption] { NativeCollectionFilters.options(notes, schema: schema) }
    private var extensions: [String] { Array(Set(notes.compactMap { $0.fileHub.map { ($0.name as NSString).pathExtension.lowercased() } } + otherFiles.map { ($0 as NSString).pathExtension.lowercased() })).filter { !$0.isEmpty }.sorted() }
    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Picker("Sort", selection: $filters.sort) { ForEach(NativeNoteSort.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.navigationLink).accessibilityIdentifier("collection.sort")
                    Picker("Updated", selection: $filters.date) { ForEach(NativeNoteDate.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.navigationLink).accessibilityIdentifier("collection.date")
                    if !archiveOnly { Toggle("Include archived", isOn: $filters.includeArchived).accessibilityIdentifier("collection.archived") }
                } footer: { Text("Pinned notes stay first. Updated dates use your local calendar.") }
                if !folders.isEmpty {
                    Section {
                        NavigationLink {
                            List {
                                ForEach(folders, id: \.self) { folder in Toggle(folder, isOn: membership(folder, in: $filters.folders)).accessibilityIdentifier("collection.folder." + folder) }
                            }.navigationTitle("Folders")
                        } label: { LabeledContent("Folders", value: filters.folders.isEmpty ? "All" : "\(filters.folders.count) selected") }.accessibilityIdentifier("collection.folders")
                    } footer: { Text("Choose exact folders, or leave all off to show every folder in this collection.") }
                }
                if fileTypes && !extensions.isEmpty {
                    Section {
                        NavigationLink {
                            List { ForEach(extensions, id: \.self) { value in Toggle(value.uppercased(), isOn: membership(value, in: $filters.extensions)) } }.navigationTitle("File types")
                        } label: { LabeledContent("File types", value: filters.extensions.isEmpty ? "All" : "\(filters.extensions.count) selected") }
                    }
                }
                Section {
                    if filters.properties.count > 1 { Toggle("Match any property", isOn: $filters.matchAnyProperty).accessibilityIdentifier("collection.matchAny") }
                    ForEach(filters.properties) { selected in
                        HStack(alignment: .top) {
                            Button {
                                path.append(.editProperty(selected.name.lowercased()))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selected.name).font(.body)
                                    Text(summary(selected)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.foregroundStyle(.primary).accessibilityIdentifier("collection.property.edit." + selected.name.lowercased())
                            Button("Remove \(selected.name)", systemImage: "minus.circle") { filters.properties.removeAll { $0.id == selected.id } }.labelStyle(.iconOnly).tint(.red)
                        }.buttonStyle(.borderless)
                    }
                    Button { path.append(.chooseProperty) } label: { Label("Add property filter", systemImage: "plus") }.disabled(options.isEmpty).accessibilityIdentifier("collection.property.add")
                } header: { Text("Properties") } footer: { Text(filters.matchAnyProperty ? "A note must match at least one selected property. Values within a property match any selected value." : "A note must match every selected property. Values within a property match any selected value.") }
                if filters.activeCount > 0 { Section { Button("Clear all filters") { filters = .init() }.accessibilityIdentifier("collection.clear") } }
            }.navigationTitle("Sort and filter").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("collection.filters.done") } }
                .task(id: vault.schemaRevision) { schema = try? await vault.schemaSnapshot() }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .chooseProperty:
                        NativeCollectionPropertyChooser(options: options) { path.append(.editProperty($0.id)) }
                    case .editProperty(let key):
                        if let option = options.first(where: { $0.id == key }) {
                            NativeCollectionPropertyFilterView(option: option, existing: filters.properties.first { $0.name.lowercased() == key }) { value in
                                filters.properties.removeAll { $0.name.caseInsensitiveCompare(value.name) == .orderedSame }
                                filters.properties.append(value); path.removeAll()
                            }
                        } else { ContentUnavailableView("Property no longer available", systemImage: "tag") }
                    }
                }
        }
    }
    private func membership(_ value: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(value) }, set: { included in if included { values.wrappedValue.insert(value) } else { values.wrappedValue.remove(value) } })
    }
    private func summary(_ value: NativeCollectionPropertyFilter) -> String {
        if let comparison = value.dateComparison { return comparison.rawValue + " " + value.date + (comparison == .between ? " – " + value.endDate : "") }
        guard let values = value.values else { return "Is present" }
        return values.isEmpty ? "No values selected" : values.sorted { $0.id < $1.id }.map(\.label).joined(separator: ", ")
    }
}

private struct NativeCollectionPropertyChooser: View {
    @Environment(\.dismiss) private var dismiss
    let options: [NativeCollectionPropertyOption]
    let choose: (NativeCollectionPropertyOption) -> Void
    @State private var query = ""
    var body: some View {
        List {
                ForEach(options.filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { option in Button(option.name) { choose(option) } }
            }.searchable(text: $query, prompt: "Find a property").navigationTitle("Choose property").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

private struct NativeCollectionPropertyFilterView: View {
    @Environment(\.dismiss) private var dismiss
    let option: NativeCollectionPropertyOption
    let save: (NativeCollectionPropertyFilter) -> Void
    @State private var filter: NativeCollectionPropertyFilter
    @State private var mode: String
    @State private var date: Date
    @State private var endDate: Date
    init(option: NativeCollectionPropertyOption, existing: NativeCollectionPropertyFilter?, save: @escaping (NativeCollectionPropertyFilter) -> Void) {
        self.option = option; self.save = save
        _filter = State(initialValue: existing ?? .init(name: option.name))
        _mode = State(initialValue: existing?.dateComparison != nil ? "date" : existing?.values != nil ? "values" : "present")
        _date = State(initialValue: existing.flatMap { Self.formatter.date(from: $0.date) } ?? Date())
        _endDate = State(initialValue: existing.flatMap { Self.formatter.date(from: $0.endDate) } ?? Date())
    }
    private static var formatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; return f
    }
    var body: some View {
        Form {
                Picker("Match", selection: $mode) {
                    Text("Is present").tag("present"); Text("Selected values").tag("values")
                    if option.isDate { Text("Date comparison").tag("date") }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("collection.property.mode")
                if mode == "values" {
                    Section {
                        ForEach(option.values.union(filter.values ?? []).sorted { $0.id < $1.id }) { value in
                            Toggle(isOn: Binding(get: { filter.values?.contains(value) == true }, set: { included in
                                var values = filter.values ?? []; if included { values.insert(value) } else { values.remove(value) }; filter.values = values
                            })) {
                                VStack(alignment: .leading) {
                                    Text(value.label)
                                    if option.values.contains(where: { $0.value == value.value && $0.kind != value.kind }) { Text(value.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                                }
                            }.accessibilityIdentifier("collection.value." + value.id)
                        }
                    } footer: { Text("Select one or more values. Text, numbers and checkboxes are matched by their stored type.") }
                } else if mode == "date" {
                    Picker("Comparison", selection: Binding(get: { filter.dateComparison ?? .on }, set: { filter.dateComparison = $0 })) { ForEach(NativePropertyDateComparison.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.navigationLink)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if filter.dateComparison == .between { DatePicker("End date", selection: $endDate, displayedComponents: .date) }
                }
            }.navigationTitle(option.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            var value = filter
                            value.values = mode == "values" ? (filter.values ?? []) : nil
                            value.dateComparison = mode == "date" ? (filter.dateComparison ?? .on) : nil
                            value.date = Self.formatter.string(from: date); value.endDate = Self.formatter.string(from: endDate)
                            save(value)
                        }.disabled(mode == "values" && (filter.values?.isEmpty ?? true)).accessibilityIdentifier("collection.property.apply")
                    }
                }
    }
}
