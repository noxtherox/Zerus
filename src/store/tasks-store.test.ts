import { beforeEach, describe, expect, it, vi } from "vitest";

const backend = vi.hoisted(() => ({
  readText: vi.fn(),
  write: vi.fn(),
}));

vi.mock("@/store/notes-store", () => ({
  getVaultBackend: () => backend,
}));

import { createTask, createTaskList, renameTaskList, deleteTaskList, updateTask, deleteTask, loadTasks, refreshTasks } from "./tasks-store";

describe("tasks store", () => {
  beforeEach(() => {
    backend.readText.mockReset();
    backend.write.mockReset().mockResolvedValue(undefined);
  });

  it("persists empty lists, task membership and moves through reloads", async () => {
    backend.readText.mockResolvedValue(JSON.stringify({ tasks: [], categoryOptions: [] }));
    await loadTasks("/test-vault");
    const work = createTaskList(" Work ")!;
    expect(createTaskList("work")).toBeNull();
    expect(createTaskList("General")).toBeNull();
    const task = createTask("Work task", work.id)!;
    createTask("General task");
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledTimes(3));
    const saved = JSON.parse(backend.write.mock.calls[2][1]);
    expect(saved.lists).toEqual([{ id: work.id, name: "Work" }]);
    expect(saved.tasks.map((item: { listId: string | null }) => item.listId)).toEqual([work.id, null]);
    backend.readText.mockResolvedValue(JSON.stringify(saved));
    await loadTasks("/test-vault");
    updateTask(task.id, { listId: null });
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledTimes(4));
    expect(JSON.parse(backend.write.mock.calls[3][1]).lists).toEqual(saved.lists);
    expect(JSON.parse(backend.write.mock.calls[3][1]).tasks[0].listId).toBeNull();
  });

  it("persists and refreshes the default list name without changing its tasks", async () => {
    backend.readText.mockResolvedValue(JSON.stringify({
      tasks: [{ id: "default-task", title: "Keep me", linkedNoteIds: ["note"] }],
      lists: [{ id: "work", name: "Work" }],
    }));
    await loadTasks("/test-vault");
    expect(renameTaskList(null, "work")).toBe(false);
    expect(renameTaskList(null, " ")).toBe(false);
    expect(renameTaskList(null, " Inbox ")).toBe(true);
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    const saved = JSON.parse(backend.write.mock.calls[0][1]);
    expect(saved.generalListName).toBe("Inbox");
    expect(saved.tasks[0]).toEqual(expect.objectContaining({ listId: null, linkedNoteIds: ["note"] }));
    backend.readText.mockResolvedValue(JSON.stringify(saved));
    await loadTasks("/test-vault");
    expect(createTaskList("inbox")).toBeNull();
    expect(renameTaskList("work", "INBOX")).toBe(false);
    backend.readText.mockResolvedValue(JSON.stringify({ ...saved, generalListName: "Personal" }));
    await refreshTasks();
    expect(createTaskList("personal")).toBeNull();
    expect(renameTaskList(null, "General")).toBe(true);
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledTimes(2));
    expect(JSON.parse(backend.write.mock.calls[1][1]).generalListName).toBeUndefined();
  });

  it("renames lists without changing membership and rejects invalid names", async () => {
    backend.readText.mockResolvedValue(JSON.stringify({
      lists: [{ id: "work", name: "Work" }, { id: "home", name: "Home" }],
      tasks: [{ id: "task", title: "Keep me", listId: "work" }],
      categoryOptions: [],
    }));
    await loadTasks("/test-vault");
    expect(renameTaskList("work", " ")).toBe(false);
    expect(renameTaskList("work", "GENERAL")).toBe(false);
    expect(renameTaskList("work", "home")).toBe(false);
    expect(renameTaskList("missing", "New")).toBe(false);
    expect(backend.write).not.toHaveBeenCalled();
    expect(renameTaskList("work", " Projects ")).toBe(true);
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    const saved = JSON.parse(backend.write.mock.calls[0][1]);
    expect(saved.lists).toEqual([{ id: "work", name: "Projects" }, { id: "home", name: "Home" }]);
    expect(saved.tasks[0].listId).toBe("work");
    backend.readText.mockResolvedValue(JSON.stringify(saved));
    await loadTasks("/test-vault");
    expect(createTaskList("projects")).toBeNull();
  });

  it("deletes only the list and moves active and completed tasks to General", async () => {
    backend.readText.mockResolvedValue(JSON.stringify({
      lists: [{ id: "work", name: "Work" }, { id: "home", name: "Home" }],
      tasks: [
        { id: "active", title: "Active", listId: "work", linkedNoteIds: ["note-1"] },
        { id: "done", title: "Done", listId: "work", completed: true, completedAt: "2026-09-01T10:00:00Z" },
        { id: "other", title: "Other", listId: "home" },
      ],
      categoryOptions: ["Keep"],
    }));
    await loadTasks("/test-vault");
    deleteTaskList("missing");
    expect(backend.write).not.toHaveBeenCalled();
    deleteTaskList("work");
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    const saved = JSON.parse(backend.write.mock.calls[0][1]);
    expect(saved.lists).toEqual([{ id: "home", name: "Home" }]);
    expect(saved.categoryOptions).toEqual(["Keep"]);
    expect(saved.tasks).toEqual([
      expect.objectContaining({ id: "active", listId: null, linkedNoteIds: ["note-1"] }),
      expect.objectContaining({ id: "done", listId: null, completed: true, completedAt: "2026-09-01T10:00:00Z" }),
      expect.objectContaining({ id: "other", listId: "home" }),
    ]);
    backend.readText.mockResolvedValue(JSON.stringify(saved));
    await loadTasks("/test-vault");
    updateTask("active", { title: "Still here" });
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledTimes(2));
    expect(JSON.parse(backend.write.mock.calls[1][1]).tasks[0]).toEqual(
      expect.objectContaining({ title: "Still here", listId: null, linkedNoteIds: ["note-1"] }),
    );
  });

  it("deletes a task and its note relations from persisted task data", async () => {
    backend.readText.mockResolvedValue(JSON.stringify({
      categoryOptions: ["Work"],
      tasks: [
        {
          id: "delete-me",
          title: "Delete me",
          completed: false,
          category: "Work",
          priority: "none",
          date: "2026-08-24",
          dueDate: null,
          completedAt: null,
          linkedNoteIds: ["note-1", "note-2"],
          createdAt: "2026-08-24T10:00:00.000Z",
        },
        {
          id: "keep-me",
          title: "Keep me",
          completed: false,
          category: null,
          priority: "none",
          date: "2026-08-24",
          dueDate: null,
          completedAt: null,
          linkedNoteIds: ["note-1"],
          createdAt: "2026-08-24T11:00:00.000Z",
        },
      ],
    }));

    await loadTasks("/test-vault");
    deleteTask("delete-me");

    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    const [path, content] = backend.write.mock.calls[0];
    expect(path).toBe(".zerus/tasks.json");
    expect(JSON.parse(content)).toEqual({
      lists: [],
      categoryOptions: ["Work"],
      tasks: [expect.objectContaining({ id: "keep-me", linkedNoteIds: ["note-1"] })],
    });
  });

  it("refreshes task changes that arrive through the open vault", async () => {
    backend.readText
      .mockResolvedValueOnce(JSON.stringify({ tasks: [], categoryOptions: [] }))
      .mockResolvedValueOnce(JSON.stringify({
        categoryOptions: ["Synced"],
        tasks: [{
          id: "from-another-device",
          title: "Synced task",
          completed: false,
          category: "Synced",
          priority: "none",
          date: "2026-08-26",
          dueDate: null,
          completedAt: null,
          linkedNoteIds: [],
          createdAt: "2026-08-26T10:00:00.000Z",
        }],
      }));

    await loadTasks("/test-vault");
    await refreshTasks();
    deleteTask("from-another-device");

    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    expect(JSON.parse(backend.write.mock.calls[0][1])).toEqual({
      lists: [],
      categoryOptions: ["Synced"],
      tasks: [],
    });
  });

  it("does not replace a newer local edit with a stale refresh", async () => {
    let resolveRefresh!: (value: string) => void;
    backend.readText
      .mockResolvedValueOnce(JSON.stringify({ tasks: [], categoryOptions: [] }))
      .mockImplementationOnce(() => new Promise((resolve) => { resolveRefresh = resolve; }));

    await loadTasks("/test-vault");
    const refresh = refreshTasks();
    await vi.waitFor(() => expect(backend.readText).toHaveBeenCalledTimes(2));
    const localTask = createTask("Keep local edit");
    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    backend.write.mockClear();

    resolveRefresh(JSON.stringify({
      tasks: [{
        id: "stale-task",
        title: "Stale task",
        completed: false,
        category: null,
        priority: "none",
        date: "2026-08-26",
        dueDate: null,
        completedAt: null,
        linkedNoteIds: [],
        createdAt: "2026-08-26T09:00:00.000Z",
      }],
      categoryOptions: [],
    }));
    await refresh;
    deleteTask(localTask!.id);

    await vi.waitFor(() => expect(backend.write).toHaveBeenCalledOnce());
    expect(JSON.parse(backend.write.mock.calls[0][1]).tasks).toEqual([]);
  });
});
