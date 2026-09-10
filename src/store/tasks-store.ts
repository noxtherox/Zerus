import { useSyncExternalStore } from "react";
import { getVaultBackend } from "@/store/notes-store";
import { normalizeListOptions } from "@/lib/properties";
import { localDateKey, normalizeTaskData, removeTaskCategory, type Task, type TaskList, type TaskPatch } from "@/lib/tasks";

const TASKS_PATH = ".zerus/tasks.json";
let tasks: Task[] = [];
let lists: TaskList[] = [];
let generalListName = "General";
let categoryOptions: string[] = [];
let location: string | null = null;
let loadGeneration = 0;
let localRevision = 0;
let writes: Promise<void> = Promise.resolve();
const listeners = new Set<() => void>();

function emit() { listeners.forEach((listener) => listener()); }
function subscribe(listener: () => void) { listeners.add(listener); return () => listeners.delete(listener); }
function snapshot() { return tasks; }
function generalListNameSnapshot() { return generalListName; }

export function useGeneralTaskListName(): string {
  return useSyncExternalStore(subscribe, generalListNameSnapshot, generalListNameSnapshot);
}

function listsSnapshot() { return lists; }

export function useTaskLists(): TaskList[] {
  return useSyncExternalStore(subscribe, listsSnapshot, listsSnapshot);
}

function categoryOptionsSnapshot() { return categoryOptions; }

export function useTasks(): Task[] {
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

export function useTaskCategoryOptions(): string[] {
  return useSyncExternalStore(subscribe, categoryOptionsSnapshot, categoryOptionsSnapshot);
}

export async function loadTasks(vaultLocation: string | null): Promise<void> {
  const generation = ++loadGeneration;
  location = vaultLocation;
  const backend = getVaultBackend();
  if (!backend || !vaultLocation) { tasks = []; lists = []; generalListName = "General"; categoryOptions = []; emit(); return; }
  try {
    const loaded = normalizeTaskData(JSON.parse(await backend.readText(TASKS_PATH)));
    if (generation !== loadGeneration || location !== vaultLocation) return;
    tasks = loaded.tasks;
    lists = loaded.lists;
    generalListName = loaded.generalListName ?? "General";
    categoryOptions = loaded.categoryOptions;
  } catch {
    if (generation !== loadGeneration || location !== vaultLocation) return;
    tasks = [];
    lists = [];
    generalListName = "General";
    categoryOptions = [];
  }
  emit();
}

function taskDataMatches(nextTasks: Task[], nextCategoryOptions: string[], nextLists: TaskList[]): boolean {
  return JSON.stringify({ tasks, categoryOptions, lists }) ===
    JSON.stringify({ tasks: nextTasks, categoryOptions: nextCategoryOptions, lists: nextLists });
}

/** Reloads task data delivered by the vault's filesystem sync provider. */
export async function refreshTasks(): Promise<void> {
  const backend = getVaultBackend();
  const refreshLocation = location;
  const generation = loadGeneration;
  const revision = localRevision;
  const pendingWrites = writes;
  if (!backend || !refreshLocation) return;

  // Never read behind a local write. A task edit made while this refresh is in
  // flight also wins over the older disk snapshot we may have just read.
  await pendingWrites;
  if (
    generation !== loadGeneration ||
    refreshLocation !== location ||
    revision !== localRevision ||
    backend !== getVaultBackend()
  ) return;

  try {
    const loaded = normalizeTaskData(JSON.parse(await backend.readText(TASKS_PATH)));
    if (
      generation !== loadGeneration ||
      refreshLocation !== location ||
      revision !== localRevision ||
      backend !== getVaultBackend() ||
      (generalListName === (loaded.generalListName ?? "General") && taskDataMatches(loaded.tasks, loaded.categoryOptions, loaded.lists))
    ) return;
    tasks = loaded.tasks;
    lists = loaded.lists;
    generalListName = loaded.generalListName ?? "General";
    categoryOptions = loaded.categoryOptions;
    emit();
  } catch {
    // A cloud provider can expose a file briefly while it is being replaced.
    // Keep the last good task snapshot and retry on the next refresh.
  }
}

function persist(next: Task[], nextCategoryOptions = categoryOptions, nextLists = lists) {
  const backend = getVaultBackend();
  if (!backend) return;
  const data = JSON.stringify({ tasks: next, categoryOptions: nextCategoryOptions, lists: nextLists, ...(generalListName !== "General" ? { generalListName } : {}) }, null, 2);
  writes = writes.then(() => backend.write(TASKS_PATH, data)).catch((error) => {
    console.error("Zerus: failed to save tasks", error);
  });
}

export function createTask(title: string, listId: string | null = null): Task | null {
  const cleanTitle = title.trim();
  if (!cleanTitle) return null;
  const now = new Date();
  const task: Task = { id: crypto.randomUUID(), listId: lists.some((list) => list.id === listId) ? listId : null, title: cleanTitle, completed: false, category: null, priority: "none", date: localDateKey(now), dueDate: null, completedAt: null, linkedNoteIds: [], createdAt: now.toISOString() };
  tasks = [...tasks, task]; localRevision += 1; emit(); persist(tasks); return task;
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
  localRevision += 1;
  emit(); persist(tasks);
}

export function deleteTask(id: string): void {
  const next = tasks.filter((task) => task.id !== id);
  if (next.length === tasks.length) return;
  tasks = next;
  localRevision += 1;
  emit();
  persist(tasks);
}

export function updateTaskCategoryOptions(options: string[]): void {
  const next = normalizeListOptions(options);
  if (next.length === categoryOptions.length && next.every((option, index) => option === categoryOptions[index])) return;
  categoryOptions = next;
  localRevision += 1;
  emit();
  persist(tasks, categoryOptions);
}

export function deleteTaskCategory(category: string): void {
  const next = removeTaskCategory({ tasks, categoryOptions, lists }, category);
  const changed = next.tasks.some((task, index) => task !== tasks[index]) ||
    next.categoryOptions.length !== categoryOptions.length;
  if (!changed) return;
  tasks = next.tasks;
  categoryOptions = next.categoryOptions;
  localRevision += 1;
  emit();
  persist(tasks, categoryOptions);
}

export function createTaskList(name: string): TaskList | null {
  const cleanName = name.trim();
  if (!cleanName || cleanName.toLowerCase() === generalListName.toLowerCase() || lists.some((list) => list.name.toLowerCase() === cleanName.toLowerCase())) return null;
  const list: TaskList = { id: crypto.randomUUID(), name: cleanName };
  lists = [...lists, list];
  localRevision += 1;
  emit();
  persist(tasks);
  return list;
}

export function renameTaskList(id: string | null, name: string): boolean {
  const cleanName = name.trim();
  const list = id === null ? { name: generalListName } : lists.find((list) => list.id === id);
  if (!list || !cleanName || (id !== null && cleanName.toLowerCase() === generalListName.toLowerCase()) ||
    lists.some((list) => list.id !== id && list.name.toLowerCase() === cleanName.toLowerCase())) return false;
  if (list.name === cleanName) return true;
  if (id === null) generalListName = cleanName;
  else lists = lists.map((list) => list.id === id ? { ...list, name: cleanName } : list);
  localRevision += 1;
  emit();
  persist(tasks);
  return true;
}

export function deleteTaskList(id: string): void {
  if (!lists.some((list) => list.id === id)) return;
  lists = lists.filter((list) => list.id !== id);
  tasks = tasks.map((task) => task.listId === id ? { ...task, listId: null } : task);
  localRevision += 1;
  emit();
  persist(tasks);
}
