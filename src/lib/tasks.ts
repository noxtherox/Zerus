import { normalizeListOptions } from "@/lib/properties";

export type TaskPriority = "none" | "low" | "medium" | "high";
export type TaskView = "all" | "today" | "completed";
export type TaskSort = "recently-completed" | "recently-created" | "title-asc" | "title-desc";

export interface Task {
  id: string;
  title: string;
  completed: boolean;
  category: string | null;
  priority: TaskPriority;
  date: string;
  dueDate: string | null;
  completedAt: string | null;
  linkedNoteIds: string[];
  createdAt: string;
}

export type TaskPatch = Partial<Omit<Task, "id" | "createdAt">>;

export interface TaskData {
  tasks: Task[];
  categoryOptions: string[];
}

export function localDateKey(date = new Date()): string {
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function normalizeTask(value: unknown): Task | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Record<string, unknown>;
  if (typeof candidate.id !== "string" || typeof candidate.title !== "string") {
    return null;
  }
  const createdAt =
    typeof candidate.createdAt === "string" && candidate.createdAt
      ? candidate.createdAt
      : new Date(0).toISOString();
  const priority: TaskPriority = ["low", "medium", "high"].includes(
    String(candidate.priority),
  )
    ? (candidate.priority as TaskPriority)
    : "none";
  return {
    id: candidate.id,
    title: candidate.title.trim(),
    completed: candidate.completed === true,
    category: optionalString(candidate.category),
    priority,
    date: optionalString(candidate.date) ?? localDateKey(new Date(createdAt)),
    dueDate: optionalString(candidate.dueDate),
    completedAt: optionalString(candidate.completedAt),
    linkedNoteIds: Array.isArray(candidate.linkedNoteIds)
      ? [...new Set(candidate.linkedNoteIds.filter((id): id is string => typeof id === "string" && Boolean(id)))]
      : [],
    createdAt,
  };
}

export function normalizeTasks(value: unknown): Task[] {
  if (!Array.isArray(value)) return [];
  return value.map(normalizeTask).filter((task): task is Task => task !== null);
}

/** Loads the current task file and migrates the legacy task-array format. */
export function normalizeTaskData(value: unknown): TaskData {
  if (Array.isArray(value)) {
    const tasks = normalizeTasks(value);
    return {
      tasks,
      categoryOptions: normalizeListOptions(
        tasks.flatMap((task) => task.category ? [task.category] : []),
      ),
    };
  }
  if (!value || typeof value !== "object") {
    return { tasks: [], categoryOptions: [] };
  }
  const candidate = value as Record<string, unknown>;
  return {
    tasks: normalizeTasks(candidate.tasks),
    categoryOptions: normalizeListOptions(
      Array.isArray(candidate.categoryOptions)
        ? candidate.categoryOptions.filter((option): option is string => typeof option === "string")
        : [],
    ),
  };
}

export function removeTaskCategory(data: TaskData, category: string): TaskData {
  const key = category.trim().toLowerCase();
  if (!key) return data;
  return {
    categoryOptions: data.categoryOptions.filter(
      (option) => option.toLowerCase() !== key,
    ),
    tasks: data.tasks.map((task) =>
      task.category?.toLowerCase() === key ? { ...task, category: null } : task,
    ),
  };
}

export function sortTasks(tasks: Task[], sort: TaskSort): Task[] {
  return [...tasks].sort((left, right) => {
    if (left.completed !== right.completed) return left.completed ? 1 : -1;
    if (sort === "title-asc" || sort === "title-desc") {
      const byTitle = left.title.localeCompare(right.title, undefined, { sensitivity: "base" });
      if (byTitle !== 0) return sort === "title-desc" ? -byTitle : byTitle;
    } else {
      const leftTimestamp = sort === "recently-completed"
        ? left.completedAt ?? left.createdAt
        : left.createdAt;
      const rightTimestamp = sort === "recently-completed"
        ? right.completedAt ?? right.createdAt
        : right.createdAt;
      const byTimestamp = rightTimestamp.localeCompare(leftTimestamp);
      if (byTimestamp !== 0) return byTimestamp;
    }
    return right.createdAt.localeCompare(left.createdAt);
  });
}

export function tasksForView(
  tasks: Task[],
  view: TaskView,
  today = localDateKey(),
  sort: TaskSort = "recently-created",
): Task[] {
  return sortTasks(
    tasks.filter((task) =>
      view === "completed"
        ? task.completed
        : view === "today"
          ? task.date === today
          : true,
    ),
    sort,
  );
}
