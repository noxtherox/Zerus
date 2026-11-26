import SwiftUI

struct MacTaskCollectionContext: Identifiable { let id: UUID }
private struct MacTaskNameRequest: Identifiable {
    enum Kind { case createList, renameList(NativeTaskList?), category }
    let id = UUID()
    let title: String
    let original: String
    let kind: Kind
}
private struct MacTaskCollectionReview: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let change: NativeTaskChange
}

struct MacTaskCollectionsView: View {
    @Bindable var store: MacWorkspace
    let workspaceID: UUID
    @State private var naming: MacTaskNameRequest?
    @State private var review: MacTaskCollectionReview?
    @Environment(\.dismiss) private var dismiss
    private var connected: Bool { store.workspaceID == workspaceID }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Lists & categories").macFont(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            if connected {
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Task lists").macFont(.headline); Spacer(); Button("New list…") { naming = .init(title: "New task list", original: "", kind: .createList) } }
                    HStack { Text(store.generalTaskListName); Spacer(); Text("Default list").macFont(.caption).foregroundStyle(.secondary); Button("Rename…") { naming = .init(title: "Rename default list", original: store.generalTaskListName, kind: .renameList(nil)) }.accessibilityLabel("Rename default task list") }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    ForEach(store.taskLists) { list in
                        HStack { VStack(alignment: .leading) { Text(list.name); Text("\(store.tasks.filter { $0.listID == list.id }.count) tasks").macFont(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Rename…") { naming = .init(title: "Rename task list", original: list.name, kind: .renameList(list)) }.accessibilityLabel("Rename " + list.name); Button("Delete…", role: .destructive) {
                            let assigned = Set(store.tasks.filter { $0.listID == list.id }.map(\.id))
                            review = .init(title: "Delete “\(list.name)”?", detail: "\(assigned.count) tasks move to \(store.generalTaskListName). Their supporting notes are kept.", change: .deleteList(list, assigned: assigned))
                        }.accessibilityLabel("Delete list " + list.name) }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Divider().padding(.vertical, 6)
                    HStack { Text("Categories").macFont(.headline); Spacer(); Button("New category…") { naming = .init(title: "New task category", original: "", kind: .category) } }
                    ForEach(store.taskCategories, id: \.self) { category in
                        HStack { Text(category); Spacer(); Button("Remove…", role: .destructive) {
                            let assigned = Set(store.tasks.filter { $0.category.caseInsensitiveCompare(category) == .orderedSame }.map(\.id))
                            review = .init(title: "Remove “\(category)”?", detail: "Clear this category from \(assigned.count) tasks. The tasks and their supporting notes are kept.", change: .deleteCategory(category, assigned: assigned))
                        }.accessibilityLabel("Remove category " + category) }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.disabled(store.tasksSaving) }
            } else { ContentUnavailableView("Vault changed", systemImage: "folder", description: Text("Reopen lists and categories in the vault you want to edit.")) }
        }.padding(24).frame(width: 650, height: 470)
        .macSheet(item: $naming) { request in
            MacTaskNameForm(store: store, request: request) { name in
                let change: NativeTaskChange
                switch request.kind {
                case .createList: change = .createList(id: UUID().uuidString.lowercased(), name: name)
                case .renameList(let list): change = .renameList(list, originalName: request.original, name: name)
                case .category: change = .addCategory(name)
                }
                return await store.changeTasks(change, workspaceID: workspaceID)
            }
        }
        .confirmationDialog(review?.title ?? "Apply task change?", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
            Button("Apply change", role: .destructive) { if let change = review?.change { Task { await store.changeTasks(change, workspaceID: workspaceID) } }; review = nil }
        } message: { Text(review?.detail ?? "") }
    }
}
private struct MacTaskNameForm: View {
    @Bindable var store: MacWorkspace
    let request: MacTaskNameRequest
    let save: (String) async -> Bool
    @State private var name = ""
    @State private var busy = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.title).macFont(.headline); TextField("Name", text: $name)
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { busy = true; Task { if await save(name) { dismiss() } else { issue = store.issue; store.issue = nil }; busy = false } }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
        }.padding(24).frame(width: 420).onAppear { name = request.original }
    }
}
