import SwiftUI

struct MacTasksView: View {
    @Bindable var store: MacWorkspace
    @State private var query = NativeTaskQuery()
    @State private var draft: NativeTask?
    @State private var managing: MacTaskCollectionContext?
    @State private var completedOpen = false
    private var taskViewPicker: some View {
        Picker("View", selection: $query.view) { ForEach(NativeTaskView.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
    }
    private var taskSearch: some View { TextField("Search tasks…", text: $query.search).textFieldStyle(.roundedBorder) }
    private var taskSortPicker: some View { Picker("Sort", selection: $query.sort) { ForEach(NativeTaskSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
    private var taskCategoryPicker: some View {
        Picker("Category", selection: Binding(get: { query.category ?? "" }, set: { query.category = $0.isEmpty ? nil : $0 })) { Text("All categories").tag(""); ForEach(store.taskCategories, id: \.self) { Text($0).tag($0) } }
    }
    private var taskPriorityPicker: some View {
        Picker("Priority", selection: Binding(get: { query.priority ?? "" }, set: { query.priority = $0.isEmpty ? nil : $0 })) { Text("All priorities").tag(""); ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) } }
    }
    private var olderCompletedToggle: some View { Toggle("Show older completed", isOn: $query.showOlderCompleted).macFont(.caption) }
    var body: some View {
        // Sorting parses task timestamps. Share one result across rows, empty
        // state and totals instead of sorting again for each computed property.
        let visible = query.results(store.tasks)
        let pending = visible.filter { !$0.completed }, completed = visible.filter(\.completed)
        let pendingCounts = store.tasks.reduce(into: [String: Int]()) { counts, task in
            if !task.completed { counts[task.listID, default: 0] += 1 }
        }
        let allPending = pendingCounts.values.reduce(0, +)
        VStack(spacing: 0) {
            HStack { Text("Tasks").macFont(.title2.bold()); Spacer(); if store.tasksSaving { ProgressView().controlSize(.small) }; if let drafts = store.taskDraftStore { MacTaskDraftsEntry(workspace: store, drafts: drafts) }; Button("Lists & categories…") { managing = .init(id: store.workspaceID) }; Button { draft = store.newTask(listID: query.list ?? "") } label: { Label("New task", systemImage: "plus") } }.padding(20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    listCard(name: "All lists", id: nil, pending: allPending)
                    listCard(name: store.generalTaskListName, id: "", pending: pendingCounts[""] ?? 0)
                    ForEach(store.taskLists) { list in listCard(name: list.name, id: list.id, pending: pendingCounts[list.id] ?? 0) }
                }.padding(.horizontal, 20)
            }.padding(.bottom, 16)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 15) { taskViewPicker.frame(width: 270); taskSearch.frame(minWidth: 160); taskSortPicker.frame(width: 230) }
                VStack(alignment: .leading, spacing: 10) { taskViewPicker; taskSearch; taskSortPicker }
            }.padding(.horizontal, 20)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { taskCategoryPicker.frame(width: 250); taskPriorityPicker.frame(width: 220); Spacer(); olderCompletedToggle }
                VStack(alignment: .leading, spacing: 10) { taskCategoryPicker; taskPriorityPicker; olderCompletedToggle }
            }.padding(20)
            if let issue = store.taskDraftIssue { Text(MacTaskDraftExport.message(issue)).macFont(.caption).foregroundStyle(.orange).padding(.horizontal, 20) }
            if let warning = store.taskWarning { Text(warning).macFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 20) }
            Divider()
            ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pending) { task in taskRow(task); Divider() }
                if !completed.isEmpty {
                    DisclosureGroup(isExpanded: Binding(get: { query.view == .completed || completedOpen }, set: { completedOpen = $0 })) { ForEach(completed) { taskRow($0) } } label: { Text("Completed · \(completed.count)").macFont(.headline) }
                }
                if visible.isEmpty { ContentUnavailableView("No tasks", systemImage: "checkmark.circle", description: Text("Try another list or filter, or add a task.")) }
            }.padding(.horizontal, 20) }.frame(maxHeight: .infinity)
            HStack { Text("\(pending.count) pending · \(completed.count) completed"); Spacer() }.macFont(.caption).foregroundStyle(.secondary).padding(12)
        }
        .onAppear { query.list = "" }
        .onChange(of: store.taskLists.map(\.id)) { _, ids in if let id = query.list, !id.isEmpty, !ids.contains(id) { query.list = "" } }
        .onChange(of: store.taskCategories) { _, values in if let category = query.category, !values.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) { query.category = nil } }
        .macSheet(item: $draft) { task in MacTaskEditor(store: store, task: task) }
        .macSheet(item: $managing) { context in MacTaskCollectionsView(store: store, workspaceID: context.id) }
    }
    private func listCard(name: String, id: String?, pending: Int) -> some View {
        Button { query.list = id } label: {
            VStack(alignment: .leading, spacing: 6) { Text(name).macFont(.headline).lineLimit(1); Text("\(pending) pending").macFont(.caption).foregroundStyle(.secondary) }.padding(13).frame(width: 160, alignment: .leading).background(query.list == id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel(name + " task list")
    }
    private func taskRow(_ task: NativeTask) -> some View {
        HStack(spacing: 12) {
            Button { var edited = task; edited.completed.toggle(); Task { await store.saveTask(edited) } } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(task.completed ? Color.accentColor : .secondary) }.buttonStyle(MacBoxButtonStyle()).disabled(store.tasksSaving).accessibilityLabel(task.completed ? "Reopen " + task.title : "Complete " + task.title)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).strikethrough(task.completed)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { MacDateLabel(value: task.date, prefix: "Scheduled "); if !task.dueDate.isEmpty { MacDateLabel(value: task.dueDate, prefix: "Due ") } }
                    if task.completed, let completed = task.raw["completedAt"] as? String { MacDateLabel(value: completed, prefix: "Completed ") }
                    HStack { if !task.category.isEmpty { Text(task.category).lineLimit(1) }; if !task.linkedNoteIDs.isEmpty { Label("\(task.linkedNoteIDs.count)", systemImage: "link") } }
                }.macFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if task.priority != "none" { Text(task.priority.capitalized).macFont(.caption).foregroundStyle(task.priority == "high" ? .red : .secondary) }
            Button("Edit…") { draft = task }.buttonStyle(.borderless).accessibilityLabel("Edit " + task.title)
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
    }
}

enum MacTaskNotes {
    static func matches(_ token: String, notes: [NoteDocument]) -> [NoteDocument] { notes.filter { !$0.trashed && ($0.stableID == token || $0.path == token) } }
    static func token(_ note: NoteDocument, notes: [NoteDocument]) -> String { if let id = note.stableID, matches(id, notes: notes).count == 1 { return id }; return note.path }
    static func isLinked(_ note: NoteDocument, ids: [String], notes: [NoteDocument]) -> Bool { ids.contains { token in let matches = matches(token, notes: notes); return matches.count == 1 && matches[0].path == note.path } }
}

struct MacTaskEditor: View {
    @Bindable var store: MacWorkspace
    let task: NativeTask
    var recovered: NativeTaskDraft? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var session: NativeTaskDraftSession?
    @State private var issue: String?
    var body: some View {
        Group {
            if let session { MacTaskForm(store: store, session: session) }
            else if let issue { VStack { Text(issue); Button("Close") { dismiss() } }.padding(24) }
            else { ProgressView("Opening task…").padding(24) }
        }.onAppear {
            guard session == nil else { return }
            do { session = try store.taskDraftSession(task, recovered: recovered) } catch { issue = error.localizedDescription }
        }
    }
}

private struct MacTaskForm: View {
    @Bindable var store: MacWorkspace
    @ObservedObject var session: NativeTaskDraftSession
    private var task: NativeTask { get { session.task } nonmutating set { session.task = newValue } }
    @State private var review: MacTaskDraftReview?
    @State private var issue: String?
    @State private var saving = false
    @State private var scheduledValid = true
    @State private var dueValid = true
    @State private var dueVisibility: Bool?
    @State private var deleting = false
    @State private var linkPicker = false
    @State private var query = ""
    @State private var folder: String?
    @Environment(\.dismiss) private var dismiss
    private var connected: Bool { task.workspaceID == store.workspaceID }
    private var datesValid: Bool { scheduledValid && (!(dueVisibility ?? !task.dueDate.isEmpty) || dueValid) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(task.baseline == nil ? "New task" : "Edit task").macFont(.title2.bold()); Spacer(); if saving { ProgressView().controlSize(.small) } }
            Form {
                TextField("Title", text: $session.task.title)
                Toggle("Completed", isOn: $session.task.completed)
                Picker("Priority", selection: $session.task.priority) { ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) }; if !["none", "low", "medium", "high"].contains(task.priority) { Text("Unavailable priority").tag(task.priority) } }
                Picker("List", selection: $session.task.listID) { Text(store.generalTaskListName).tag(""); ForEach(store.taskLists) { Text($0.name).tag($0.id) }; if !task.listID.isEmpty && !store.taskLists.contains(where: { $0.id == task.listID }) { Text("Unavailable list").tag(task.listID) } }
                Picker("Category", selection: Binding(get: { store.taskCategories.first { $0.caseInsensitiveCompare(task.category) == .orderedSame } ?? task.category }, set: { task.category = $0 })) { Text("None").tag(""); ForEach(store.taskCategories, id: \.self) { Text($0).tag($0) }; if !task.category.isEmpty && !store.taskCategories.contains(where: { $0.caseInsensitiveCompare(task.category) == .orderedSame }) { Text(task.category + " (unavailable)").tag(task.category) } }
                MacDateField("Scheduled", value: $session.task.date, valid: $scheduledValid, allowEmpty: false)
                Toggle("Due date", isOn: Binding(get: { dueVisibility ?? !task.dueDate.isEmpty }, set: { enabled in
                    dueVisibility = enabled
                    if !enabled { task.dueDate = "" }
                    else if task.dueDate.isEmpty { task.dueDate = NativeTask.day(Date()) }
                }))
                if dueVisibility ?? !task.dueDate.isEmpty {
                    MacDateField("Due", value: Binding(get: { task.dueDate }, set: { value in dueVisibility = true; if value != task.dueDate { task.dueDate = value } }), valid: $dueValid)
                }
            }
            Divider()
            HStack { Text("Supporting notes").macFont(.headline); Spacer(); Button(linkPicker ? "Hide picker" : "Link a note…") { linkPicker.toggle() } }
            ScrollView { VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(task.linkedNoteIDs.enumerated()), id: \.offset) { _, token in
                    let matches = MacTaskNotes.matches(token, notes: store.notes)
                    HStack { if matches.count == 1, let note = matches.first { Button(note.title) { Task { if await commit() { await store.openNote(note.path) } } }.buttonStyle(.link) } else { Label("Unavailable linked note", systemImage: "link.badge.plus").foregroundStyle(.secondary) }; Spacer(); Button("Unlink") { task.linkedNoteIDs.removeAll { $0 == token } } }
                }
                if task.linkedNoteIDs.isEmpty { Text("No supporting notes").macFont(.caption).foregroundStyle(.secondary) }
            } }.frame(maxHeight: 100)
            if linkPicker {
                HStack { TextField("Search notes…", text: $query); Picker("Folder", selection: $folder) { Text("All folders").tag(String?.none); Text("No folder").tag(Optional("")); ForEach(store.folders, id: \.self) { Text($0).tag(Optional($0)) } }.frame(width: 210) }
                ScrollView { LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(store.notes.filter { !$0.trashed && (folder == nil || ($0.path as NSString).deletingLastPathComponent == folder) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)) }) { note in
                        Toggle(isOn: Binding(get: { MacTaskNotes.isLinked(note, ids: task.linkedNoteIDs, notes: store.notes) }, set: { enabled in
                            if enabled { task.linkedNoteIDs.append(MacTaskNotes.token(note, notes: store.notes)) }
                            else { task.linkedNoteIDs.removeAll { token in let matches = MacTaskNotes.matches(token, notes: store.notes); return matches.count == 1 && matches[0].path == note.path } }
                        })) { VStack(alignment: .leading) { Text(note.title); Text(note.folder).macFont(.caption2).foregroundStyle(.secondary) } }
                    }
                } }.frame(height: 160)
            }
            if !connected { Text("The vault changed. Close this form and reopen its task.").foregroundStyle(.red).macFont(.caption) }
            if let issue { Text(issue).foregroundStyle(.red).macFont(.caption) }
            HStack {
                Label(session.recovered ? "Recovered task draft" : session.record != nil ? "Draft kept on this Mac" : "Changes are kept privately", systemImage: "doc.badge.clock").macFont(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Export draft…") { do { try MacTaskDraftExport.save(task.shareDraft) } catch { issue = error.localizedDescription } }
            }
            if let warning = session.issue { Text(MacTaskDraftExport.message(warning)).macFont(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Discard draft…") { review = .discard }
                if task.baseline != nil { Button("Reload…") { review = .reload } }
                Button("Save as new…") { review = .copy }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !datesValid)
            }.macFont(.caption).disabled(!connected)
            HStack { if task.baseline != nil { Button("Delete…", role: .destructive) { deleting = true }.disabled(!connected) }; Spacer(); Button("Close") { session.keep(); dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { Task { _ = await commit() } }.keyboardShortcut(.defaultAction).disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connected || !datesValid) }.disabled(saving)
        }.padding(24).frame(width: 620).disabled(saving).interactiveDismissDisabled(saving)
        .onDisappear { session.keep() }
        .alert(review?.title ?? "Task draft", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), presenting: review) { choice in
            Button("Cancel", role: .cancel) {}
            switch choice {
            case .discard: Button("Discard draft", role: .destructive) { do { try session.discard(); dismiss() } catch { issue = error.localizedDescription } }
            case .reload: Button("Discard draft and reload", role: .destructive) { Task { saving = true; defer { saving = false }; do { guard let origin = task.workspaceID else { throw VaultFailure(message: "Reopen this task in its original vault.") }; let latest = try await store.reloadTask(id: task.id, workspaceID: origin); try session.discard(); session.committed(latest); dueVisibility = nil; issue = nil } catch { issue = error.localizedDescription } } }
            case .copy: Button("Save new task") { Task { _ = await commit(copy: true) } }
            }
        } message: { Text($0.message) }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $deleting) { Button("Delete task", role: .destructive) { Task { _ = await commit(delete: true) } } }
    }
    private func commit(delete: Bool = false, copy: Bool = false) async -> Bool {
        guard delete || datesValid else { issue = "Correct the task dates before saving."; return false }
        saving = true; defer { saving = false }
        let success = await store.commitTaskDraft(session, delete: delete, copy: copy)
        if success { dismiss() } else { issue = store.issue ?? "The task could not be saved. Your draft remains open."; store.issue = nil }
        return success
    }
}
