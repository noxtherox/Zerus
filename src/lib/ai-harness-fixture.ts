import type { VaultBackend } from "./vault/backend";
import type { Note } from "./note-utils";
import { noteBody } from "./frontmatter";
import { setZerusState } from "./zerus-metadata";
import { type NotesAgentPort } from "./ai-harness";

/** A disposable vault for outcome evaluations; never opens the user's vault. */
export async function disposableNotesVault(bodies: string[]) {
  const files = new Map<string, string>();
  let notes: Note[] = bodies.map((body, index) => ({
    id: `note-${index + 1}`,
    path: `inbox/Note-${index + 1}.md`,
    content: setZerusState(body, { id: `note-${index + 1}` }),
    pinned: false,
    updatedAt: new Date().toISOString(),
  }));
  notes.forEach((note) => files.set(note.path, note.content));
  const backend: VaultBackend = {
    kind: "browser",
    location: "Disposable agent evaluation",
    async loadAll() {
      return notes.map((note) => ({
        path: note.path,
        content: files.get(note.path)!,
        updatedAt: note.updatedAt,
      }));
    },
    async readText(path) {
      if (!files.has(path)) throw new Error("Missing file");
      return files.get(path)!;
    },
    async listFiles(path) {
      return [...files.keys()].filter((key) => key.startsWith(`${path}/`));
    },
    async write(path, content) {
      files.set(path, content);
    },
    async writeNew(path, content) {
      if (files.has(path)) throw new Error("Exists");
      files.set(path, content);
    },
    async move(from, to) {
      if (files.has(to)) throw new Error("Destination exists");
      await this.writeNew(to, await this.readText(from));
      files.delete(from);
    },
    async removeFile(path) {
      files.delete(path);
    },
    async exists(path) {
      return files.has(path);
    },
    async mkDir() {},
    async removeDir() {
      throw new Error("Unavailable in evaluations");
    },
    async renameDir() {
      throw new Error("Unavailable in evaluations");
    },
    async listDirs() {
      return ["inbox"];
    },
    async writeBinary() {
      throw new Error("No binary assets");
    },
    async readBinary() {
      throw new Error("No binary assets");
    },
  };
  const replace = (note: Note) => {
    notes = notes.map((item) => (item.id === note.id ? note : item));
    return note;
  };
  const port: NotesAgentPort = {
    backend,
    notes: () => notes,
    hydrate: async () => {},
    writable: async () => true,
    schemas: () => ({}),
    async write(note, content) {
      await backend.write(note.path, content);
      return replace({ ...note, content });
    },
    async create(id, typePath, content) {
      const note: Note = {
        id,
        path: `${typePath.join("/")}/${id}.md`,
        content,
        pinned: false,
        updatedAt: new Date().toISOString(),
      };
      await backend.writeNew(note.path, content);
      notes.push(note);
      return note;
    },
    async organize(note, args, path) {
      if (path !== note.path) await backend.move(note.path, path);
      const content = setZerusState(note.content, args);
      await backend.write(path, content);
      return replace({
        ...note,
        path,
        content,
        pinned: args.pinned ?? note.pinned,
        archived: args.archived ?? note.archived,
      });
    },
    async restore(snapshot, current) {
      if (!snapshot) {
        const path = `.trash/${current.path}`;
        await backend.move(current.path, path);
        return replace({ ...current, path });
      }
      if (snapshot.path !== current.path)
        await backend.move(current.path, snapshot.path);
      await backend.write(snapshot.path, snapshot.content);
      return replace({ ...current, ...snapshot });
    },
  };
  return {
    backend,
    port,
    files,
    body: (id = "note-1") =>
      noteBody(port.notes().find((note) => note.id === id)!.content),
    replace,
  };
}
