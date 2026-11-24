import Foundation

struct MacAgentPermissions {
    enum ReadScope: String, CaseIterable, Identifiable {
        case selected = "Chosen context", folder = "Folder", vault = "Entire vault"
        var id: String { rawValue }
    }
    var readScope = ReadScope.selected
    var folder = ""
    var create = false
    var creationFolder = ""
    var fileNotes = false
    var filingFolder = ""

    func scope(mode: NativeAgentMode, writes: NativeAgentPreferences.WriteScope, current: String?, paths: Set<String>, notes: [NoteDocument]) throws -> NativeAgentScope {
        if readScope == .folder { try NativePropertyDefinition.validateOwner(folder) }
        func includes(_ path: String) -> Bool {
            switch readScope {
            case .selected: return paths.contains(path)
            case .folder: return folder.isEmpty ? !path.contains("/") : path.hasPrefix(folder + "/")
            case .vault: return true
            }
        }
        let target = current.flatMap { path in notes.first { $0.path == path && !$0.trashed && NativeAgentNote.readable(path) && includes(path) } }
        if mode != .ask, writes == .current {
            guard let target, NativeAgentNote.ordinary(target.path), !target.archived, target.fileHub == nil else {
                throw VaultFailure(message: "Choose a writable current note within this run's read context before starting.")
            }
        }
        let canCreate = create && mode != .ask && writes != .current
        if canCreate, readScope == .selected { try NativePropertyDefinition.validateOwner(creationFolder) }
        return .init(paths: paths, folder: readScope == .folder ? folder : nil, entireVault: readScope == .vault,
                     currentWritePath: mode != .ask && writes == .current ? target?.path : nil,
                     currentReadPath: target?.path ?? "", createFolder: canCreate && readScope == .selected ? creationFolder : nil,
                     allowCreation: canCreate,
                     organizationFolder: fileNotes && readScope == .selected ? filingFolder : nil,
                     allowOrganizationMoves: fileNotes && mode != .ask && writes != .current)
    }
}
