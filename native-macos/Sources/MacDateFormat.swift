import SwiftUI

/// Presentation only. Vault dates remain ISO calendar days or timestamp strings.
enum MacNumericDateFormat: String, CaseIterable {
    case dayFirst = "DD/MM/YYYY", monthFirst = "MM/DD/YYYY", iso = "YYYY-MM-DD", dotted = "DD.MM.YYYY"
    static func validated(_ value: String) -> Self { Self(rawValue: value) ?? .dayFirst }
    static func isDay(_ value: String) -> Bool {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return false }
        let leap = parts[0] % 400 == 0 || parts[0] % 4 == 0 && parts[0] % 100 != 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[parts[1] - 1]).contains(parts[2])
    }
    func calendarDay(_ value: String) -> String {
        guard Self.isDay(value) else { return value }
        let parts = value.split(separator: "-")
        return rawValue.replacingOccurrences(of: "YYYY", with: String(parts[0])).replacingOccurrences(of: "MM", with: String(parts[1])).replacingOccurrences(of: "DD", with: String(parts[2]))
    }
    static func localDay(_ value: String, timeZone: TimeZone = .current) -> String? {
        if isDay(value) { return value }
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"#, options: .regularExpression) != nil else { return nil }
        let expanded = value.replacingOccurrences(of: #"T([0-9]{2}:[0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})$"#, with: "T$1:00$2", options: .regularExpression)
        if let date = NativeRevisionIndex.date(expanded) { return Self.iso.display(date, timeZone: timeZone) }
        // Offset-free ISO timestamps spell local wall time directly.
        if value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9](?:\.[0-9]{1,9})?)?$"#, options: .regularExpression) != nil,
           isDay(String(value.prefix(10))) { return String(value.prefix(10)) }
        return nil
    }
    func display(_ value: String, timeZone: TimeZone = .current) -> String {
        Self.localDay(value, timeZone: timeZone).map(calendarDay) ?? value
    }
    func display(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return calendarDay(String(format: "%04d-%02d-%02d", year, month, day))
    }
    func parse(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        let separator = rawValue.contains("/") ? "/" : rawValue.contains(".") ? "." : "-"
        let tokens = rawValue.components(separatedBy: separator), parts = text.components(separatedBy: separator)
        guard parts.count == 3 else { return nil }
        var values: [String: Int] = [:]
        for (index, token) in tokens.enumerated() {
            guard parts[index].range(of: token == "YYYY" ? #"^[0-9]{4}$"# : #"^[0-9]{1,2}$"#, options: .regularExpression) != nil,
                  let number = Int(parts[index]) else { return nil }
            values[token] = number
        }
        let value = String(format: "%04d-%02d-%02d", values["YYYY"]!, values["MM"]!, values["DD"]!)
        return Self.isDay(value) ? value : nil
    }
}

/// Retains incomplete text and its interpretation while a format changes elsewhere.
struct MacDateDraft {
    var text: String
    var format: MacNumericDateFormat
    var baseline: String
    var original: String
    var editing = false
    var valid: Bool
    init(value: String, format: MacNumericDateFormat) {
        text = format.display(value); self.format = format; baseline = value; original = value
        valid = value.isEmpty || MacNumericDateFormat.localDay(value) != nil
    }
    mutating func refresh(value: String, format: MacNumericDateFormat) {
        if value != baseline || !editing { self = .init(value: value, format: format) }
    }
    mutating func edit(_ text: String, publishing: Bool) -> String? {
        self.text = text; editing = true
        let value = format.parse(text); valid = value != nil
        if publishing, let value { baseline = value }
        return value
    }
    mutating func finish(value: String, format: MacNumericDateFormat) {
        if valid { self = .init(value: value, format: format) }
    }
}

struct MacDateField: View {
    let title: String
    @Binding var value: String
    @Binding var valid: Bool
    let allowEmpty: Bool
    let publishOnEdit: Bool
    @AppStorage("zerus.mac.dateFormat") private var preference = "DD/MM/YYYY"
    @State private var draft: MacDateDraft
    @State private var calendarOpen = false
    @FocusState private var focused: Bool
    init(_ title: String, value: Binding<String>, valid: Binding<Bool> = .constant(true), allowEmpty: Bool = true, publishOnEdit: Bool = true) {
        self.title = title; _value = value; _valid = valid; self.allowEmpty = allowEmpty; self.publishOnEdit = publishOnEdit
        _draft = State(initialValue: .init(value: value.wrappedValue, format: .dayFirst))
    }
    private var format: MacNumericDateFormat { .validated(preference) }
    private var acceptable: Bool { draft.valid && (allowEmpty || !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).macFont(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(title, text: Binding(get: { draft.text }, set: { text in
                    guard text != draft.text else { return }
                    let publishes = publishOnEdit && (allowEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let parsed = draft.edit(text, publishing: publishes), publishes, parsed != value { value = parsed }
                    valid = acceptable
                }), prompt: Text(draft.format.rawValue)).labelsHidden().focused($focused)
                    .accessibilityLabel(title).accessibilityHint("Enter a date as " + draft.format.rawValue)
                    .onSubmit { finish(); focused = false }
                    .onExitCommand { if value != draft.original { value = draft.original }; draft = .init(value: value, format: format); valid = acceptable; calendarOpen = false; focused = false }
                Button { calendarOpen.toggle() } label: { Image(systemName: "calendar") }.buttonStyle(.borderless).accessibilityLabel(title + " calendar")
                    .macPopover(isPresented: $calendarOpen) {
                        DatePicker(title, selection: Binding(get: { MacNumericDateFormat.localDay(value).flatMap { NativeTask.parseDay($0) } ?? Date() }, set: {
                            let day = NativeTask.day($0); if day != value { value = day }; draft = .init(value: value, format: format); valid = true; calendarOpen = false
                        }), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().padding(12).frame(width: 280)
                    }
            }
            if !acceptable { Text("Enter a valid date as " + draft.format.rawValue + (allowEmpty ? ", or clear the field." : ".")).macFont(.caption).foregroundStyle(.red) }
            else if draft.editing && draft.format != format { Text("Finish this date as " + draft.format.rawValue + ".").macFont(.caption).foregroundStyle(.secondary) }
            if draft.editing && !publishOnEdit && acceptable { Text("Press Return or leave the field to apply.").macFont(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { refresh() }
        .onChange(of: value) { refresh() }
        .onChange(of: preference) { refresh() }
        .onChange(of: focused) { if !focused { finish() } }
    }
    private func refresh() { draft.refresh(value: value, format: format); valid = acceptable }
    private func finish() {
        if acceptable {
            if draft.editing, let parsed = draft.format.parse(draft.text), parsed != value { value = parsed }
            draft.finish(value: value, format: format)
        }
        valid = acceptable
    }
}

struct MacDateLabel: View {
    let value: String
    var prefix = ""
    @AppStorage("zerus.mac.dateFormat") private var preference = "DD/MM/YYYY"
    var body: some View { Text(prefix + MacNumericDateFormat.validated(preference).display(value)) }
}
