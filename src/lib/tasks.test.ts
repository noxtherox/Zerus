import { describe, expect, it } from "vitest";
import { normalizeTasks, tasksForView, type Task } from "./tasks";

const task = (patch: Partial<Task>): Task => ({
  id: "task-1", title: "First", completed: false, category: null,
  priority: "none", date: "2026-08-23", dueDate: null, completedAt: null,
  linkedNoteIds: [], createdAt: "2026-08-23T10:00:00.000Z", ...patch,
});

describe("tasks", () => {
  it("normalizes portable task data and keeps note links as a collection", () => {
    expect(normalizeTasks([{ id: "1", title: "  Ship  ", linkedNoteIds: ["n1", "n1", 2], priority: "urgent", createdAt: "2026-08-23T10:00:00Z" }])).toEqual([
      expect.objectContaining({ title: "Ship", priority: "none", linkedNoteIds: ["n1"], date: "2026-08-23" }),
    ]);
  });

  it("shows active tasks first in All and filters Today and Completed", () => {
    const tasks = [task({ id: "done", completed: true }), task({ id: "other", date: "2026-08-24" }), task({ id: "today" })];
    expect(tasksForView(tasks, "all", "2026-08-23").map(({ id }) => id)).toEqual(["today", "other", "done"]);
    expect(tasksForView(tasks, "today", "2026-08-23").map(({ id }) => id)).toEqual(["today", "done"]);
    expect(tasksForView(tasks, "completed", "2026-08-23").map(({ id }) => id)).toEqual(["done"]);
  });
});
