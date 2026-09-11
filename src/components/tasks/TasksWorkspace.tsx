import { DateInput } from "@/components/ui/date-input";
import { formatDate, useDateFormat } from "@/lib/date-format";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Calendar,
  ChevronDown,
  Plus,
  CheckSquare,
  ArrowUpDown,
  Link2,
  Search,
  Trash2,
  MoreHorizontal,
  Pencil,
  X,
} from "@/lib/icons";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { TypeIcon } from "@/components/notes/TypeIcon";
import type { TypeIcons } from "@/lib/type-icons";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn } from "@/lib/utils";
import {
  isExternalNote,
  isTrashed,
  noteMatchesSearch,
  noteSnippet,
  noteTitle,
  noteTypePath,
  type Note,
  typeKey,
} from "@/lib/note-utils";
import { formatTaskDate, localDateKey, tasksForView, type Task, type TaskList, type TaskPatch, type TaskSort, type TaskView } from "@/lib/tasks";

interface TasksWorkspaceProps {
  tasks: Task[];
  lists: TaskList[];
  generalListName: string;
  onCreateList: (name: string) => TaskList | null;
  onRenameList: (id: string | null, name: string) => boolean;
  onDeleteList: (id: string) => void;
  notes: Note[];
  typeIcons: TypeIcons;
  selectedTaskId: string | null;
  onSelectedTaskChange: (id: string | null) => void;
  onCreateTask: (title: string, listId: string | null) => Task | null;
  onUpdateTask: (id: string, patch: TaskPatch) => void;
  onDeleteTask: (id: string) => void;
  onOpenNote: (id: string) => void;
  initialView?: TaskView;
}

const views: { value: TaskView; label: string }[] = [
  { value: "all", label: "All" },
  { value: "today", label: "Today" },
  { value: "completed", label: "Completed" },
];

const sorts: { value: TaskSort; label: string }[] = [
  { value: "recently-completed", label: "Recently completed" },
  { value: "recently-created", label: "Newest first" },
  { value: "title-asc", label: "Title A–Z" },
  { value: "title-desc", label: "Title Z–A" },
];

const TASK_COMPLETION_MS = 420;
const TASK_CREATION_MS = 280;

const ALL_TYPES = "__all_types__";
const UNTYPED = "__untyped__";

function noteTypeLabel(note: Note): string {
  return typeKey(noteTypePath(note)) || "No type";
}

function LinkNoteDialog({
  open,
  onOpenChange,
  notes,
  typeIcons,
  linkedNoteIds,
  onLink,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  notes: Note[];
  typeIcons: TypeIcons;
  linkedNoteIds: string[];
  onLink: (noteId: string) => void;
}) {
  const [query, setQuery] = useState("");
  const [selectedType, setSelectedType] = useState(ALL_TYPES);

  useEffect(() => {
    if (!open) {
      setQuery("");
      setSelectedType(ALL_TYPES);
    }
  }, [open]);

  const typeOptions = useMemo(
    () =>
      [...new Set(notes.map((note) => typeKey(noteTypePath(note))))].sort(
        (left, right) => left.localeCompare(right),
      ),
    [notes],
  );
  const linkedIds = useMemo(() => new Set(linkedNoteIds), [linkedNoteIds]);
  const results = useMemo(
    () =>
      notes
        .filter((note) => {
          const noteType = typeKey(noteTypePath(note));
          const matchesType =
            selectedType === ALL_TYPES ||
            (selectedType === UNTYPED ? !noteType : noteType === selectedType);
          return matchesType && noteMatchesSearch(note, query);
        })
        .sort((left, right) => noteTitle(left).localeCompare(noteTitle(right))),
    [notes, query, selectedType],
  );

  const choose = (noteId: string) => {
    if (linkedIds.has(noteId)) return;
    onLink(noteId);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl gap-5 p-5">
        <DialogHeader>
          <DialogTitle>Link a note</DialogTitle>
          <DialogDescription>
            Filter by type or search across your notes, then choose one to link.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-2 sm:grid-cols-[180px_minmax(0,1fr)]">
          <Select value={selectedType} onValueChange={setSelectedType}>
            <SelectTrigger aria-label="Filter notes by type">
              <SelectValue placeholder="All types" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL_TYPES}>All types</SelectItem>
              {typeOptions.includes("") && <SelectItem value={UNTYPED}>No type</SelectItem>}
              {typeOptions.filter(Boolean).map((noteType) => (
                <SelectItem key={noteType} value={noteType}>
                  {noteType}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div className="relative">
            <Search
              aria-hidden="true"
              className="pointer-events-none absolute left-3 top-1/2 z-10 -translate-y-1/2 text-muted-foreground"
              size={16}
            />
            <Input
              autoFocus
              className="pl-9"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search notes…"
              aria-label="Search notes"
            />
          </div>
        </div>

        <div className="max-h-80 min-h-48 overflow-y-auto rounded-lg border border-border/70 p-1.5">
          {results.length ? (
            <div className="space-y-1">
              {results.map((note) => {
                const isLinked = linkedIds.has(note.id);
                const snippet = noteSnippet(note);
                return (
                  <button
                    key={note.id}
                    type="button"
                    disabled={isLinked}
                    onClick={() => choose(note.id)}
                    className="flex w-full items-start gap-3 rounded-md px-3 py-2.5 text-left transition-colors hover:bg-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-default disabled:opacity-55"
                  >
                    <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
                      <TypeIcon icon={typeIcons[typeKey(noteTypePath(note))]} size={15} />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-2">
                        <span className="truncate text-sm font-medium">{noteTitle(note)}</span>
                        {isLinked && (
                          <span className="shrink-0 rounded-full bg-zerus-accent/15 px-2 py-0.5 text-[10px] font-medium text-zerus-accent">
                            Linked
                          </span>
                        )}
                      </span>
                      <span className="mt-0.5 block truncate text-xs text-muted-foreground">
                        {noteTypeLabel(note)}{snippet ? ` · ${snippet}` : ""}
                      </span>
                    </span>
                  </button>
                );
              })}
            </div>
          ) : (
            <div className="flex min-h-44 items-center justify-center px-6 text-center text-sm text-muted-foreground">
              No notes match this type and search.
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function TaskDetails({
  task,
  lists,
  generalListName,
  notes,
  typeIcons,
  onUpdate,
  onRequestDelete,
  onOpenNote,
}: {
  task: Task;
  lists: TaskList[];
  generalListName: string;
  notes: Note[];
  typeIcons: TypeIcons;
  onUpdate: (patch: TaskPatch) => void;
  onRequestDelete: () => void;
  onOpenNote: (id: string) => void;
}) {
  const dateFormat = useDateFormat();
  const [linkDialogOpen, setLinkDialogOpen] = useState(false);
  const linkedNotes = task.linkedNoteIds
    .map((id) => notes.find((note) => note.id === id))
    .filter((note): note is Note => Boolean(note));

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-5">
        <div className="space-y-5">
          <div className="flex items-start gap-3 rounded-lg border border-border/60 bg-background p-3">
            <Checkbox
              className="mt-2 shrink-0"
              checked={task.completed}
              onCheckedChange={(checked) => onUpdate({ completed: checked === true })}
              aria-label={task.completed ? "Mark task active" : "Complete task"}
            />
            <label className="min-w-0 flex-1">
              <span className="sr-only">Title</span>
              <textarea
                rows={3}
                className={cn("w-full resize-y rounded-sm bg-transparent py-1 text-base font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring", task.completed && "text-muted-foreground line-through")}
                value={task.title}
                onChange={(event) => onUpdate({ title: event.target.value })}
              />
            </label>
          </div>
          <label className="block text-xs text-muted-foreground">
            List
            <select
              className="mt-1 h-8 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground"
              value={task.listId ?? ""}
              onChange={(event) => onUpdate({ listId: event.target.value || null })}
            >
              <option value="">{generalListName}</option>
              {lists.map((list) => <option key={list.id} value={list.id}>{list.name}</option>)}
            </select>
          </label>
          <label className="block text-xs text-muted-foreground">
            Priority
            <select
              className="mt-1 h-8 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground"
              value={task.priority}
              onChange={(event) => onUpdate({ priority: event.target.value as Task["priority"] })}
            >
              <option value="none">None</option>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </label>
          <label className="block text-xs text-muted-foreground">
            Date
            <DateInput
              className="mt-1 h-8"
              value={task.date}
              onValueChange={(next) => onUpdate({ date: next })}
            />
          </label>
          <label className="block text-xs text-muted-foreground">
            Due date
            <DateInput
              className="mt-1 h-8"
              value={task.dueDate ?? ""}
              aria-label="Due date"
              onValueChange={(next) => onUpdate({ dueDate: next || null })}
            />
          </label>
          <div className="border-t border-border/60 pt-5">
            <span className="block text-xs text-muted-foreground">Linked notes</span>
            <div className="mt-1 flex min-h-8 flex-wrap items-center gap-1.5">
              {linkedNotes.map((note) => (
                <span key={note.id} className="inline-flex h-8 min-w-0 items-center rounded-md border border-border/70 bg-background">
                  <button
                    type="button"
                    className="flex min-w-0 items-center gap-1.5 px-2.5 text-xs hover:text-zerus-accent"
                    onClick={() => onOpenNote(note.id)}
                    title={`Open ${noteTitle(note)}`}
                  >
                    <TypeIcon icon={typeIcons[typeKey(noteTypePath(note))]} size={13} className="shrink-0" />
                    <span className="max-w-44 truncate">{noteTitle(note)}</span>
                  </button>
                  <button
                    type="button"
                    className="flex h-full items-center border-l border-border/60 px-2 text-muted-foreground hover:text-foreground"
                    aria-label={`Unlink ${noteTitle(note)}`}
                    onClick={() => onUpdate({ linkedNoteIds: task.linkedNoteIds.filter((id) => id !== note.id) })}
                  >
                    <X size={12} />
                  </button>
                </span>
              ))}
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="h-8"
                onClick={() => setLinkDialogOpen(true)}
              >
                <Link2 size={14} />
                Link a note
              </Button>
            </div>
          </div>
        </div>
        {task.completedAt && (
          <p className="mt-2 text-xs text-muted-foreground">
            Completed {formatDate(task.completedAt, dateFormat) + " " + new Date(task.completedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
          </p>
        )}
      </div>
      <div className="flex shrink-0 items-center justify-between gap-2 border-t border-border/60 px-5 py-3">
        <span className="text-xs text-muted-foreground">
          Created {formatDate(task.createdAt, dateFormat)}
        </span>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="h-8 text-destructive hover:bg-destructive/10 hover:text-destructive"
          onClick={onRequestDelete}
        >
          <Trash2 size={14} />
          Delete task
        </Button>
      </div>
      <LinkNoteDialog
        open={linkDialogOpen}
        onOpenChange={setLinkDialogOpen}
        notes={notes}
        typeIcons={typeIcons}
        linkedNoteIds={task.linkedNoteIds}
        onLink={(noteId) => onUpdate({ linkedNoteIds: [...task.linkedNoteIds, noteId] })}
      />
    </div>
  );
}

export function TasksWorkspace({
  tasks,
  lists,
  generalListName,
  onCreateList,
  onRenameList,
  onDeleteList,
  notes,
  typeIcons,
  selectedTaskId,
  onSelectedTaskChange,
  onCreateTask,
  onUpdateTask,
  onDeleteTask,
  onOpenNote,
  initialView = "all",
}: TasksWorkspaceProps) {
  const workspaceRef = useRef<HTMLElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const taskButtons = useRef(new Map<string, HTMLButtonElement>());
  const [isNarrow, setIsNarrow] = useState(false);
  const [selectedListId, setSelectedListId] = useState<string | null>(null);
  const activeListId = lists.some((list) => list.id === selectedListId) ? selectedListId : null;
  const [listDialogOpen, setListDialogOpen] = useState(false);
  const [listToRename, setListToRename] = useState<{ id: string | null; name: string } | null>(null);
  const [listToDelete, setListToDelete] = useState<TaskList | null>(null);
  const [listName, setListName] = useState("");
  const [listError, setListError] = useState("");
  const listCards = [{ id: null, name: generalListName }, ...lists];
  const selectedTask = tasks.filter((task) => (task.listId ?? null) === activeListId).find((task) => task.id === selectedTaskId) ?? null;

  useEffect(() => {
    const workspace = workspaceRef.current;
    if (!workspace) return;
    const observer = new ResizeObserver(([entry]) => setIsNarrow(entry.contentRect.width < 720));
    observer.observe(workspace);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (selectedTaskId) closeButtonRef.current?.focus({ preventScroll: true });
  }, [selectedTaskId]);

  const closeDetails = () => {
    const taskId = selectedTaskId;
    onSelectedTaskChange(null);
    requestAnimationFrame(() => {
      if (taskId) taskButtons.current.get(taskId)?.focus({ preventScroll: true });
    });
  };

  const [view, setView] = useState<TaskView>(initialView);
  const [sort, setSort] = useState<TaskSort>("recently-created");
  const [showAllCompleted, setShowAllCompleted] = useState(false);
  const [completedExpanded, setCompletedExpanded] = useState(false);
  const [today, setToday] = useState(() => localDateKey());
  useEffect(() => {
    const refreshDate = () => setToday(localDateKey());
    const timer = window.setInterval(refreshDate, 60_000);
    window.addEventListener("focus", refreshDate);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refreshDate);
    };
  }, []);
  const [draft, setDraft] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const normalizedSearch = searchQuery.trim().toLowerCase();
  const [taskToDelete, setTaskToDelete] = useState<Task | null>(null);
  // Persist completion immediately; only delay moving the row between sections.
  const [completingIds, setCompletingIds] = useState<Set<string>>(() => new Set());
  const [restoringTasks, setRestoringTasks] = useState<Map<string, Task>>(() => new Map());
  const [creatingIds, setCreatingIds] = useState<Set<string>>(() => new Set());
  const [emptyStateExiting, setEmptyStateExiting] = useState(false);
  const creationTimers = useRef(new Map<string, number>());
  useEffect(() => {
    const timers = creationTimers.current;
    return () => { timers.forEach((timer) => window.clearTimeout(timer)); };
  }, []);
  const completionTimers = useRef(new Map<string, number>());
  useEffect(() => {
    const timers = completionTimers.current;
    return () => { timers.forEach((timer) => window.clearTimeout(timer)); };
  }, []);
  const animateTaskCreation = (id: string) => {
    const replacesEmptyState = view !== "completed" && activeTasks.length === 0 && !normalizedSearch;
    if (replacesEmptyState) setEmptyStateExiting(true);
    setCreatingIds((previous) => new Set(previous).add(id));
    creationTimers.current.set(id, window.setTimeout(() => {
      creationTimers.current.delete(id);
      setCreatingIds((previous) => {
        const next = new Set(previous);
        next.delete(id);
        return next;
      });
      if (replacesEmptyState) setEmptyStateExiting(false);
    }, TASK_CREATION_MS));
  };
  const updateTask = (id: string, patch: TaskPatch) => {
    if (patch.completed !== undefined) {
      window.clearTimeout(completionTimers.current.get(id));
      completionTimers.current.delete(id);
      const restoring = !patch.completed ? tasks.find((task) => task.id === id && task.completed) : undefined;
      setRestoringTasks((previous) => {
        const next = new Map(previous);
        if (restoring) next.set(id, restoring);
        else next.delete(id);
        return next;
      });
      const animate = patch.completed && tasks.some((task) => task.id === id && !task.completed) && view !== "completed";
      setCompletingIds((previous) => {
        const next = new Set(previous);
        if (animate) next.add(id);
        else next.delete(id);
        return next;
      });
      if (animate || restoring) {
        completionTimers.current.set(id, window.setTimeout(() => {
          completionTimers.current.delete(id);
          if (restoring) {
            setRestoringTasks((previous) => {
              const next = new Map(previous);
              next.delete(id);
              return next;
            });
            animateTaskCreation(id);
          }
          setCompletingIds((previous) => {
            const next = new Set(previous);
            next.delete(id);
            return next;
          });
        }, TASK_COMPLETION_MS));
      }
    }
    onUpdateTask(id, patch);
  };
  const displayTasks = useMemo(() => tasks.map((task) =>
    completingIds.has(task.id) && view !== "completed"
      ? { ...task, completed: false, completedAt: null }
      : restoringTasks.has(task.id)
        ? { ...task, completed: true, completedAt: restoringTasks.get(task.id)!.completedAt }
        : task,
  ), [tasks, completingIds, restoringTasks, view]);
  const visibleTasks = useMemo(
    () => tasksForView(displayTasks.filter((task) => (task.listId ?? null) === activeListId), view, today, sort, showAllCompleted).filter((task) =>
      !normalizedSearch || task.title.toLowerCase().includes(normalizedSearch),
    ),
    [displayTasks, activeListId, view, today, sort, showAllCompleted, normalizedSearch],
  );
  const linkableNotes = useMemo(
    () => notes.filter((note) => !isExternalNote(note) && !isTrashed(note)),
    [notes],
  );
  const activeTasks = visibleTasks.filter((task) => !task.completed);
  const completedTasks = visibleTasks.filter((task) => task.completed);
  const completedOpen = view === "completed" || completedExpanded;
  const completedTotal = tasksForView(
    displayTasks.filter((task) => (task.listId ?? null) === activeListId), view, today, sort, true,
  ).filter((task) => task.completed && (!normalizedSearch ||
    task.title.toLowerCase().includes(normalizedSearch))).length;
  const submit = () => {
    const created = onCreateTask(draft, activeListId);
    if (!created) return;
    animateTaskCreation(created.id);
    setDraft("");
    setSearchQuery("");
    setView("all");
  };

  const renderTask = (task: Task) => {
    const isCompleting = completingIds.has(task.id) && view !== "completed";
    const isRestoring = restoringTasks.has(task.id);
    const isLeaving = isCompleting || isRestoring;
    const checked = !isRestoring && (task.completed || isCompleting);
    const isSelected = selectedTaskId === task.id;
    return (
      <div
        key={task.id}
        className={cn("task-row-shell", isLeaving ? "task-row-completing" : creatingIds.has(task.id) && "task-row-creating")}
        style={{ animationDuration: `${isLeaving ? TASK_COMPLETION_MS : TASK_CREATION_MS}ms` }}
      >
      <div className="min-h-0 overflow-hidden">
      <div
        className={cn(
          "group flex min-h-16 items-center gap-3 border-b px-3 transition-colors",
          isSelected ? "border-zerus-accent/25 bg-zerus-accent/10" : "border-border/35 hover:bg-muted/40",
        )}
      >
        <Checkbox
          className="shrink-0"
          checked={checked}
          onCheckedChange={(checked) => updateTask(task.id, { completed: checked === true })}
          aria-label={checked ? `Mark ${task.title} active` : `Complete ${task.title}`}
        />
        <button
          ref={(node) => {
            if (node) taskButtons.current.set(task.id, node);
            else taskButtons.current.delete(task.id);
          }}
          type="button"
          className="flex min-w-0 flex-1 flex-col gap-1 rounded-md py-2.5 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          aria-label={`Open ${task.title || "Untitled task"} details`}
          aria-expanded={isSelected}
          aria-controls={isSelected ? "task-details" : undefined}
          onClick={() => onSelectedTaskChange(task.id)}
        >
          <span className={cn("w-full truncate text-sm font-medium text-foreground", checked && "font-normal text-muted-foreground line-through")}>
            {task.title || "Untitled task"}
          </span>
          <span className="flex max-w-full flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
            {task.priority !== "none" && (
              <span className={cn("capitalize", task.priority === "high" && "text-destructive")}>{task.priority} priority</span>
            )}
            <span className="flex items-center gap-1"><Calendar size={12} /><time dateTime={task.date} title={task.date}>{formatTaskDate(task.date, today)}</time></span>
            {task.dueDate && <span>Due <time dateTime={task.dueDate} title={task.dueDate}>{formatTaskDate(task.dueDate, today).toLowerCase()}</time></span>}
            {task.linkedNoteIds.length > 0 && (
              <span className="flex items-center gap-1" aria-label={`${task.linkedNoteIds.length} linked notes`}>
                <Link2 size={13} />{task.linkedNoteIds.length}
              </span>
            )}
          </span>
        </button>
      </div>
      </div>
      </div>
    );
  };

  return (
    <main
      ref={workspaceRef}
      className="flex h-full min-w-0 overflow-hidden bg-background"
      onKeyDown={(event) => {
        if (event.key === "Escape" && !event.defaultPrevented && selectedTask &&
          !(event.target as HTMLElement).closest('[role="dialog"], [role="alertdialog"], [role="listbox"], [data-radix-popper-content-wrapper]')) {
          event.preventDefault();
          event.stopPropagation();
          closeDetails();
        }
      }}
    >
      <div className={cn("min-h-0 min-w-0 flex-1 flex-col", isNarrow && selectedTask ? "hidden" : "flex")}>

      <header className="border-b border-border/60 px-4 pb-3 pt-5 sm:px-6">
        <div className="flex items-center gap-2">
          <CheckSquare size={19} />
          <h2 className="text-lg font-semibold">Tasks</h2>
        </div>
        <div className="mt-4 flex gap-3 overflow-x-auto pb-2" role="group" aria-label="Task lists">
          {listCards.map((list) => {
            const count = tasks.filter((task) => (task.listId ?? null) === list.id && !task.completed).length;
            return (
              <div
                key={list.id ?? "general"}
                className={cn("relative w-40 shrink-0 rounded-xl border transition-colors",
                  activeListId === list.id ? "border-zerus-accent/50 bg-zerus-accent/10" : "border-border/60 bg-background/70 hover:bg-background")}
              >
                <button
                  type="button"
                  aria-pressed={activeListId === list.id}
                  onClick={() => { setSelectedListId(list.id); onSelectedTaskChange(null); setDraft(""); }}
                  className="w-full rounded-xl p-4 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <span className="block truncate pr-6 text-sm font-medium" title={list.name}>{list.name}</span>
                  <span className="mt-2 block text-xs text-muted-foreground">{count} {count === 1 ? "task" : "tasks"} to do</span>
                </button>
                <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon" className="absolute right-1 top-2 h-8 w-8" aria-label={`Options for ${list.name}`}>
                        <MoreHorizontal size={17} />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onSelect={() => {
                        setListToRename({ id: list.id, name: list.name });
                        setListName(list.name);
                        setListError("");
                        setListDialogOpen(true);
                      }}>
                        <Pencil className="mr-2" size={14} /> Rename list
                      </DropdownMenuItem>
                      {list.id !== null && <DropdownMenuItem className="text-destructive focus:text-destructive" onSelect={() => setListToDelete({ id: list.id!, name: list.name })}>
                        <Trash2 className="mr-2" size={14} /> Delete list
                      </DropdownMenuItem>}
                    </DropdownMenuContent>
                </DropdownMenu>
              </div>
            );
          })}
          <button
            type="button"
            className="flex w-32 shrink-0 flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-border px-4 py-3 text-sm text-muted-foreground hover:bg-background hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onClick={() => { setListToRename(null); setListName(""); setListError(""); setListDialogOpen(true); }}
          >
            <Plus size={18} /> New list
          </button>
        </div>
        <div className="mt-4 flex w-full flex-wrap items-center justify-between gap-3">
          <div className="flex gap-1" role="group" aria-label="Task views">
            {views.map((item) => (
              <button
                key={item.value}
                type="button"
                aria-pressed={view === item.value}
                onClick={() => { setView(item.value); onSelectedTaskChange(null); }}
                className={cn(
                  "rounded-md px-3 py-1.5 text-sm",
                  view === item.value
                    ? "bg-zerus-accent/15 text-zerus-accent"
                    : "text-muted-foreground hover:bg-muted",
                )}
              >
                {item.label}
              </button>
            ))}
          </div>
          <div className="flex min-w-0 flex-1 items-center justify-end gap-2 sm:flex-none">
            <div className="relative min-w-0 flex-1 sm:w-48 sm:flex-none">
              <Search
                aria-hidden="true"
                className="pointer-events-none absolute left-3 top-1/2 z-10 -translate-y-1/2 text-muted-foreground"
                size={16}
              />
              <Input
                type="search"
                className="h-8 bg-transparent pl-9 pr-8 text-xs [&::-webkit-search-cancel-button]:appearance-none"
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Escape" && searchQuery) {
                    event.preventDefault();
                    event.stopPropagation();
                    setSearchQuery("");
                  }
                }}
                placeholder="Search tasks…"
                aria-label="Search tasks"
              />
              {searchQuery && (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="absolute right-1 top-1/2 h-6 w-6 -translate-y-1/2"
                  aria-label="Clear task search"
                  onClick={() => setSearchQuery("")}
                >
                  <X size={15} />
                </Button>
              )}
            </div>
            <Select value={sort} onValueChange={(value) => setSort(value as TaskSort)}>
              <SelectTrigger className="h-8 w-40 shrink-0 bg-transparent text-xs" aria-label="Sort tasks">
                <ArrowUpDown size={13} className="mr-1 shrink-0" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {sorts.map((item) => (
                  <SelectItem key={item.value} value={item.value}>{item.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-6">
        <div className="w-full">
          <form className="mb-2 flex min-h-12 items-center gap-2 border-b border-border/60 px-3 focus-within:border-zerus-accent/60" onSubmit={(event) => { event.preventDefault(); submit(); }}>
            <Plus size={17} className="shrink-0 text-muted-foreground" aria-hidden="true" />
            <Input
              className="h-11 border-0 bg-transparent px-0 shadow-none focus-visible:ring-0 focus-visible:ring-offset-0"
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => { if (event.key === "Enter" && event.nativeEvent.isComposing) event.preventDefault(); }}
              placeholder="Add a task…"
              aria-label="New task title"
            />
            <Button type="submit" size="sm" className="h-8 bg-zerus-accent text-primary-foreground hover:bg-zerus-accent/90 disabled:bg-muted disabled:text-muted-foreground" disabled={!draft.trim()}>Add</Button>
          </form>
          {view !== "completed" && (
            <section aria-label="Active tasks">
              {activeTasks.map(renderTask)}
              {(emptyStateExiting || activeTasks.every((task) => completingIds.has(task.id))) && (
                <div
                  className={cn("task-row-shell", emptyStateExiting ? "task-empty-exiting" : activeTasks.length > 0 && "task-empty-entering")}
                  style={{ animationDuration: `${emptyStateExiting ? TASK_CREATION_MS : TASK_COMPLETION_MS}ms` }}
                >
                <div className="min-h-0 overflow-hidden">
                <div className="px-3 py-10 text-center" role="status">
                  {!normalizedSearch && <CheckSquare size={24} className="mx-auto mb-3 text-zerus-accent/80" aria-hidden="true" />}
                  <p className="text-sm font-medium text-foreground">
                    {normalizedSearch ? "No active tasks match your search." : view === "today" ? "Nothing scheduled for today" : "You’re all caught up"}
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {normalizedSearch ? "Try a different title." : "Add a task above whenever you’re ready."}
                  </p>
                </div>
                </div>
                </div>
              )}
            </section>
          )}
          {(completedTotal > 0 || view === "completed") && (
            <section className="mt-5" aria-labelledby="completed-heading">
              {view === "completed" ? (
                <h3 id="completed-heading" className="px-3 py-2 text-xs font-medium text-muted-foreground">Completed · {completedTotal}</h3>
              ) : (
                <h3 id="completed-heading">
                  <button type="button" className="flex min-h-10 w-full items-center gap-2 rounded-md px-3 text-left text-xs font-medium text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    aria-expanded={completedOpen} aria-controls="completed-tasks"
                    onClick={() => setCompletedExpanded(!completedExpanded)}>
                    <ChevronDown size={14} className={cn("transition-transform", !completedOpen && "-rotate-90")} aria-hidden="true" />
                    Completed · {completedTotal}
                  </button>
                </h3>
              )}
              {completedOpen && (
                <div id="completed-tasks">
                  <div className="px-3 pb-3 pt-1">
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-muted-foreground">
                      <label className="flex cursor-pointer items-center gap-2">
                        <Checkbox
                          checked={showAllCompleted}
                          onCheckedChange={(checked) => {
                            setShowAllCompleted(checked === true);
                            onSelectedTaskChange(null);
                          }}
                        />
                        Show all completed tasks
                      </label>
                      {!showAllCompleted && <span>Showing the last 7 days.</span>}
                    </div>
                  </div>
                  {completedTasks.map(renderTask)}
                  {completedTasks.length === 0 && (
                    <p className="px-3 py-8 text-center text-sm text-muted-foreground" role="status">
                      {normalizedSearch ? "No completed tasks match your search in this period." : showAllCompleted ? "No completed tasks yet." : "No tasks completed in the last 7 days."}
                    </p>
                  )}
                </div>
              )}
            </section>
          )}
        </div>
      </div>
      </div>
      {selectedTask && (
        <aside
          id="task-details"
          aria-labelledby="task-details-heading"
          className={cn("flex min-h-0 min-w-0 shrink-0 flex-col border-l border-border/60 bg-zerus-surface motion-safe:animate-in motion-safe:slide-in-from-right-4 motion-safe:duration-200", isNarrow ? "w-full" : "w-[340px] xl:w-[380px]")}
        >
          <header className="flex shrink-0 items-center justify-between border-b border-border/60 px-5 py-3">
            <h3 id="task-details-heading" className="text-sm font-medium">Task details</h3>
            <Button ref={closeButtonRef} variant="ghost" size="icon" className="h-8 w-8" aria-label="Close task details" title="Close task details (Esc)" onClick={closeDetails}>
              <X size={16} />
            </Button>
          </header>
          <TaskDetails
            key={selectedTask.id}
            task={selectedTask}
            lists={lists}
            generalListName={generalListName}
            notes={linkableNotes}
            typeIcons={typeIcons}
            onUpdate={(patch) => {
              updateTask(selectedTask.id, patch);
              if ("listId" in patch && patch.listId !== activeListId) onSelectedTaskChange(null);
            }}
            onRequestDelete={() => setTaskToDelete(selectedTask)}
            onOpenNote={onOpenNote}
          />
        </aside>
      )}
      <Dialog open={listDialogOpen} onOpenChange={setListDialogOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>{listToRename ? "Rename list" : "Create a list"}</DialogTitle>
            <DialogDescription>{listToRename ? "Choose a new name for this task list." : "Keep a separate set of tasks for a project or part of your day."}</DialogDescription>
          </DialogHeader>
          <form className="space-y-4" onSubmit={(event) => {
            event.preventDefault();
            if (listToRename) {
              if (!onRenameList(listToRename.id, listName)) {
                setListError("Choose a unique list name. The list must still exist.");
                return;
              }
              setListDialogOpen(false);
              return;
            }
            const list = onCreateList(listName);
            if (!list) { setListError("Choose a unique list name."); return; }
            setSelectedListId(list.id);
            onSelectedTaskChange(null);
            setView("all");
            setDraft("");
            setListDialogOpen(false);
          }}>
            <label className="block text-sm">
              List name
              <Input className="mt-2" autoFocus value={listName} onChange={(event) => { setListName(event.target.value); setListError(""); }} placeholder="e.g. Work or Personal" maxLength={100} />
            </label>
            {listError && <p role="alert" className="text-sm text-destructive">{listError}</p>}
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setListDialogOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={!listName.trim()}>{listToRename ? "Save changes" : "Create list"}</Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
      <AlertDialog open={listToDelete !== null} onOpenChange={(open) => { if (!open) setListToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete “{listToDelete?.name}”?</AlertDialogTitle>
            <AlertDialogDescription>
              This permanently deletes the list. Its tasks, including completed tasks, will move to “{generalListName}”.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => {
                if (!listToDelete) return;
                onDeleteList(listToDelete.id);
                if (selectedListId === listToDelete.id) {
                  setSelectedListId(null);
                  onSelectedTaskChange(null);
                  setDraft("");
                }
                setListToDelete(null);
              }}
            >
              Delete list
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog
        open={taskToDelete !== null}
        onOpenChange={(open) => { if (!open) setTaskToDelete(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete “{taskToDelete?.title || "Untitled task"}”?</AlertDialogTitle>
            <AlertDialogDescription>
              This permanently deletes the task
              {taskToDelete?.linkedNoteIds.length
                ? ` and removes its relation from ${taskToDelete.linkedNoteIds.length} linked ${taskToDelete.linkedNoteIds.length === 1 ? "note" : "notes"}`
                : ""}.
              {" "}This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => {
                if (!taskToDelete) return;
                onDeleteTask(taskToDelete.id);
                if (selectedTaskId === taskToDelete.id) onSelectedTaskChange(null);
                setTaskToDelete(null);
              }}
            >
              Delete task
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </main>
  );
}
