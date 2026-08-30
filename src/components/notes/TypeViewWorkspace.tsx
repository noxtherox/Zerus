import { Fragment, useEffect, useId, useMemo, useState, type CSSProperties, type ReactNode } from "react";
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  useDraggable,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  arrayMove,
  horizontalListSortingStrategy,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  Calendar,
  CheckCircle2,
  ChevronDown,
  FileText,
  Folder,
  GripVertical,
  LayoutGrid,
  LayoutKanban,
  List,
  Plus,
  Search,
  Sparkles,
  Table2,
} from "@/lib/icons";
import { boardCollisionDetection } from "@/lib/board-dnd";
import { Button } from "@/components/ui/button";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { NoteListFilters } from "@/components/notes/NoteListFilters";
import { PropertyPills } from "@/components/notes/PropertyPills";
import { filterNotes, type NoteFilter } from "@/lib/filters";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import {
  effectiveProperties,
  type PropertyDef,
  type PropertySchemas,
} from "@/lib/properties";
import {
  boardColumnOrderKey,
  propertyGroupLabels,
  reconcileBoardColumnOrder,
  type NoteViewMode,
  type TypeViewConfig,
} from "@/lib/note-views";
import {
  firstNoteImage,
  type Note,
  noteSnippet,
  noteTitle,
  typeKey,
} from "@/lib/note-utils";
import { getImageUrl } from "@/store/notes-store";
import { cn } from "@/lib/utils";

const NO_PROPERTY = "__none__";
const NO_VALUE = "__no_value__";

const VIEW_DEFS: Array<{
  mode: NoteViewMode;
  label: string;
  icon: typeof LayoutGrid;
}> = [
  { mode: "gallery", label: "Gallery", icon: LayoutGrid },
  { mode: "board", label: "Kanban", icon: LayoutKanban },
  { mode: "table", label: "Table", icon: Table2 },
  { mode: "calendar", label: "Calendar", icon: Calendar },
  { mode: "list", label: "List", icon: List },
];

function viewDefinition(mode: NoteViewMode) {
  return VIEW_DEFS.find((view) => view.mode === mode) ?? VIEW_DEFS[4];
}

function propertyValue(note: Note, propertyName: string): PropertyValue | undefined {
  const properties = getNoteProperties(note.content);
  const key = Object.keys(properties).find(
    (name) => name.toLowerCase() === propertyName.toLowerCase(),
  );
  return key ? properties[key] : undefined;
}

export function TypeViewSwitcher({
  typeName,
  mode,
  hideSubtypeNotes,
  onChange,
  onHideSubtypeNotesChange,
}: {
  typeName: string;
  mode: NoteViewMode;
  hideSubtypeNotes: boolean;
  onChange: (mode: NoteViewMode) => void;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
}) {
  const current = viewDefinition(mode);
  const CurrentIcon = current.icon;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 gap-2 px-2 text-sm font-medium"
          aria-label="Change view"
        >
          <CurrentIcon size={16} />
          {current.label}
          <ChevronDown size={14} className="text-muted-foreground" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-60 p-1.5">
        <DropdownMenuLabel className="px-2 py-2 text-[11px] uppercase tracking-wider text-muted-foreground">
          View for {typeName}
        </DropdownMenuLabel>
        {VIEW_DEFS.map(({ mode: itemMode, label, icon: Icon }) => (
          <DropdownMenuItem
            key={itemMode}
            className="min-h-10 gap-3 px-2.5"
            onSelect={() => onChange(itemMode)}
          >
            <Icon size={17} className="text-muted-foreground" />
            <span className="flex-1">{label}</span>
            {mode === itemMode && (
              <CheckCircle2 size={16} className="text-zerus-accent" />
            )}
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <div className="flex min-h-10 items-center gap-2 rounded-sm px-2.5 text-sm">
          <Folder size={17} className="text-muted-foreground" />
          <label
            htmlFor="hide-subfolder-notes"
            className="flex-1 cursor-pointer whitespace-nowrap"
          >
            Hide subfolder notes
          </label>
          <Switch
            id="hide-subfolder-notes"
            checked={hideSubtypeNotes}
            onCheckedChange={onHideSubtypeNotesChange}
            aria-label="Hide subfolder notes"
            className="h-5 w-9 [&>span]:h-4 [&>span]:w-4 [&>span]:data-[state=checked]:translate-x-4"
          />
        </div>
        <DropdownMenuSeparator />
        <div className="flex items-center gap-2 px-2.5 py-2 text-xs text-muted-foreground">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          Saved for this type
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function NoteCard({
  note,
  visibleProperties,
  onOpen,
}: {
  note: Note;
  visibleProperties: string[];
  onOpen: (id: string) => void;
}) {
  const image = useMemo(() => firstNoteImage(note.content), [note.content]);
  const [imageUrl, setImageUrl] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setImageUrl(null);
    if (image) {
      void getImageUrl(image.path).then((url) => {
        if (active) setImageUrl(url);
      });
    }
    return () => {
      active = false;
    };
  }, [image]);

  return (
    <button
      type="button"
      className="block w-full cursor-pointer rounded-lg border border-border/70 bg-zerus-surface p-3.5 text-left shadow-sm transition-colors hover:bg-zerus-text/[0.025] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      onClick={() => onOpen(note.id)}
    >
      <span className="block">
        <span className="flex items-start gap-2">
          <FileText size={15} className="mt-0.5 shrink-0 text-muted-foreground" />
          <strong className="line-clamp-2 text-sm font-semibold">
            {noteTitle(note)}
          </strong>
        </span>
        {imageUrl && (
          <span className="mt-3 block h-40 overflow-hidden rounded-md bg-muted">
            <img
              src={imageUrl}
              alt={image?.alt ?? ""}
              className="h-full w-full object-cover"
            />
          </span>
        )}
        {noteSnippet(note) && (
          <span className="mt-2.5 line-clamp-3 block text-xs leading-5 text-muted-foreground">
            {noteSnippet(note)}
          </span>
        )}
      </span>
      <PropertyPills note={note} visibleProperties={visibleProperties} className="mt-3" />
    </button>
  );
}

function GalleryView({
  notes,
  groupBy,
  visibleProperties,
  onOpen,
}: {
  notes: Note[];
  groupBy: string | null;
  visibleProperties: string[];
  onOpen: (id: string) => void;
}) {
  const galleryId = useId();
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(
    () => new Set(),
  );
  const groups = useMemo(() => {
    const grouped = new Map<string, Note[]>();
    for (const note of notes) {
      const labels = groupBy
        ? propertyGroupLabels(propertyValue(note, groupBy))
        : ["All notes"];
      for (const label of labels) {
        grouped.set(label, [...(grouped.get(label) ?? []), note]);
      }
    }
    return [...grouped];
  }, [groupBy, notes]);

  useEffect(() => {
    setCollapsedGroups(new Set());
  }, [groupBy]);

  const toggleGroup = (label: string) => {
    setCollapsedGroups((current) => {
      const next = new Set(current);
      if (next.has(label)) next.delete(label);
      else next.add(label);
      return next;
    });
  };

  if (!notes.length) return <EmptyView message="No notes match this view." />;
  return (
    <div className="space-y-8 p-6">
      {groups.map(([label, groupNotes], index) => {
        const collapsed = collapsedGroups.has(label);
        const contentId = `${galleryId}-group-${index}`;
        return (
          <section key={label}>
            {(groupBy || groups.length > 1) && (
              <button
                type="button"
                className="mb-3 flex items-center gap-2 rounded-sm text-sm font-semibold hover:text-foreground/80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                aria-expanded={!collapsed}
                aria-controls={contentId}
                onClick={() => toggleGroup(label)}
              >
                <ChevronDown
                  size={15}
                  className={cn("transition-transform", collapsed && "-rotate-90")}
                />
                {label}
                <span className="text-xs font-normal text-muted-foreground">
                  {groupNotes.length}
                </span>
              </button>
            )}
            {!collapsed && (
              <div
                id={contentId}
                className="grid grid-cols-[repeat(auto-fill,minmax(260px,1fr))] gap-3"
              >
                {groupNotes.map((note) => (
                  <NoteCard key={note.id} note={note} visibleProperties={visibleProperties} onOpen={onOpen} />
                ))}
              </div>
            )}
          </section>
        );
      })}
    </div>
  );
}

function DraggableBoardCard({ note, visibleProperties, onOpen }: { note: Note; visibleProperties: string[]; onOpen: (id: string) => void }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: note.id,
    data: { type: "card" },
  });
  const style: CSSProperties = { transform: CSS.Translate.toString(transform) };
  return (
    <button
      type="button"
      ref={setNodeRef}
      style={style}
      className={cn(
        "block w-full cursor-pointer rounded-md border bg-background p-3 text-left shadow-sm transition-colors hover:bg-zerus-text/[0.025] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        isDragging && "z-50 opacity-70",
      )}
      {...listeners}
      {...attributes}
      onClick={(event) => {
        if (!event.defaultPrevented && !isDragging) onOpen(note.id);
      }}
      onKeyDown={(event) => {
        if (event.key === "Enter") {
          event.preventDefault();
          onOpen(note.id);
          return;
        }
        listeners?.onKeyDown?.(event);
      }}
    >
      <span className="block text-sm font-medium">{noteTitle(note)}</span>
      {noteSnippet(note) && (
        <span className="mt-1.5 line-clamp-2 block text-xs leading-4 text-muted-foreground">
          {noteSnippet(note)}
        </span>
      )}
      <PropertyPills note={note} visibleProperties={visibleProperties} className="mt-2" />
    </button>
  );
}

function BoardColumn({
  value,
  notes,
  visibleProperties,
  onOpen,
  onMoveLeft,
  onMoveRight,
}: {
  value: string;
  notes: Note[];
  visibleProperties: string[];
  onOpen: (id: string) => void;
  onMoveLeft: (() => void) | null;
  onMoveRight: (() => void) | null;
}) {
  const id = `board-column:${value}`;
  const {
    attributes,
    isDragging,
    isOver,
    listeners,
    setActivatorNodeRef,
    setNodeRef,
    transform,
    transition,
  } = useSortable({ id, data: { type: "column", value } });
  const style: CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
  };
  const label = value === NO_VALUE ? "No value" : value;
  return (
    <section
      ref={setNodeRef}
      style={style}
      className={cn("group/board-column w-64 shrink-0", isDragging && "z-40 opacity-70")}
    >
      <header className="mb-2 flex h-7 items-center gap-1 px-1 text-xs font-medium">
        <button
          ref={setActivatorNodeRef}
          type="button"
          aria-label={`Reorder ${label} column`}
          title={`Drag to reorder ${label}`}
          className="flex h-6 w-5 touch-none cursor-grab items-center justify-center rounded text-muted-foreground/50 hover:bg-muted hover:text-muted-foreground active:cursor-grabbing focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          {...attributes}
          {...listeners}
        >
          <GripVertical size={13} aria-hidden="true" />
        </button>
        <span className="h-2 w-2 rounded-full bg-zerus-accent/80" />
        <span className="min-w-0 flex-1 truncate">{label}</span>
        <span className="text-muted-foreground">{notes.length}</span>
        <div className="flex opacity-0 transition-opacity group-hover/board-column:opacity-100 focus-within:opacity-100">
          <button
            type="button"
            aria-label={`Move ${label} column left`}
            title="Move column left"
            disabled={!onMoveLeft}
            onClick={() => onMoveLeft?.()}
            className="h-6 w-5 rounded text-muted-foreground hover:bg-muted hover:text-foreground disabled:pointer-events-none disabled:opacity-25"
          >
            ‹
          </button>
          <button
            type="button"
            aria-label={`Move ${label} column right`}
            title="Move column right"
            disabled={!onMoveRight}
            onClick={() => onMoveRight?.()}
            className="h-6 w-5 rounded text-muted-foreground hover:bg-muted hover:text-foreground disabled:pointer-events-none disabled:opacity-25"
          >
            ›
          </button>
        </div>
      </header>
      <div
        className={cn(
          "min-h-28 space-y-2 rounded-lg border border-border/50 bg-zerus-surface/60 p-2",
          isOver && "border-zerus-accent/60 bg-zerus-accent/5",
        )}
      >
        {notes.map((note) => (
          <DraggableBoardCard key={note.id} note={note} visibleProperties={visibleProperties} onOpen={onOpen} />
        ))}
      </div>
    </section>
  );
}

function BoardView({
  notes,
  property,
  propertyDef,
  visibleProperties,
  columnOrder,
  onOpen,
  onColumnOrderChange,
  onSetProperty,
}: {
  notes: Note[];
  property: string | null;
  propertyDef: PropertyDef | undefined;
  visibleProperties: string[];
  columnOrder: string[] | undefined;
  onOpen: (id: string) => void;
  onColumnOrderChange: (order: string[]) => void;
  onSetProperty: (id: string, name: string, value: PropertyValue | null) => void;
}) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const columns = useMemo(() => {
    if (!property) return [];
    const values = new Set<string>(propertyDef?.listOptions ?? []);
    for (const note of notes) {
      const value = propertyValue(note, property);
      if (Array.isArray(value)) value.forEach((item) => values.add(item));
      else if (value !== undefined && value !== "") values.add(String(value));
    }
    return reconcileBoardColumnOrder([NO_VALUE, ...values], columnOrder);
  }, [columnOrder, notes, property, propertyDef]);

  if (!property) {
    return <EmptyView message="Choose a property above to create Kanban columns." />;
  }

  const handleDragEnd = ({ active, over }: DragEndEvent) => {
    if (!over) return;
    if (active.data.current?.type === "column") {
      const oldIndex = columns.findIndex((column) => `board-column:${column}` === active.id);
      const newIndex = columns.findIndex((column) => `board-column:${column}` === over.id);
      if (oldIndex >= 0 && newIndex >= 0 && oldIndex !== newIndex) {
        onColumnOrderChange(arrayMove(columns, oldIndex, newIndex));
      }
      return;
    }
    if (active.data.current?.type !== "card" || over.data.current?.type !== "column") return;
    const value = String(over.data.current.value);
    onSetProperty(
      String(active.id),
      property,
      value === NO_VALUE ? null : propertyDef?.listMultiple ? [value] : value,
    );
  };

  const moveColumn = (index: number, offset: -1 | 1) => {
    const target = index + offset;
    if (target < 0 || target >= columns.length) return;
    onColumnOrderChange(arrayMove(columns, index, target));
  };

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={boardCollisionDetection}
      onDragEnd={handleDragEnd}
    >
      <div className="flex min-w-max items-start gap-3 p-6">
        <SortableContext
          items={columns.map((column) => `board-column:${column}`)}
          strategy={horizontalListSortingStrategy}
        >
          {columns.map((column, index) => (
            <BoardColumn
              key={column}
              value={column}
              notes={notes.filter((note) => {
                const value = propertyValue(note, property);
                if (column === NO_VALUE) return value === undefined || value === "";
                return Array.isArray(value)
                  ? value.includes(column)
                  : String(value) === column;
              })}
              visibleProperties={visibleProperties}
              onOpen={onOpen}
              onMoveLeft={index > 0 ? () => moveColumn(index, -1) : null}
              onMoveRight={index < columns.length - 1 ? () => moveColumn(index, 1) : null}
            />
          ))}
        </SortableContext>
      </div>
    </DndContext>
  );
}

function PropertyEditor({
  note,
  def,
  onSetProperty,
}: {
  note: Note;
  def: PropertyDef;
  onSetProperty: (id: string, name: string, value: PropertyValue | null) => void;
}) {
  const value = propertyValue(note, def.name);
  if (def.type === "checkbox") {
    return (
      <input
        type="checkbox"
        checked={value === true}
        onChange={(event) => onSetProperty(note.id, def.name, event.target.checked)}
        aria-label={`${def.name} for ${noteTitle(note)}`}
      />
    );
  }
  if (def.type === "list" && !def.listMultiple) {
    return (
      <select
        className="h-8 w-full rounded border border-transparent bg-transparent px-1 text-xs hover:border-border focus:border-border"
        value={typeof value === "string" ? value : ""}
        onChange={(event) => onSetProperty(note.id, def.name, event.target.value || null)}
      >
        <option value="">No value</option>
        {(def.listOptions ?? []).map((option) => (
          <option key={option}>{option}</option>
        ))}
      </select>
    );
  }
  return (
    <Input
      type={def.type === "date" ? "date" : def.type === "number" ? "number" : "text"}
      value={Array.isArray(value) ? value.join(", ") : value === undefined ? "" : String(value)}
      className="h-8 border-transparent bg-transparent px-1 text-xs hover:border-border focus:border-border"
      onChange={(event) => {
        const raw = event.target.value;
        onSetProperty(
          note.id,
          def.name,
          raw === "" ? null : def.type === "number" ? Number(raw) : raw,
        );
      }}
    />
  );
}

function TableView({
  notes,
  properties,
  onOpen,
  onSetProperty,
}: {
  notes: Note[];
  properties: PropertyDef[];
  onOpen: (id: string) => void;
  onSetProperty: (id: string, name: string, value: PropertyValue | null) => void;
}) {
  return (
    <div className="p-6">
      <div className="overflow-auto rounded-lg border border-border/70">
        <table className="w-full min-w-[720px] border-collapse text-left text-xs">
          <thead className="bg-zerus-surface text-muted-foreground">
            <tr>
              <th className="min-w-64 border-b border-r border-border/70 px-3 py-2 font-medium">Name</th>
              {properties.map((property) => (
                <th key={property.name} className="min-w-36 border-b border-r border-border/70 px-3 py-2 font-medium last:border-r-0">
                  {property.name}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {notes.map((note) => (
              <tr
                key={note.id}
                className="cursor-pointer hover:bg-zerus-text/[0.02]"
                onClick={(event) => {
                  if (!(event.target as HTMLElement).closest("input, select, textarea, button, a")) {
                    onOpen(note.id);
                  }
                }}
              >
                <td className="border-b border-r border-border/50 px-3 py-2 last:border-b-0">
                  <button className="flex items-center gap-2 font-medium hover:underline" onClick={() => onOpen(note.id)}>
                    <FileText size={14} className="text-muted-foreground" />
                    {noteTitle(note)}
                  </button>
                </td>
                {properties.map((property) => (
                  <td key={property.name} className="border-b border-r border-border/50 px-2 py-1 last:border-r-0">
                    <PropertyEditor note={note} def={property} onSetProperty={onSetProperty} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function CalendarView({
  notes,
  dateProperty,
  visibleProperties,
  onOpen,
}: {
  notes: Note[];
  dateProperty: string | null;
  visibleProperties: string[];
  onOpen: (id: string) => void;
}) {
  const today = new Date();
  const year = today.getFullYear();
  const month = today.getMonth();
  const first = new Date(year, month, 1);
  const leading = (first.getDay() + 6) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const cells = Array.from({ length: 42 }, (_, index) => index - leading + 1);
  const dated = new Map<number, Note[]>();
  const undated: Note[] = [];
  for (const note of notes) {
    const raw = dateProperty ? propertyValue(note, dateProperty) : undefined;
    const value = typeof raw === "string" ? /^\d{4}-\d{2}-\d{2}/.exec(raw)?.[0] : undefined;
    if (!value) {
      undated.push(note);
      continue;
    }
    const date = new Date(`${value}T00:00:00`);
    if (date.getFullYear() !== year || date.getMonth() !== month) continue;
    dated.set(date.getDate(), [...(dated.get(date.getDate()) ?? []), note]);
  }

  if (!dateProperty) {
    return <EmptyView message="Choose a date property above to place notes on Calendar." />;
  }

  return (
    <div className="grid min-h-full grid-cols-[minmax(720px,1fr)_230px]">
      <div className="p-6 pr-4">
        <h2 className="mb-4 text-sm font-semibold">
          {today.toLocaleDateString(undefined, { month: "long", year: "numeric" })}
        </h2>
        <div className="grid grid-cols-7 border-l border-t border-border/70">
          {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => (
            <div key={day} className="border-b border-r border-border/70 px-2 py-1.5 text-[10px] font-semibold uppercase text-muted-foreground">
              {day}
            </div>
          ))}
          {cells.map((day, index) => {
            const inMonth = day > 0 && day <= daysInMonth;
            return (
              <div key={index} className="min-h-28 border-b border-r border-border/70 p-1.5">
                {inMonth && (
                  <>
                    <div className="mb-1 text-right text-[10px] text-muted-foreground">{day}</div>
                    {(dated.get(day) ?? []).map((note) => (
                      <button
                        key={note.id}
                        className="mb-1 block w-full truncate rounded border-l-2 border-zerus-accent bg-zerus-accent/10 px-1.5 py-1 text-left text-[10px]"
                        onClick={() => onOpen(note.id)}
                      >
                        <span className="block truncate">{noteTitle(note)}</span>
                        <PropertyPills note={note} visibleProperties={visibleProperties} className="mt-1" />
                      </button>
                    ))}
                  </>
                )}
              </div>
            );
          })}
        </div>
      </div>
      <aside className="border-l border-border/60 bg-zerus-surface p-4">
        <div className="mb-3 flex items-center justify-between text-xs font-semibold">
          Undated <span className="text-muted-foreground">{undated.length}</span>
        </div>
        <div className="space-y-2">
          {undated.map((note) => (
            <button key={note.id} className="w-full rounded-md border bg-background p-2.5 text-left text-xs font-medium" onClick={() => onOpen(note.id)}>
              <span className="block truncate">{noteTitle(note)}</span>
              <PropertyPills note={note} visibleProperties={visibleProperties} className="mt-1.5" />
            </button>
          ))}
        </div>
      </aside>
    </div>
  );
}

function EmptyView({ message }: { message: string }) {
  return (
    <div className="flex h-full min-h-72 items-center justify-center px-6 text-center text-sm text-muted-foreground">
      {message}
    </div>
  );
}

interface TypeViewWorkspaceProps {
  typePath: string[];
  notes: Note[];
  schemas: PropertySchemas;
  config: TypeViewConfig;
  isRefreshing: boolean;
  isDesktop: boolean;
  aiOpen: boolean;
  editorOpen: boolean;
  hideSubtypeNotes: boolean;
  editor: ReactNode;
  onOpenNote: (id: string) => void;
  onCreateNote: () => void;
  onToggleAi: () => void;
  onConfigChange: (patch: Partial<TypeViewConfig>) => void;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
  onSetProperty: (id: string, name: string, value: PropertyValue | null) => void;
}

export function TypeViewWorkspace({
  typePath,
  notes,
  schemas,
  config,
  isRefreshing,
  isDesktop,
  aiOpen,
  editorOpen,
  hideSubtypeNotes,
  editor,
  onOpenNote,
  onCreateNote,
  onToggleAi,
  onConfigChange,
  onHideSubtypeNotesChange,
  onSetProperty,
}: TypeViewWorkspaceProps) {
  const [search, setSearch] = useState("");
  const typeName = typePath.join(" / ");
  const typeParentPath = typePath.slice(0, -1);
  const currentTypeName = typePath.at(-1) ?? "Notes";
  const typeFilter = useMemo<NoteFilter>(
    () => ({
      kind: "type",
      path: typePath,
      includeSubtypes: !hideSubtypeNotes,
    }),
    [hideSubtypeNotes, typePath],
  );
  const filteredNotes = useMemo(
    () => filterNotes(notes, typeFilter, search, config.filters),
    [config.filters, notes, search, typeFilter],
  );
  const filterOptions = useMemo(
    () =>
      filterNotes(notes, typeFilter, "", {
        ...config.filters,
        date: null,
        properties: [],
      }),
    [config.filters, notes, typeFilter],
  );
  const properties = effectiveProperties(typePath, schemas);
  const groupableProperties = properties.filter((property) =>
    config.mode === "gallery"
      ? !(property.type === "list" && property.listMultiple)
      : property.type !== "relation" && !(property.type === "list" && property.listMultiple),
  );
  const dateProperties = properties.filter((property) => property.type === "date");
  const activeGroupProperty = groupableProperties.find(
    (property) => property.name.toLowerCase() === config.groupBy?.toLowerCase(),
  );
  const activeGroupBy = activeGroupProperty?.name ?? null;

  if (editorOpen) {
    return (
      <div className="flex h-full min-w-0 flex-col bg-zerus-editor">
        <div className="min-h-0 flex-1">{editor}</div>
      </div>
    );
  }

  return (
    <div className={cn("flex h-full min-w-0 flex-col bg-zerus-editor", isRefreshing && "pointer-events-none opacity-70")}>
      <header className="shrink-0 border-b border-border/60">
        <div className="flex items-center gap-2 px-4 py-3">
          <Breadcrumb className="mr-auto min-w-0">
            <BreadcrumbList className="flex-nowrap gap-1.5 overflow-hidden text-base sm:gap-1.5">
              {typeParentPath.map((segment, index) => (
                <Fragment key={typePath.slice(0, index + 1).join("/")}>
                  <BreadcrumbItem className="min-w-0">
                    <span className="truncate font-medium text-muted-foreground">
                      {segment}
                    </span>
                  </BreadcrumbItem>
                  <BreadcrumbSeparator className="shrink-0 text-muted-foreground/60" />
                </Fragment>
              ))}
              <BreadcrumbItem className="min-w-0">
                <BreadcrumbPage className="truncate text-lg font-semibold">
                  {currentTypeName}
                </BreadcrumbPage>
              </BreadcrumbItem>
            </BreadcrumbList>
          </Breadcrumb>
          <div className="relative w-52">
            <Search size={14} className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search this view…" className="h-8 bg-zerus-surface pl-8 text-xs" />
          </div>
          <NoteListFilters
            notes={filterOptions}
            showTypes={false}
            showFileTypes={false}
            showArchivedToggle
            filters={config.filters}
            visibleProperties={config.visibleProperties}
            onChange={(filters) => onConfigChange({ filters })}
            onVisiblePropertiesChange={(visibleProperties) => onConfigChange({ visibleProperties })}
          />
          {isDesktop && (
            <Button
              variant="ghost"
              size="sm"
              className={cn(
                "h-8 shrink-0 gap-1.5 px-2.5 text-xs",
                aiOpen && "bg-muted text-zerus-accent",
              )}
              title={aiOpen ? "Hide AI chat" : `Chat with ${currentTypeName}`}
              aria-label={aiOpen ? "Hide AI chat" : `Chat with ${currentTypeName}`}
              aria-pressed={aiOpen}
              onClick={onToggleAi}
            >
              <Sparkles size={15} />
              AI
            </Button>
          )}
          <Button size="sm" className="h-8 gap-1.5" onClick={onCreateNote}>
            <Plus size={15} /> New
          </Button>
        </div>
        <div className="flex min-h-10 items-center gap-3 border-t border-border/40 px-4">
          <TypeViewSwitcher
            typeName={typeName}
            mode={config.mode}
            hideSubtypeNotes={hideSubtypeNotes}
            onChange={(mode) => onConfigChange({ mode })}
            onHideSubtypeNotesChange={onHideSubtypeNotesChange}
          />
          {(config.mode === "gallery" || config.mode === "board") && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              Group by
              <Select value={activeGroupBy ?? NO_PROPERTY} onValueChange={(value) => onConfigChange({ groupBy: value === NO_PROPERTY ? null : value })}>
                <SelectTrigger className="h-7 w-40 border-border/60 bg-zerus-surface px-2 text-xs">
                  <SelectValue placeholder="No grouping" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NO_PROPERTY}>No grouping</SelectItem>
                  {groupableProperties.map((property) => (
                    <SelectItem key={property.name} value={property.name}>{property.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          {config.mode === "calendar" && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              Date property
              <Select value={config.dateProperty ?? NO_PROPERTY} onValueChange={(value) => onConfigChange({ dateProperty: value === NO_PROPERTY ? null : value })}>
                <SelectTrigger className="h-7 w-40 border-border/60 bg-zerus-surface px-2 text-xs">
                  <SelectValue placeholder="Choose property" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NO_PROPERTY}>Choose property</SelectItem>
                  {dateProperties.map((property) => (
                    <SelectItem key={property.name} value={property.name}>{property.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <span className="ml-auto flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" /> Auto-saved
          </span>
        </div>
      </header>
      <main className="min-h-0 flex-1 overflow-auto">
        {config.mode === "gallery" && <GalleryView notes={filteredNotes} groupBy={activeGroupBy} visibleProperties={config.visibleProperties} onOpen={onOpenNote} />}
        {config.mode === "board" && (
          <BoardView
            notes={filteredNotes}
            property={activeGroupBy}
            propertyDef={activeGroupProperty}
            visibleProperties={config.visibleProperties}
            columnOrder={activeGroupBy ? config.boardColumnOrder[boardColumnOrderKey(activeGroupBy)] : undefined}
            onOpen={onOpenNote}
            onColumnOrderChange={(order) => {
              if (!activeGroupBy) return;
              onConfigChange({
                boardColumnOrder: {
                  ...config.boardColumnOrder,
                  [boardColumnOrderKey(activeGroupBy)]: order,
                },
              });
            }}
            onSetProperty={onSetProperty}
          />
        )}
        {config.mode === "table" && <TableView notes={filteredNotes} properties={properties} onOpen={onOpenNote} onSetProperty={onSetProperty} />}
        {config.mode === "calendar" && <CalendarView notes={filteredNotes} dateProperty={config.dateProperty} visibleProperties={config.visibleProperties} onOpen={onOpenNote} />}
      </main>
    </div>
  );
}
