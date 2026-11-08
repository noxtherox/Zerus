import SwiftUI

struct TasksView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var vault: VaultStore
    @AppStorage(NativeDateFormat.key) private var dateFormat = NativeDateFormat.dayFirst.rawValue
    let open: (NoteDocument) -> Void
    let library: () -> Void
    let settings: () -> Void
    @State private var query = NativeTaskQuery()
    @State private var editing: NativeTask?
    @State private var deleting: NativeTask?
    @State private var collections = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in taskList(now: context.date) }
                .navigationTitle("Tasks").searchable(text: $query.search, prompt: "Search tasks")
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .nativeSearchContrast("Search tasks")
                .refreshable { await vault.refresh() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { NativeLibraryButton(action: library) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Section("Tasks") {
                                Button("New task", systemImage: "plus") {
                                    var task = vault.newTask(); if let list = query.list { task.listID = list }; editing = task
                                }
                                Button("Manage task lists and categories", systemImage: "list.bullet.rectangle") { collections = true }.accessibilityIdentifier("tasks.manage")
                                Picker("Sort tasks", selection: $query.sort) { ForEach(NativeTaskSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                                Picker("Category", selection: $query.category) {
                                    Text("All categories").tag(String?.none)
                                    ForEach(Array(Set(vault.taskCategories + vault.tasks.map(\.category))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag(Optional($0)) }
                                }
                                Picker("Priority", selection: $query.priority) { Text("All priorities").tag(String?.none); ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag(Optional($0)) } }
                                Toggle("Show older completed tasks", isOn: $query.showOlderCompleted)
                            }
                            Section { Button("Settings", systemImage: "gearshape", action: settings) }
                        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings").accessibilityIdentifier("tasks.filter")
                    }
                }
                .navigationDestination(isPresented: $collections) { NativeTaskCollectionsView(workspaceID: vault.workspaceID) }
                .sheet(item: $editing) { task in TaskDetailView(task: task) }
                .confirmationDialog("Delete this task?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    if let deleting { Button("Delete task", role: .destructive) { Task { await vault.saveTask(deleting, delete: true); self.deleting = nil } }.accessibilityIdentifier("task.delete.confirm") }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { Text("The task is permanently deleted. Supporting notes remain in your vault.") }
        }
        .onChange(of: vault.workspaceID) { _, _ in editing = nil; deleting = nil; collections = false; query = .init() }
    }
    private var viewPicker: some View {
        Picker("Task view", selection: $query.view) {
            ForEach(NativeTaskView.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }
    private func taskList(now: Date) -> some View {
        let tasks = query.results(vault.tasks, now: now)
        let openTaskCount = vault.tasks.filter { !$0.completed }.count
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One thing at a time.").font(.system(.title2, design: .serif))
                    Text("\(openTaskCount) \(openTaskCount == 1 ? "task" : "tasks") ahead. Make a little progress.").font(.subheadline).foregroundStyle(Accent.secondaryText).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Accent.text).padding(.vertical, 10)
                Group {
                    if dynamicTypeSize.isAccessibilitySize { viewPicker.pickerStyle(.inline) }
                    else { viewPicker.pickerStyle(.segmented) }
                }.accessibilityIdentifier("tasks.view")
                Picker("List", selection: $query.list) {
                    Text("All lists").tag(String?.none); Text(vault.generalTaskListName).tag(Optional(""))
                    ForEach(vault.taskLists) { Text($0.name).tag(Optional($0.id)) }
                    if let id = query.list, !id.isEmpty, !vault.taskLists.contains(where: { $0.id == id }) { Text("Unavailable list").tag(Optional(id)) }
                }.accessibilityIdentifier("tasks.list")
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let store = vault.taskDraftStore { NativeTaskDraftsEntry(store: store, workspaceID: vault.workspaceID).id(vault.workspaceID) }
            if let issue = vault.taskDraftIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if let issue = vault.taskIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if tasks.isEmpty { ContentUnavailableView("A little breathing room", systemImage: "checkmark.circle", description: Text("No tasks match this view. Add a task or adjust the filters.")).foregroundStyle(Accent.text).listRowBackground(Color.clear) }
            if tasks.contains(where: { !$0.completed }) { Section { ForEach(tasks.filter { !$0.completed }) { taskRow($0, now: now).listRowBackground(Accent.card) } } header: { Text("To do").foregroundStyle(Accent.secondaryText) } }
            if tasks.contains(where: \.completed) { Section { ForEach(tasks.filter(\.completed)) { taskRow($0, now: now).listRowBackground(Accent.card) } } header: { Text("Completed").foregroundStyle(Accent.secondaryText) } }
            if !query.showOlderCompleted {
                Section {
                    Button("Show older completed tasks") { query.showOlderCompleted = true }.font(.subheadline).accessibilityIdentifier("tasks.older")
                } footer: {
                    Text("Completed tasks from the last seven days are shown by default.")
                        .font(.footnote).foregroundStyle(Accent.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.scrollContentBackground(.hidden).background(Accent.paper)
    }
    private func taskRow(_ task: NativeTask, now: Date) -> some View {
        let details = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return HStack(alignment: .top, spacing: 12) {
            Button { var next = task; next.completed.toggle(); Task { await vault.saveTask(next) } } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel(task.completed ? "Mark incomplete" : "Complete \(task.title)").accessibilityIdentifier("task.complete." + task.id)
            Button { editing = task } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title.isEmpty ? "Untitled task" : task.title).foregroundStyle(Accent.text).strikethrough(task.completed).frame(maxWidth: .infinity, alignment: .leading)
                    details {
                        if task.priority != "none" { Label(task.priority.capitalized, systemImage: "flag.fill").foregroundStyle(task.priority == "high" ? .red : .secondary) }
                        if !task.category.isEmpty { Text(task.category) }
                        if query.list == nil { Text(vault.taskLists.first { $0.id == task.listID }?.name ?? vault.generalTaskListName) }
                    }.font(.caption).foregroundStyle(Accent.secondaryText)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    details {
                        Label(dayLabel(task.date, now: now), systemImage: "calendar")
                        if !task.dueDate.isEmpty { Text("Due " + dayLabel(task.dueDate, now: now)).foregroundStyle(task.dueDate < NativeTask.day(now) && !task.completed ? .red : .secondary) }
                        if !task.linkedNoteIDs.isEmpty { Label(String(task.linkedNoteIDs.count), systemImage: "link") }
                    }.font(.caption).foregroundStyle(Accent.secondaryText)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                }.padding(.vertical, 7)
            }.buttonStyle(.plain).accessibilityLabel(task.title.isEmpty ? "Untitled task" : task.title)
            .accessibilityValue([task.completed ? "Completed" : "Incomplete", task.priority == "none" ? "" : task.priority.capitalized, task.category, "Scheduled " + dayLabel(task.date, now: now), task.dueDate.isEmpty ? "" : "Due " + dayLabel(task.dueDate, now: now)].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityIdentifier("task.open." + task.id)
        }.swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { deleting = task } }
    }
    private func dayLabel(_ key: String, now: Date) -> String {
        guard let date = NativeTask.parseDay(key) else { return key }
        if Calendar.current.isDate(date, inSameDayAs: now) { return "Today" }
        return (NativeDateFormat(rawValue: dateFormat) ?? .dayFirst).string(day: key)
    }
}

struct TaskDetailView: View {
    @EnvironmentObject private var vault: VaultStore
    let task: NativeTask
    var recovered: NativeTaskDraft? = nil
    @State private var session: NativeTaskDraftSession?
    var body: some View {
        Group {
            if task.workspaceID != vault.workspaceID { ContentUnavailableView("Vault changed", systemImage: "folder", description: Text("Reopen this task in its original vault.")) }
            else if let session { NativeTaskDetailForm(session: session) }
            else { ProgressView("Opening task…") }
        }.onAppear {
            guard session == nil, task.workspaceID == vault.workspaceID else { return }
            let value = NativeTaskDraftSession(task: task, store: vault.taskDraftStore, canonical: vault.tasks.first { $0.id == task.id }, recovered: recovered, accessIssue: vault.taskDraftIssue)
            if let saved = value.completedCopy(in: vault.tasks) { value.committed(saved) }
            session = value
        }
    }
}

private struct NativeTaskDetailForm: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @ObservedObject var session: NativeTaskDraftSession
    private var task: NativeTask { get { session.task } nonmutating set { session.task = newValue } }
    private enum DraftReview {
        case discard, reload, copy
        var title: String {
            switch self { case .discard: return "Discard this task draft?"; case .reload: return "Discard draft and reload?"; case .copy: return "Save this draft as a new task?" }
        }
        var message: String {
            switch self { case .discard: return "The task in your vault stays unchanged. This local draft will be removed."; case .reload: return "This local draft will be removed and the latest saved task will open."; case .copy: return "The original task stays unchanged. A separate task will contain this draft’s values." }
        }
    }
    @State private var review: DraftReview?
    @State private var links = false
    @State private var saving = false
    @State private var issue: String?
    @State private var opened: NativeOpenedNote?
    @FocusState private var titleFocused: Bool
    private func matches(_ token: String) -> [NoteDocument] { vault.notes.filter { !$0.trashed && ($0.stableID == token || $0.path == token) } }
    private var supportingIDs: [String] {
        guard task.baseline != nil, NativeTaskData.equal(task.raw["linkedNoteIds"], task.baseline?["linkedNoteIds"]),
              let latest = vault.tasks.first(where: { $0.id == task.id && $0.workspaceID == task.workspaceID }) else { return task.linkedNoteIDs }
        return latest.linkedNoteIDs
    }
    private var linkedNotes: [NoteDocument] { vault.notes.filter { note in supportingIDs.contains { matches($0).count == 1 && matches($0)[0].path == note.path } } }
    private var unresolved: [String] { supportingIDs.filter { matches($0).count != 1 } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top) {
                        TextField("What needs doing?", text: $session.task.title, axis: .vertical).font(.title3).focused($titleFocused).accessibilityIdentifier("task.title")
                        if titleFocused { Button("Done") { titleFocused = false }.buttonStyle(.borderless).accessibilityLabel("Dismiss task keyboard").accessibilityIdentifier("task.keyboard.dismiss") }
                    }
                    Toggle("Completed", isOn: $session.task.completed).accessibilityIdentifier("task.completed")
                }
                if session.dirty || session.recovered || session.issue != nil {
                    Section {
                        Label(session.record == nil ? "Save or share before closing" : session.recovered ? "Recovered task draft" : "Draft kept on this iPhone", systemImage: "doc.badge.clock").accessibilityIdentifier("task.draft.status")
                        if let warning = session.issue { Text(warning).font(.caption).foregroundStyle(.orange) }
                        ShareLink(item: task.shareDraft) { Label("Share draft", systemImage: "square.and.arrow.up") }
                        Button("Discard draft", role: .destructive) { review = .discard }.accessibilityIdentifier("task.draft.discard")
                    } footer: { Text(session.record == nil && session.dirty ? "This draft has not been kept on this iPhone. Save or share before closing." : "Closing keeps this draft privately. Save updates the task in your vault.") }
                }
                if let issue {
                    Section {
                        Text(issue).foregroundStyle(.red).accessibilityIdentifier("task.error")
                        Button("Discard draft and reload") { review = .reload }.accessibilityIdentifier("task.draft.reload")
                        Button("Save as a new task") { review = .copy }.accessibilityIdentifier("task.draft.copy")
                    }
                }
                Section("Plan") {
                    Picker("List", selection: $session.task.listID) {
                        Text(vault.generalTaskListName).tag(""); ForEach(vault.taskLists) { Text($0.name).tag($0.id) }
                        if !task.listID.isEmpty && !vault.taskLists.contains(where: { $0.id == task.listID }) { Text("Unavailable list").tag(task.listID) }
                    }.accessibilityIdentifier("task.list")
                    Picker("Priority", selection: $session.task.priority) {
                        ForEach(["none", "low", "medium", "high"] + (["none", "low", "medium", "high"].contains(task.priority) ? [] : [task.priority]), id: \.self) { Text($0.capitalized).tag($0) }
                    }.accessibilityIdentifier("task.priority")
                    Picker("Category", selection: $session.task.category) {
                        Text("None").tag(""); ForEach(Array(Set(vault.taskCategories + [task.category])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier("task.category")
                    DatePicker("Scheduled", selection: Binding(get: { NativeTask.parseDay(task.date) ?? Date() }, set: { task.date = NativeTask.day($0) }), displayedComponents: .date).accessibilityIdentifier("task.date")
                    Menu {
                        Button("Today") { task.date = NativeTask.day(Date()) }
                        Button("Tomorrow") { task.date = NativeTask.day(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) }
                        Button("Next week") { task.date = NativeTask.day(Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()) }
                    } label: {
                        HStack { Text("Quick schedule"); Spacer(); Image(systemName: "calendar.badge.clock") }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityIdentifier("task.schedule")
                    if NativeTask.parseDay(task.date) == nil { Text("Stored schedule: " + task.date).font(.caption).foregroundStyle(.orange) }
                    Toggle("Due date", isOn: Binding(get: { !task.dueDate.isEmpty }, set: { task.dueDate = $0 ? NativeTask.day(Date()) : "" })).accessibilityIdentifier("task.hasDueDate")
                    if !task.dueDate.isEmpty {
                        DatePicker("Due", selection: Binding(get: { NativeTask.parseDay(task.dueDate) ?? Date() }, set: { task.dueDate = NativeTask.day($0) }), displayedComponents: .date).accessibilityIdentifier("task.dueDate")
                        if NativeTask.parseDay(task.dueDate) == nil { Text("Stored due date: " + task.dueDate).font(.caption).foregroundStyle(.orange) }
                    }
                }
                Section("Supporting notes") {
                    ForEach(linkedNotes) { note in
                        HStack {
                            Button { Task { if await save() { openNote(note) } } } label: { Label(note.title, systemImage: "doc.text") }.accessibilityIdentifier("task.note." + (note.stableID ?? note.path))
                            Spacer()
                            Button { task.linkedNoteIDs.removeAll { $0 == note.stableID || $0 == note.path } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("Unlink " + note.title)
                        }
                    }
                    ForEach(Array(Set(unresolved)), id: \.self) { token in
                        HStack { Label("Unavailable linked note", systemImage: "link.badge.plus").foregroundStyle(.secondary); Spacer(); Button("Unlink") { task.linkedNoteIDs.removeAll { $0 == token } } }.accessibilityIdentifier("task.unresolved." + token)
                    }
                    Button("Choose notes", systemImage: "link") { links = true }.accessibilityIdentifier("task.chooseNotes")
                }
                if let completed = task.completedAt { Section { LabeledContent("Completed") { NativeDateText(completed, time: true) } } }

            }
            .navigationTitle("Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { titleFocused = false; Task { await Task.yield(); session.keep(); dismiss() } }.disabled(saving).accessibilityIdentifier("task.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { if await save() { dismiss() } } }.disabled(saving || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("task.save") }
            }
            .onChange(of: phase) { _, value in if value != .active { session.keep() } }
            .onDisappear { session.keep() }
            .alert(review?.title ?? "Task draft", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), presenting: review) { choice in
                switch choice {
                case .discard:
                    Button("Discard draft", role: .destructive) { do { try session.discard(); dismiss() } catch { issue = error.localizedDescription } }
                case .reload:
                    Button("Discard draft and reload", role: .destructive) { Task { saving = true; defer { saving = false }; do { let latest = try await vault.reloadTask(id: task.id, workspace: task.workspaceID); try session.discard(); session.committed(latest); issue = nil } catch { issue = error.localizedDescription } } }
                case .copy:
                    Button("Save new task") { Task { await saveCopy() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { choice in Text(choice.message) }
            .scrollDismissesKeyboard(.interactively)
            .disabled(saving).interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Updating task…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .sheet(isPresented: $links) {
                let selected = Set(linkedNotes.map(\.path))
                NotePicker(title: "Supporting notes", multiple: true, selected: selected) { ids in
                    guard task.workspaceID == vault.workspaceID else { return }
                    let missing = unresolved
                    task.linkedNoteIDs = Array(Set(missing + vault.notes.filter { ids.contains($0.path) }.map { $0.stableID ?? $0.path })).sorted()
                }
            }
            .fullScreenCover(item: $opened) { request in
                NativeNoteNavigationView(navigation: request.navigation)
            }
        }
    }
    private func openNote(_ note: NoteDocument) {
        guard note.workspaceID == vault.workspaceID, task.workspaceID == vault.workspaceID else { return }
        guard let session = vault.session(for: note) else {
            issue = "This note is no longer available, or more than one file has its note ID. Refresh Library and check the original files."
            return
        }
        opened = NativeOpenedNote(navigation: NativeNoteNavigation(vault: vault, session: session))
    }
    private func saveCopy() async {
        titleFocused = false; await Task.yield()
        saving = true; defer { saving = false }
        do {
            if let saved = session.completedCopy(in: vault.tasks) { session.committed(saved); dismiss(); return }
            let copy = try session.copyIntent()
            if await vault.saveTask(copy), let saved = vault.tasks.first(where: { $0.id == copy.id }) { session.committed(saved); dismiss() }
            else { issue = vault.error ?? "The new task could not be saved. Your draft is kept here." }
        } catch { issue = error.localizedDescription }
    }
    private func save() async -> Bool {
        titleFocused = false; await Task.yield(); session.keep()
        saving = true; defer { saving = false }
        let result = await vault.saveTask(task)
        if result, let saved = vault.tasks.first(where: { $0.id == task.id }) { session.committed(saved); issue = nil }
        else { issue = vault.error ?? "The task could not be saved. Your draft is still here." }
        return result
    }
}

private struct TaskCollectionName: Identifiable {
    enum Kind { case createList, renameList(NativeTaskList?), category }
    let id = UUID()
    let kind: Kind
    let title: String
    let original: String
}
private struct TaskCollectionDeletion: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
    let change: NativeTaskChange
}
struct NativeTaskCollectionsView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    @State private var naming: TaskCollectionName?
    @State private var deleting: TaskCollectionDeletion?
    @State private var busy = false
    private var categories: [String] { Array(Set(vault.taskCategories + vault.tasks.map(\.category))).filter { !$0.isEmpty }.sorted() }
    var body: some View {
        List {
            Section {
                HStack {
                    Label(vault.generalTaskListName, systemImage: "tray")
                    Spacer()
                    Button("Rename") { naming = .init(kind: .renameList(nil), title: "Rename default list", original: vault.generalTaskListName) }.accessibilityIdentifier("tasks.general.rename")
                }
                ForEach(vault.taskLists) { list in
                    HStack {
                        VStack(alignment: .leading) { Text(list.name); Text("\(vault.tasks.filter { $0.listID == list.id }.count) tasks").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Menu {
                            Button("Rename") { naming = .init(kind: .renameList(list), title: "Rename list", original: list.name) }
                            Button("Delete list", role: .destructive) {
                                let ids = Set(vault.tasks.filter { $0.listID == list.id }.map(\.id))
                                deleting = .init(title: "Delete “\(list.name)” ?", explanation: "\(ids.count) tasks move to \(vault.generalTaskListName). The tasks and their notes are kept.", change: .deleteList(list, assigned: ids))
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Actions for " + list.name)
                    }
                }
                Button("New list", systemImage: "plus") { naming = .init(kind: .createList, title: "New task list", original: "") }.accessibilityIdentifier("tasks.list.add")
            } header: { Text("Lists") } footer: { Text("Each task belongs to a list. The default list can be renamed and is always available.") }
            Section("Categories") {
                ForEach(categories, id: \.self) { category in
                    HStack {
                        Text(category); Spacer()
                        Button(role: .destructive) {
                            let ids = Set(vault.tasks.filter { $0.category.lowercased() == category.lowercased() }.map(\.id))
                            deleting = .init(title: "Remove “\(category)” ?", explanation: "Clear this category from \(ids.count) tasks. The tasks and their notes are kept.", change: .deleteCategory(category, assigned: ids))
                        } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove category " + category)
                    }
                }
                Button("New category", systemImage: "plus") { naming = .init(kind: .category, title: "New task category", original: "") }.accessibilityIdentifier("tasks.category.add")
            }
        }.navigationTitle("Lists and categories").navigationBarTitleDisplayMode(.inline).disabled(busy)
            .sheet(item: $naming) { request in
                NativeTaskCollectionNameForm(title: request.title, original: request.original) { value in
                    let change: NativeTaskChange
                    switch request.kind {
                    case .createList: change = .createList(id: UUID().uuidString.lowercased(), name: value)
                    case .renameList(let list): change = .renameList(list, originalName: request.original, name: value)
                    case .category: change = .addCategory(value)
                    }
                    return await vault.changeTasks(change, workspace: workspaceID)
                }
            }
            .confirmationDialog(deleting?.title ?? "Remove collection?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting { Button("Remove", role: .destructive) { busy = true; Task { _ = await vault.changeTasks(deleting.change, workspace: workspaceID); busy = false; self.deleting = nil } }.accessibilityIdentifier("tasks.collection.delete") }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text(deleting?.explanation ?? "") }
    }
}
private struct NativeTaskCollectionNameForm: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (String) async -> Bool
    @State private var name: String
    @State private var busy = false
    @State private var issue: String?
    init(title: String, original: String, save: @escaping (String) async -> Bool) { self.title = title; self.save = save; _name = State(initialValue: original) }
    var body: some View {
        NavigationStack {
            Form { TextField("Name", text: $name).accessibilityIdentifier("tasks.collection.name"); if let issue { Text(issue).foregroundStyle(.red) } }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { busy = true; Task { if await save(name) { dismiss() } else { issue = vault.error ?? "Could not save the collection." }; busy = false } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("tasks.collection.save") }
                }.disabled(busy).interactiveDismissDisabled(busy)
        }
    }
}
