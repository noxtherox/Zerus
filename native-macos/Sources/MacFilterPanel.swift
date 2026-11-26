import SwiftUI

struct MacFilterPanel: View {
    @Binding var filters: NativeCollectionFilters
    let notes: [NoteDocument]
    let schema: NativeSchemaSnapshot?
    var showsFolders = true
    var options: [NativeCollectionPropertyOption] { NativeCollectionFilters.options(notes, schema: schema).filter { !$0.name.lowercased().hasPrefix("zerus-") } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Sort & filter").macFont(.headline); Spacer(); Button("Reset") { filters = .init() } }
                Picker("Sort", selection: $filters.sort) { ForEach(NativeNoteSort.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Modified", selection: $filters.date) { ForEach(NativeNoteDate.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Include archived", isOn: $filters.includeArchived)
                Divider()
                HStack { Text("Properties").fontWeight(.semibold); Spacer(); Menu("Add filter") {
                    ForEach(options.filter { option in !filters.properties.contains { $0.name.caseInsensitiveCompare(option.name) == .orderedSame } }) { option in Button(option.name) { filters.properties.append(.init(name: option.name)) } }
                } }
                if !filters.properties.isEmpty { Toggle("Match any property filter", isOn: $filters.matchAnyProperty).macFont(.caption) }
                ForEach($filters.properties) { $filter in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(filter.name).fontWeight(.medium); Spacer(); Button { filters.properties.removeAll { $0.id == filter.id } } label: { Image(systemName: "xmark.circle") }.buttonStyle(MacBoxButtonStyle()).help("Remove filter") }
                        MacPropertyFilterControls(filter: $filter, option: options.first { $0.name.caseInsensitiveCompare(filter.name) == .orderedSame })
                    }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                if showsFolders { DisclosureGroup("Folders") {
                    VStack(alignment: .leading, spacing: 6) { ForEach(Array(Set(notes.filter { !$0.trashed }.map(\.folder))).sorted(), id: \.self) { folder in Toggle(folder, isOn: Binding(get: { filters.folders.contains(folder) }, set: { enabled in if enabled { filters.folders.insert(folder) } else { filters.folders.remove(folder) } })) } }.macFont(.caption).padding(.top, 6)
                } }
                Text("Filters affect this collection. Match any combines property filters with OR; the other controls still apply.").macFont(.caption2).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(width: 380, height: 540)
    }
}

private struct MacPropertyFilterControls: View {
    @Binding var filter: NativeCollectionPropertyFilter
    let option: NativeCollectionPropertyOption?
    var mode: Binding<String> { .init(get: { filter.dateComparison != nil ? "date" : filter.values == nil ? "present" : "values" }, set: { value in
        filter.dateComparison = value == "date" ? .on : nil
        filter.values = value == "values" ? [] : nil
        if value == "date" && filter.date.isEmpty { filter.date = NativeTask.day(Date()) }
    }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Compare", selection: mode) {
                Text("Has property").tag("present")
                Text("Accepted values").tag("values")
                if option?.isDate == true || filter.dateComparison != nil { Text("Date comparison").tag("date") }
            }
            if filter.dateComparison != nil {
                Picker("Date", selection: Binding(get: { filter.dateComparison ?? .on }, set: { filter.dateComparison = $0 })) { ForEach(NativePropertyDateComparison.allCases) { Text($0.rawValue).tag($0) } }
                MacDateField("Date", value: $filter.date, allowEmpty: false, publishOnEdit: false)
                if filter.dateComparison == .between { MacDateField("End date", value: $filter.endDate, allowEmpty: false, publishOnEdit: false) }
            } else if filter.values != nil {
                ForEach(Array((option?.values ?? []).union(filter.values ?? [])).sorted { $0.id < $1.id }) { value in
                    Toggle(isOn: Binding(get: { filter.values?.contains(value) == true }, set: { enabled in if enabled { filter.values?.insert(value) } else { filter.values?.remove(value) } })) {
                        if option?.isDate == true { MacDateLabel(value: value.value) } else { Text(label(value)) }
                    }
                }
                if filter.values?.isEmpty == true { Text("Choose one or more accepted values.").macFont(.caption2).foregroundStyle(.secondary) }
            }
        }.macFont(.caption)
    }
    private func label(_ value: NativeCollectionValue) -> String { NoteReference(wikilink: "[[" + value.value + "]]")?.label ?? value.label }
}
