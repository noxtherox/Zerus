export type TaskPriority = "none" | "low" | "medium" | "high";
export type TaskView = "all" | "today" | "completed";

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

export function tasksForView(tasks: Task[], view: TaskView, today = localDateKey()): Task[] {
  return tasks
    .filter((task) =>
      view === "completed"
        ? task.completed
        : view === "today"
          ? task.date === today
          : true,
    )
    .sort((left, right) => {
      if (left.completed !== right.completed) return left.completed ? 1 : -1;
      if (left.date !== right.date) return left.date.localeCompare(right.date);
      return left.createdAt.localeCompare(right.createdAt);
    });
}
