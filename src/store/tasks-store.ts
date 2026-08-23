import { useSyncExternalStore } from "react";
import { getVaultBackend } from "@/store/notes-store";
import { localDateKey, normalizeTasks, type Task, type TaskPatch } from "@/lib/tasks";

const TASKS_PATH = ".zerus/tasks.json";
let tasks: Task[] = [];
let location: string | null = null;
let loadGeneration = 0;
let writes: Promise<void> = Promise.resolve();
const listeners = new Set<() => void>();

function emit() { listeners.forEach((listener) => listener()); }
function subscribe(listener: () => void) { listeners.add(listener); return () => listeners.delete(listener); }
function snapshot() { return tasks; }

export function useTasks(): Task[] {
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

export async function loadTasks(vaultLocation: string | null): Promise<void> {
  const generation = ++loadGeneration;
  location = vaultLocation;
  const backend = getVaultBackend();
  if (!backend || !vaultLocation) { tasks = []; emit(); return; }
  try {
    const loaded = normalizeTasks(JSON.parse(await backend.readText(TASKS_PATH)));
    if (generation !== loadGeneration || location !== vaultLocation) return;
    tasks = loaded;
  } catch {
    if (generation !== loadGeneration || location !== vaultLocation) return;
    tasks = [];
  }
  emit();
}

function persist(next: Task[]) {
  const backend = getVaultBackend();
  if (!backend) return;
  writes = writes.then(() => backend.write(TASKS_PATH, JSON.stringify(next, null, 2))).catch((error) => {
    console.error("Zerus: failed to save tasks", error);
  });
}

export function createTask(title: string): Task | null {
  const cleanTitle = title.trim();
  if (!cleanTitle) return null;
  const now = new Date();
  const task: Task = { id: crypto.randomUUID(), title: cleanTitle, completed: false, category: null, priority: "none", date: localDateKey(now), dueDate: null, completedAt: null, linkedNoteIds: [], createdAt: now.toISOString() };
  tasks = [...tasks, task]; emit(); persist(tasks); return task;
}

export function updateTask(id: string, patch: TaskPatch): void {
  const now = new Date().toISOString();
  tasks = tasks.map((task) => {
    if (task.id !== id) return task;
    const completed = patch.completed ?? task.completed;
    return { ...task, ...patch, id: task.id, createdAt: task.createdAt,
      completedAt: completed ? (task.completedAt ?? now) : null,
      linkedNoteIds: patch.linkedNoteIds ? [...new Set(patch.linkedNoteIds)] : task.linkedNoteIds,
    };
  });
  emit(); persist(tasks);
}
