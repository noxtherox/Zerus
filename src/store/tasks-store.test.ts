import { beforeEach, describe, expect, it, vi } from "vitest";

const backend = vi.hoisted(() => ({
  readText: vi.fn(),
  write: vi.fn(),
}));

vi.mock("@/store/notes-store", () => ({
  getVaultBackend: () => backend,
}));

import { deleteTask, loadTasks } from "./tasks-store";

describe("tasks store", () => {
  beforeEach(() => {
    backend.readText.mockReset();
    backend.write.mockReset().mockResolvedValue(undefined);
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
      categoryOptions: ["Work"],
      tasks: [expect.objectContaining({ id: "keep-me", linkedNoteIds: ["note-1"] })],
    });
  });
});
