import { useEffect, useMemo, useState } from "react";
import {
  Calendar,
  CheckSquare,
  ArrowUpDown,
  Link2,
  Search,
  SlidersHorizontal,
  X,
} from "@/lib/icons";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { ListValueEditor } from "@/components/notes/PropertiesSection";
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
import { tasksForView, type Task, type TaskPatch, type TaskSort, type TaskView } from "@/lib/tasks";

interface TasksWorkspaceProps {
  tasks: Task[];
  categoryOptions: string[];
  notes: Note[];
  selectedTaskId: string | null;
  onSelectedTaskChange: (id: string | null) => void;
  onCreateTask: (title: string) => Task | null;
  onUpdateTask: (id: string, patch: TaskPatch) => void;
  onCategoryOptionsChange: (options: string[]) => void;
  onDeleteCategory: (category: string) => void;
  onOpenNote: (id: string) => void;
  initialView?: TaskView;
}

const views: { value: TaskView; label: string }[] = [
  { value: "all", label: "All Tasks" },
  { value: "today", label: "Today" },
  { value: "completed", label: "Completed" },
];

const sorts: { value: TaskSort; label: string }[] = [
  { value: "recently-completed", label: "Most recently completed" },
  { value: "recently-created", label: "Most recently created" },
  { value: "title-asc", label: "Title A–Z" },
  { value: "title-desc", label: "Title Z–A" },
];

const ALL_TYPES = "__all_types__";
const UNTYPED = "__untyped__";

function noteTypeLabel(note: Note): string {
  return typeKey(noteTypePath(note)) || "No type";
}

function LinkNoteDialog({
  open,
  onOpenChange,
  notes,
  linkedNoteIds,
  onLink,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  notes: Note[];
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
                      <Link2 size={15} />
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
  notes,
  categoryOptions,
  onUpdate,
  onCategoryOptionsChange,
  onDeleteCategory,
  onOpenNote,
}: {
  task: Task;
  notes: Note[];
  categoryOptions: string[];
  onUpdate: (patch: TaskPatch) => void;
  onCategoryOptionsChange: (options: string[]) => void;
  onDeleteCategory: (category: string) => void;
  onOpenNote: (id: string) => void;
}) {
  const [linkDialogOpen, setLinkDialogOpen] = useState(false);
  const linkedNotes = task.linkedNoteIds
    .map((id) => notes.find((note) => note.id === id))
    .filter((note): note is Note => Boolean(note));

  return (
    <div className="border-t border-border/60 px-3 pb-3 pt-3" onClick={(event) => event.stopPropagation()}>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <label className="block text-xs text-muted-foreground md:col-span-2 xl:col-span-2">
          Title
          <Input
            className="mt-1 h-8"
            value={task.title}
            onChange={(event) => onUpdate({ title: event.target.value })}
          />
        </label>
        <div className="block text-xs text-muted-foreground">
          <span>Category</span>
          <div className="mt-1 min-h-8 rounded-md border border-input bg-background px-1 py-0.5 text-foreground">
            <ListValueEditor
              def={{ name: "Category", type: "list", listOptions: categoryOptions, listMultiple: false }}
              value={task.category ?? undefined}
              onCommit={(value) => onUpdate({ category: typeof value === "string" ? value : null })}
              onCreateOption={(option) => onCategoryOptionsChange([...categoryOptions, option])}
              onDeleteOption={onDeleteCategory}
              emptyPickerLabel="Create category"
              selectedPickerLabel="Change"
              searchPlaceholder="Search or create category…"
            />
          </div>
        </div>
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
          <Input
            className="mt-1 h-8"
            type="date"
            value={task.date}
            onChange={(event) => onUpdate({ date: event.target.value })}
          />
        </label>
        <label className="block text-xs text-muted-foreground">
          Due date
          <Input
            className="mt-1 h-8"
            type="date"
            value={task.dueDate ?? ""}
            onChange={(event) => onUpdate({ dueDate: event.target.value || null })}
          />
        </label>
        <div className="md:col-span-2">
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
                  <Link2 size={13} className="shrink-0" />
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
        <p className="mt-2 text-[11px] text-muted-foreground">
          Completed {new Date(task.completedAt).toLocaleString()}
        </p>
      )}
      <LinkNoteDialog
        open={linkDialogOpen}
        onOpenChange={setLinkDialogOpen}
        notes={notes}
        linkedNoteIds={task.linkedNoteIds}
        onLink={(noteId) => onUpdate({ linkedNoteIds: [...task.linkedNoteIds, noteId] })}
      />
    </div>
  );
}

export function TasksWorkspace({
  tasks,
  categoryOptions,
  notes,
  selectedTaskId,
  onSelectedTaskChange,
  onCreateTask,
  onUpdateTask,
  onCategoryOptionsChange,
  onDeleteCategory,
  onOpenNote,
  initialView = "all",
}: TasksWorkspaceProps) {
  const [view, setView] = useState<TaskView>(initialView);
  const [sort, setSort] = useState<TaskSort>("recently-created");
  const [draft, setDraft] = useState("");
  const [categoryToDelete, setCategoryToDelete] = useState<string | null>(null);
  const visibleTasks = useMemo(() => tasksForView(tasks, view, undefined, sort), [tasks, view, sort]);
  const linkableNotes = useMemo(
    () => notes.filter((note) => !isExternalNote(note) && !isTrashed(note)),
    [notes],
  );
  const allTaskGroups = useMemo(() => [
    { label: "To Do", tasks: visibleTasks.filter((task) => !task.completed) },
    { label: "Completed", tasks: visibleTasks.filter((task) => task.completed) },
  ], [visibleTasks]);
  const deleteCategoryUseCount = categoryToDelete
    ? tasks.filter((task) => task.category?.toLowerCase() === categoryToDelete.toLowerCase()).length
    : 0;
  const requestCategoryDelete = (category: string) => {
    const useCount = tasks.filter(
      (task) => task.category?.toLowerCase() === category.toLowerCase(),
    ).length;
    if (useCount === 0) {
      onDeleteCategory(category);
      return;
    }
    setCategoryToDelete(category);
  };
  const submit = () => {
    const created = onCreateTask(draft);
    if (!created) return;
    setDraft("");
  };

  const renderTask = (task: Task) => {
    const isExpanded = selectedTaskId === task.id;
    return (
      <div
        key={task.id}
        className={cn(
          "group overflow-hidden rounded-lg border bg-background/80 transition-colors",
          isExpanded ? "border-border shadow-sm" : "border-transparent hover:border-border/60 hover:bg-background",
        )}
      >
        <div
          className="flex cursor-pointer items-center gap-3 px-3 py-2.5"
          onClick={() => onSelectedTaskChange(isExpanded ? null : task.id)}
        >
          <span
            className="flex h-4 w-4 shrink-0 items-center justify-center"
            onClick={(event) => event.stopPropagation()}
          >
            <Checkbox
              checked={task.completed}
              onCheckedChange={(checked) => onUpdateTask(task.id, { completed: checked === true })}
              aria-label={task.completed ? `Mark ${task.title} active` : `Complete ${task.title}`}
            />
          </span>
          <span className={cn("min-w-0 flex-1 truncate text-sm", task.completed && "text-muted-foreground line-through")}>
            {task.title || "Untitled task"}
          </span>
          {task.category && (
            <span className="rounded bg-muted px-1.5 py-0.5 text-[11px] text-muted-foreground">{task.category}</span>
          )}
          {task.priority !== "none" && (
            <span className={cn("text-[11px] capitalize", task.priority === "high" ? "text-destructive" : "text-muted-foreground")}>
              {task.priority}
            </span>
          )}
          <span className="flex items-center gap-1 text-[11px] text-muted-foreground">
            <Calendar size={12} />
            {task.date}
          </span>
          {task.linkedNoteIds.length > 0 && (
            <span className="flex items-center gap-1 text-[11px] text-muted-foreground" aria-label={`${task.linkedNoteIds.length} linked notes`}>
              <Link2 size={13} />
              {task.linkedNoteIds.length > 1 && task.linkedNoteIds.length}
            </span>
          )}
          <Button
            variant="ghost"
            size="icon"
            className={cn("h-7 w-7", isExpanded ? "text-foreground" : "opacity-60 group-hover:opacity-100")}
            aria-label={isExpanded ? `Close ${task.title} details` : `Edit ${task.title}`}
            aria-expanded={isExpanded}
            onClick={(event) => {
              event.stopPropagation();
              onSelectedTaskChange(isExpanded ? null : task.id);
            }}
          >
            <SlidersHorizontal size={14} />
          </Button>
        </div>
        {isExpanded && (
          <TaskDetails
            task={task}
            notes={linkableNotes}
            categoryOptions={categoryOptions}
            onUpdate={(patch) => onUpdateTask(task.id, patch)}
            onCategoryOptionsChange={onCategoryOptionsChange}
            onDeleteCategory={requestCategoryDelete}
            onOpenNote={onOpenNote}
          />
        )}
      </div>
    );
  };

  return (
    <main className="flex h-full min-w-0 flex-col bg-zerus-surface">
      <header className="border-b border-border/60 px-6 pb-3 pt-5">
        <div className="flex items-center gap-2">
          <CheckSquare size={19} />
          <h2 className="text-lg font-semibold">Tasks</h2>
        </div>
        <div className="mt-4 flex max-w-2xl gap-2">
          <Input
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => { if (event.key === "Enter") submit(); }}
            placeholder="Add a task…"
            aria-label="New task title"
          />
          <Button onClick={submit} disabled={!draft.trim()}>Add</Button>
        </div>
        <div className="mt-4 flex max-w-3xl items-center justify-between gap-3">
          <div className="flex gap-1" role="tablist">
            {views.map((item) => (
              <button
                key={item.value}
                role="tab"
                aria-selected={view === item.value}
                onClick={() => setView(item.value)}
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
          <Select value={sort} onValueChange={(value) => setSort(value as TaskSort)}>
            <SelectTrigger className="h-8 w-52 text-xs" aria-label="Sort tasks">
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
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-6 py-4">
        <div className="max-w-3xl">
          {view === "all" && visibleTasks.length > 0 ? (
            <div className="space-y-5">
              {allTaskGroups.map((group) => (
                <section key={group.label} aria-labelledby={`tasks-${group.label.toLowerCase().replace(" ", "-")}`}>
                  <h3
                    id={`tasks-${group.label.toLowerCase().replace(" ", "-")}`}
                    className="mb-1.5 px-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                  >
                    {group.label}
                  </h3>
                  <div className="space-y-1.5">
                    {group.tasks.map(renderTask)}
                  </div>
                </section>
              ))}
            </div>
          ) : (
            <div className="space-y-1.5">{visibleTasks.map(renderTask)}</div>
          )}
          {visibleTasks.length === 0 && (
            <p className="py-12 text-center text-sm text-muted-foreground">
              {view === "completed"
                ? "No completed tasks yet."
                : view === "today"
                  ? "Nothing scheduled for today."
                  : "Add your first task above."}
            </p>
          )}
        </div>
      </div>
      <AlertDialog
        open={categoryToDelete !== null}
        onOpenChange={(open) => { if (!open) setCategoryToDelete(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete “{categoryToDelete}” category?</AlertDialogTitle>
            <AlertDialogDescription>
              This category is used by {deleteCategoryUseCount} {deleteCategoryUseCount === 1 ? "task" : "tasks"}.
              Deleting it will remove the category from {deleteCategoryUseCount === 1 ? "that task" : "those tasks"}.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => {
                if (categoryToDelete) onDeleteCategory(categoryToDelete);
                setCategoryToDelete(null);
              }}
            >
              Delete category
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </main>
  );
}
