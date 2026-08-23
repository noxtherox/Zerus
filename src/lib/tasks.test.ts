import { describe, expect, it } from "vitest";
import { normalizeTaskData, normalizeTasks, removeTaskCategory, sortTasks, tasksForView, type Task } from "./tasks";

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

  it("migrates legacy task categories into customizable single-select options", () => {
    expect(normalizeTaskData([
      task({ id: "first", category: " Work " }),
      task({ id: "second", category: "work" }),
      task({ id: "third", category: "Personal" }),
    ])).toEqual(expect.objectContaining({
      categoryOptions: ["Work", "Personal"],
    }));
  });

  it("normalizes persisted category options without hard-coding task values", () => {
    expect(normalizeTaskData({
      tasks: [task({ category: "Legacy value" })],
      categoryOptions: [" Work ", "work", "Personal", 4],
    })).toEqual(expect.objectContaining({
      categoryOptions: ["Work", "Personal"],
    }));
  });

  it("deletes a category option and clears it from every matching task", () => {
    const data = {
      categoryOptions: ["Work", "Personal"],
      tasks: [
        task({ id: "first", category: "Work" }),
        task({ id: "second", category: "work" }),
        task({ id: "third", category: "Personal" }),
      ],
    };

    expect(removeTaskCategory(data, " WORK ")).toEqual({
      categoryOptions: ["Personal"],
      tasks: [
        expect.objectContaining({ id: "first", category: null }),
        expect.objectContaining({ id: "second", category: null }),
        expect.objectContaining({ id: "third", category: "Personal" }),
      ],
    });
  });

  it("shows active tasks first in All and filters Today and Completed", () => {
    const tasks = [task({ id: "done", completed: true }), task({ id: "other", date: "2026-08-24" }), task({ id: "today" })];
    expect(tasksForView(tasks, "all", "2026-08-23").map(({ id }) => id)).toEqual(["other", "today", "done"]);
    expect(tasksForView(tasks, "today", "2026-08-23").map(({ id }) => id)).toEqual(["today", "done"]);
    expect(tasksForView(tasks, "completed", "2026-08-23").map(({ id }) => id)).toEqual(["done"]);
  });

  it("sorts within active and completed groups by requested descending timestamps or title", () => {
    const tasks = [
      task({ id: "active-old", title: "Zulu", createdAt: "2026-08-20T10:00:00.000Z" }),
      task({ id: "done-old", title: "Bravo", completed: true, createdAt: "2026-08-20T11:00:00.000Z", completedAt: "2026-08-21T10:00:00.000Z" }),
      task({ id: "active-new", title: "Alpha", createdAt: "2026-08-23T10:00:00.000Z" }),
      task({ id: "done-new", title: "Charlie", completed: true, createdAt: "2026-08-22T10:00:00.000Z", completedAt: "2026-08-23T11:00:00.000Z" }),
    ];

    expect(sortTasks(tasks, "recently-created").map(({ id }) => id)).toEqual(["active-new", "active-old", "done-new", "done-old"]);
    expect(sortTasks(tasks, "recently-completed").map(({ id }) => id)).toEqual(["active-new", "active-old", "done-new", "done-old"]);
    expect(sortTasks(tasks, "title-asc").map(({ id }) => id)).toEqual(["active-new", "active-old", "done-old", "done-new"]);
    expect(sortTasks(tasks, "title-desc").map(({ id }) => id)).toEqual(["active-old", "active-new", "done-new", "done-old"]);
  });

  it("moves tasks between the active and completed parts of All immediately", () => {
    const tasks = [task({ id: "first" }), task({ id: "second", createdAt: "2026-08-23T09:00:00.000Z" })];

    const completed = tasks.map((item) => item.id === "first" ? { ...item, completed: true } : item);
    expect(tasksForView(completed, "all").map(({ id }) => id)).toEqual(["second", "first"]);

    const restored = completed.map((item) => item.id === "first" ? { ...item, completed: false } : item);
    expect(tasksForView(restored, "all").map(({ id }) => id)).toEqual(["first", "second"]);
  });
});
