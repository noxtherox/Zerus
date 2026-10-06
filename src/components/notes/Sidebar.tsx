import { GlobalSearchButton } from "@/components/search/GlobalSearch";
import { handleMiddleMouseDown } from "@/lib/middle-click";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  type DragEndEvent,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  ChevronDown,
  ChevronRight,
  ChevronsLeft,
  CheckSquare,
  FileStack,
  Files,
  GripVertical,
  Link2,
  Notebook,
  Plus,
  Settings,
  Trash2,
} from "@/lib/icons";
import { cn } from "@/lib/utils";
import { ZerusLogo } from "@/components/ZerusLogo";
import {
  DEFAULT_TYPE,
  MAX_TYPE_DEPTH,
  type Note,
  type TypeNode,
  buildTypeTree,
  getAllTypePaths,
  isExternalNote,
  isManagedSavedLinkNote,
  isTrashed,
  parseTypePath,
  reorderTypeTree,
  typeKey,
} from "@/lib/note-utils";
import type { NoteFilter } from "@/lib/filters";
import type { TypeIcons } from "@/lib/type-icons";
import {
  createType,
  deleteType,
  renameType,
  setTypeIcon,
} from "@/store/notes-store";
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { buttonVariants } from "@/components/ui/button-variants";
import { Input } from "@/components/ui/input";
import { ThemeSettingsDialog } from "./ThemeSettingsDialog";
import { TypeIcon } from "./TypeIcon";
import { TypeContextMenu } from "./TypeContextMenu";
import { CollapsedSidebar } from "./CollapsedSidebar";
import { IconPickerDialog } from "./IconPickerDialog";
import { TypeCreationDialog } from "./TypeCreationDialog";
import { getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";
import { VaultSwitcherDialog } from "./VaultSwitcherDialog";
import { vaultNameFromPath } from "@/lib/vault-registry";
import {
  TYPE_TREE_PAGE_SIZE,
  visibleTypeNodes,
} from "@/lib/type-tree-pagination";

interface SidebarProps {
  notes: Note[];
  taskCount: number;
  trashedImageCount: number;
  /** Types that exist without notes (empty folders) — still shown in the tree. */
  extraTypes: string[][];
  /** Custom icon per type key — types without one get the folder glyph. */
  typeIcons: TypeIcons;
  /** Full type keys in the user's preferred order. */
  typeOrder: string[];
  keptOpenTypes: string[];
  onKeptOpenTypesChange: (keys: string[]) => void;
  filter: NoteFilter;
  isDesktop: boolean;
  vaultLocation: string | null;
  defaultNoteType: string[];
  hideSubtypeNotes: boolean;
  onDefaultNoteTypeChange: (typePath: string[]) => void;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
  onTypeOrderChange: (order: string[]) => void;
  onOpenFilterInNewTab: (filter: NoteFilter) => void;
  onFilterChange: (filter: NoteFilter) => void;
  onOpenTypeInNewTab: (typePath: string[]) => void;
  onCollapse: () => void;
  collapsed?: boolean;
  onRestore?: () => void;
}

function flattenTypeKeys(nodes: TypeNode[]): string[] {
  return nodes.flatMap((node) => [
    typeKey(node.path),
    ...flattenTypeKeys(node.children),
  ]);
}

function SidebarRow({
  active,
  onClick,
  onOpenInNewTab,
  icon,
  label,
  count,
  depth = 0,
  chevron,
  onToggle,
  toggleLocked = false,
  toggleTitle,
}: {
  active: boolean;
  onClick: () => void;
  onOpenInNewTab?: () => void;
  icon: React.ReactNode;
  label: string;
  count?: number;
  depth?: number;
  chevron?: "open" | "closed" | "leaf";
  onToggle?: () => void;
  toggleLocked?: boolean;
  toggleTitle?: string;
}) {
  return (
    <div
      className={cn(
        "flex w-full items-center rounded-md text-sm transition-colors",
        active
          ? "bg-zerus-sidebar-fg/15 text-zerus-sidebar-fg"
          : "text-zerus-sidebar-fg/70 hover:bg-zerus-sidebar-fg/5 hover:text-zerus-sidebar-fg/90",
      )}
      style={{ paddingLeft: `${depth * 14}px` }}
    >
      <button
        onClick={onClick}
        onMouseDown={(event) => {
          if (onOpenInNewTab) handleMiddleMouseDown(event, onOpenInNewTab);
        }}
        className="flex min-w-0 flex-1 items-center gap-2 px-2 py-1.5 text-left"
      >
        <span className="shrink-0 opacity-80">{icon}</span>
        <span className="flex-1 truncate">{label}</span>
        {count !== undefined && (
          <span className="text-xs tabular-nums text-zerus-sidebar-fg/50">
            {count}
          </span>
        )}
      </button>
      {chevron !== undefined && chevron !== "leaf" && (
        <button
          type="button"
          aria-label={toggleLocked ? `${label} is kept open` : `${chevron === "open" ? "Collapse" : "Expand"} ${label}`}
          aria-expanded={chevron === "open"}
          aria-disabled={toggleLocked}
          title={toggleTitle ?? `${chevron === "open" ? "Collapse" : "Expand"} ${label}`}
          onClick={(event) => {
            event.stopPropagation();
            if (!toggleLocked) onToggle?.();
          }}
          className="flex h-6 w-5 shrink-0 items-center justify-center text-zerus-sidebar-fg/50 hover:text-zerus-sidebar-fg/90"
          tabIndex={-1}
        >
          {chevron === "open" ? (
            <ChevronDown size={13} />
          ) : (
            <ChevronRight size={13} />
          )}
        </button>
      )}
    </div>
  );
}

function TypeTreeRows({
  nodes,
  depth,
  parentKey,
  filter,
  expanded,
  keptOpenTypes,
  keptOpenBranches,
  visibleCounts,
  typeIcons,
  onFilterChange,
  onOpenTypeInNewTab,
  onToggle,
  onKeepOpenChange,
  onRenameType,
  onAddSubtype,
  onDeleteType,
  onChangeIcon,
  onReorder,
  scrollContainerRef,
  onLoadMore,
}: {
  nodes: TypeNode[];
  depth: number;
  parentKey: string;
  filter: NoteFilter;
  expanded: Set<string>;
  keptOpenTypes: ReadonlySet<string>;
  keptOpenBranches: ReadonlySet<string>;
  visibleCounts: Readonly<Record<string, number>>;
  typeIcons: TypeIcons;
  onFilterChange: (filter: NoteFilter) => void;
  onOpenTypeInNewTab: (typePath: string[]) => void;
  onToggle: (key: string) => void;
  onKeepOpenChange: (path: string[], keptOpen: boolean) => void;
  onRenameType: (node: TypeNode) => void;
  onAddSubtype: (node: TypeNode) => void;
  onDeleteType: (node: TypeNode) => void;
  onChangeIcon: (node: TypeNode) => void;
  onReorder: (
    sourceKey: string,
    targetKey: string,
    placement: "before" | "after",
  ) => void;
  scrollContainerRef: { readonly current: HTMLElement | null };
  onLoadMore: (parentKey: string) => void;
}) {
  const visibleNodes = visibleTypeNodes(nodes, visibleCounts[parentKey]);
  const remainingCount = nodes.length - visibleNodes.length;

  return (
    <>
      <SortableContext
        items={visibleNodes.map((node) => typeKey(node.path))}
        strategy={verticalListSortingStrategy}
      >
        {visibleNodes.map((node, index) => {
          const key = typeKey(node.path);
          const isOpen = expanded.has(key);
          return (
            <div key={key}>
              <SortableTypeRow
                node={node}
                depth={depth}
                active={filter.kind === "type" && typeKey(filter.path) === key}
                isOpen={isOpen}
                keptOpen={keptOpenTypes.has(key)}
                toggleLocked={keptOpenBranches.has(key)}
                typeIcon={typeIcons[key]}
                canMoveUp={index > 0}
                canMoveDown={index < nodes.length - 1}
                onFilterChange={onFilterChange}
                onOpenTypeInNewTab={onOpenTypeInNewTab}
                onToggle={onToggle}
                onKeepOpenChange={onKeepOpenChange}
                onRenameType={onRenameType}
                onAddSubtype={onAddSubtype}
                onDeleteType={onDeleteType}
                onChangeIcon={onChangeIcon}
                onMoveUp={() =>
                  onReorder(key, typeKey(nodes[index - 1].path), "before")
                }
                onMoveDown={() =>
                  onReorder(key, typeKey(nodes[index + 1].path), "after")
                }
              />
              {isOpen && node.children.length > 0 && (
                <TypeTreeRows
                  nodes={node.children}
                  depth={depth + 1}
                  parentKey={key}
                  filter={filter}
                  expanded={expanded}
                  keptOpenTypes={keptOpenTypes}
                  keptOpenBranches={keptOpenBranches}
                  visibleCounts={visibleCounts}
                  typeIcons={typeIcons}
                  onFilterChange={onFilterChange}
                  onOpenTypeInNewTab={onOpenTypeInNewTab}
                  onToggle={onToggle}
                  onKeepOpenChange={onKeepOpenChange}
                  onRenameType={onRenameType}
                  onAddSubtype={onAddSubtype}
                  onDeleteType={onDeleteType}
                  onChangeIcon={onChangeIcon}
                  onReorder={onReorder}
                  scrollContainerRef={scrollContainerRef}
                  onLoadMore={onLoadMore}
                />
              )}
            </div>
          );
        })}
      </SortableContext>
      {remainingCount > 0 && (
        <TypeTreeLoadMore
          parentKey={parentKey}
          depth={depth}
          remainingCount={remainingCount}
          scrollContainerRef={scrollContainerRef}
          onLoadMore={onLoadMore}
        />
      )}
    </>
  );
}

function TypeTreeLoadMore({
  parentKey,
  depth,
  remainingCount,
  scrollContainerRef,
  onLoadMore,
}: {
  parentKey: string;
  depth: number;
  remainingCount: number;
  scrollContainerRef: { readonly current: HTMLElement | null };
  onLoadMore: (parentKey: string) => void;
}) {
  const sentinelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const root = scrollContainerRef.current;
    const target = sentinelRef.current;
    if (!root || !target) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) onLoadMore(parentKey);
      },
      { root, rootMargin: "0px 0px 120px 0px" },
    );

    observer.observe(target);
    return () => observer.disconnect();
  }, [onLoadMore, parentKey, scrollContainerRef]);

  return (
    <div
      ref={sentinelRef}
      aria-label={`${remainingCount} more types load automatically while scrolling`}
      className="flex h-8 items-center text-xs text-zerus-sidebar-fg/40"
      style={{ paddingLeft: `${depth * 14 + 32}px` }}
    >
      Loading more…
    </div>
  );
}

function SortableTypeRow({
  node,
  depth,
  active,
  isOpen,
  keptOpen,
  toggleLocked,
  typeIcon,
  canMoveUp,
  canMoveDown,
  onFilterChange,
  onOpenTypeInNewTab,
  onToggle,
  onKeepOpenChange,
  onRenameType,
  onAddSubtype,
  onDeleteType,
  onChangeIcon,
  onMoveUp,
  onMoveDown,
}: {
  node: TypeNode;
  depth: number;
  active: boolean;
  isOpen: boolean;
  keptOpen: boolean;
  toggleLocked: boolean;
  typeIcon: TypeIcons[string];
  canMoveUp: boolean;
  canMoveDown: boolean;
  onFilterChange: (filter: NoteFilter) => void;
  onOpenTypeInNewTab: (typePath: string[]) => void;
  onToggle: (key: string) => void;
  onKeepOpenChange: (path: string[], keptOpen: boolean) => void;
  onRenameType: (node: TypeNode) => void;
  onAddSubtype: (node: TypeNode) => void;
  onDeleteType: (node: TypeNode) => void;
  onChangeIcon: (node: TypeNode) => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
}) {
  const key = typeKey(node.path);
  const {
    attributes,
    listeners,
    setActivatorNodeRef,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: key });

  return (
    <div
      ref={setNodeRef}
      className={cn("relative group/type", isDragging && "z-20 opacity-70")}
      style={{ transform: CSS.Transform.toString(transform), transition }}
    >
      <TypeContextMenu
        node={node}
        canMoveUp={canMoveUp}
        canMoveDown={canMoveDown}
        keptOpen={keptOpen}
        onKeepOpenChange={(checked) => onKeepOpenChange(node.path, checked)}
        onOpenTypeInNewTab={onOpenTypeInNewTab}
        onRenameType={onRenameType}
        onAddSubtype={onAddSubtype}
        onDeleteType={onDeleteType}
        onChangeIcon={onChangeIcon}
        onMoveUp={onMoveUp}
        onMoveDown={onMoveDown}
      >
        <div className="relative">
          <SidebarRow
            active={active}
            onClick={() => onFilterChange({ kind: "type", path: node.path })}
            onOpenInNewTab={() => onOpenTypeInNewTab(node.path)}
            icon={
              <TypeIcon
                icon={typeIcon}
                open={isOpen && node.children.length > 0}
                size={15}
              />
            }
            label={node.name}
            depth={depth}
            chevron={
              node.children.length ? (isOpen ? "open" : "closed") : "leaf"
            }
              onToggle={() => onToggle(key)}
              toggleLocked={toggleLocked}
              toggleTitle={toggleLocked
                ? keptOpen
                  ? "Turn off Keep folder open in the folder menu to collapse"
                  : "A nested folder is kept open"
                : undefined}
          />
          <button
            ref={setActivatorNodeRef}
            type="button"
            aria-label={`Reorder ${node.name}`}
            title={`Drag to reorder ${node.name}`}
            onClick={(event) => {
              event.preventDefault();
              event.stopPropagation();
            }}
            className={cn(
              "absolute top-1/2 flex h-7 w-6 -translate-y-1/2 touch-none cursor-grab items-center justify-center text-zerus-sidebar-fg/35 opacity-0 transition-opacity hover:text-zerus-sidebar-fg/80 active:cursor-grabbing group-hover/type:opacity-100 focus:opacity-100",
              node.children.length ? "right-5" : "right-0",
            )}
            {...attributes}
            {...listeners}
          >
            <GripVertical size={13} aria-hidden="true" />
          </button>
        </div>
      </TypeContextMenu>
    </div>
  );
}

export function Sidebar({
  notes,
  taskCount,
  trashedImageCount,
  extraTypes,
  typeIcons,
  typeOrder,
  keptOpenTypes,
  onKeptOpenTypesChange,
  filter,
  isDesktop,
  vaultLocation,
  defaultNoteType,
  hideSubtypeNotes,
  onDefaultNoteTypeChange,
  onHideSubtypeNotesChange,
  onTypeOrderChange,
  onFilterChange,
  onOpenFilterInNewTab,
  onOpenTypeInNewTab,
  onCollapse,
  collapsed = false,
  onRestore = onCollapse,
}: SidebarProps) {
  const tree = useMemo(
    () => buildTypeTree(notes, extraTypes, typeOrder),
    [notes, extraTypes, typeOrder],
  );
  const { activeCount, externalCount, fileCount, linkCount, trashedNoteCount } = useMemo(() => {
    let activeCount = 0;
    let externalCount = 0;
    let fileCount = 0;
    let linkCount = 0;
    let trashedNoteCount = 0;
    for (const note of notes) {
      if (isExternalNote(note)) {
        externalCount++;
      } else if (isTrashed(note)) {
        trashedNoteCount++;
      } else {
        if (!isManagedSavedLinkNote(note)) activeCount++;
        if (getFileHubReference(note) !== null) fileCount++;
        if (getLinkHubReference(note) !== null) linkCount++;
      }
    }
    return { activeCount, externalCount, fileCount, linkCount, trashedNoteCount };
  }, [notes]);
  const trashCount = trashedNoteCount + trashedImageCount;
  const typeSensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 6 },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  // null = no creation dialog; parent path is kept separate so the field only
  // contains the new type's name.
  const [typeDraft, setTypeDraft] = useState<string | null>(null);
  const [typeParentPath, setTypeParentPath] = useState<string[]>([]);

  const startTypeCreation = (parentPath: string[] = []) => {
    setTypeParentPath(parentPath);
    setTypeDraft("");
  };

  const closeTypeCreation = () => {
    setTypeDraft(null);
    setTypeParentPath([]);
  };

  const reorderTypes = (
    sourceKey: string,
    targetKey: string,
    placement: "before" | "after",
  ) => {
    const order = reorderTypeTree(tree, sourceKey, targetKey, placement);
    if (order) onTypeOrderChange(order);
  };

  const handleTypeDragEnd = ({ active, over }: DragEndEvent) => {
    if (!over) return;
    const sourceKey = String(active.id);
    const targetKey = String(over.id);
    if (sourceKey === targetKey) return;
    const parentOf = (key: string) => key.split("/").slice(0, -1).join("/");
    if (parentOf(sourceKey) !== parentOf(targetKey)) return;

    const orderedKeys = flattenTypeKeys(tree);
    const placement =
      orderedKeys.indexOf(sourceKey) < orderedKeys.indexOf(targetKey)
        ? "after"
        : "before";
    reorderTypes(sourceKey, targetKey, placement);
  };

  const submitNewType = async (name: string) => {
    const path = [...typeParentPath, name].slice(0, MAX_TYPE_DEPTH);
    closeTypeCreation();
    if (!path.length) return;
    const existingKeys = new Set(flattenTypeKeys(tree));
    const created = await createType(path);
    if (!created) return;

    // Keep the current tree order as the baseline, then append every newly
    // created level. This makes a new root type (and new nested levels) land
    // at the bottom instead of being pulled into alphabetical fallback order.
    const newKeys: string[] = [];
    for (let depth = 1; depth <= path.length; depth++) {
      const key = typeKey(path.slice(0, depth));
      if (!existingKeys.has(key)) newKeys.push(key);
    }
    if (newKeys.length) {
      const currentKeys = new Set(typeOrder);
      const baseline = [
        ...typeOrder,
        ...flattenTypeKeys(tree).filter((key) => !currentKeys.has(key)),
      ].filter((key) => !newKeys.includes(key));
      onTypeOrderChange([...baseline, ...newKeys]);
    }
    onFilterChange({ kind: "type", path });
  };

  // Type pending a rename, or null when no dialog is open
  const [renameTarget, setRenameTarget] = useState<TypeNode | null>(null);
  const [renameDraft, setRenameDraft] = useState("");

  const startRename = (node: TypeNode) => {
    setRenameTarget(node);
    setRenameDraft(typeKey(node.path));
  };

  const submitRename = async () => {
    if (!renameTarget) return;
    const oldPath = renameTarget.path;
    const newPath = parseTypePath(renameDraft);
    if (!newPath.length || typeKey(newPath) === typeKey(oldPath)) {
      setRenameTarget(null);
      return;
    }
    const renamed = await renameType(oldPath, newPath);
    if (!renamed) return;
    setRenameTarget(null);
    const oldKey = typeKey(oldPath);
    const oldPrefix = `${oldKey}/`;
    const newKey = typeKey(newPath);
    onTypeOrderChange(
      typeOrder.map((key) =>
        key === oldKey
          ? newKey
          : key.startsWith(oldPrefix)
            ? `${newKey}/${key.slice(oldPrefix.length)}`
            : key,
      ),
    );
    onKeptOpenTypesChange(
      keptOpenTypes.map((key) =>
        key === oldKey
          ? newKey
          : key.startsWith(oldPrefix)
            ? `${newKey}/${key.slice(oldPrefix.length)}`
            : key,
      ),
    );
    const defaultKey = typeKey(defaultNoteType);
    if (defaultKey === oldKey || defaultKey.startsWith(`${oldKey}/`)) {
      onDefaultNoteTypeChange([
        ...newPath,
        ...defaultNoteType.slice(oldPath.length),
      ]);
    }
    if (filter.kind === "type") {
      const activeKey = typeKey(filter.path);
      if (activeKey === oldKey || activeKey.startsWith(`${oldKey}/`)) {
        onFilterChange({
          kind: "type",
          path: [...newPath, ...filter.path.slice(oldPath.length)],
        });
      }
    }
  };

  // Type whose icon is being edited, or null when the picker is closed
  const [iconTarget, setIconTarget] = useState<TypeNode | null>(null);

  // Type pending a delete confirmation, or null when no dialog is open
  const [deleteTarget, setDeleteTarget] = useState<TypeNode | null>(null);

  const confirmDeleteType = async () => {
    if (!deleteTarget) return;
    const key = typeKey(deleteTarget.path);
    setDeleteTarget(null);
    const deleted = await deleteType(deleteTarget.path);
    if (!deleted) return;
    onTypeOrderChange(
      typeOrder.filter(
        (type) => type !== key && !type.startsWith(`${key}/`),
      ),
    );
    onKeptOpenTypesChange(
      keptOpenTypes.filter((type) => type !== key && !type.startsWith(`${key}/`)),
    );
    const defaultKey = typeKey(defaultNoteType);
    if (defaultKey === key || defaultKey.startsWith(`${key}/`)) {
      onDefaultNoteTypeChange(DEFAULT_TYPE);
    }
    const activeKey = filter.kind === "type" ? typeKey(filter.path) : null;
    if (activeKey && (activeKey === key || activeKey.startsWith(`${key}/`))) {
      onFilterChange({ kind: "all" });
    }
  };

  // Ordinary expansion lasts for this session; kept-open folders and their
  // ancestors stay expanded even after restarting or collapsing the sidebar.
  const [sessionExpansion, setSessionExpansion] = useState(() => ({
    vaultLocation,
    keys: new Set<string>(),
  }));
  const keptOpenSet = useMemo(() => new Set(keptOpenTypes), [keptOpenTypes]);
  const keptOpenBranches = useMemo(() => {
    const validKeys = new Set(flattenTypeKeys(tree));
    const branches = new Set<string>();
    for (const key of keptOpenTypes) {
      if (!validKeys.has(key)) continue;
      const path = key.split("/");
      for (let depth = 1; depth <= path.length; depth++) {
        branches.add(typeKey(path.slice(0, depth)));
      }
    }
    return branches;
  }, [keptOpenTypes, tree]);
  const expanded = useMemo(() => new Set([
    ...(sessionExpansion.vaultLocation === vaultLocation ? sessionExpansion.keys : []),
    ...keptOpenBranches,
  ]), [sessionExpansion, vaultLocation, keptOpenBranches]);
  const [visibleTypeCounts, setVisibleTypeCounts] = useState<
    Record<string, number>
  >({});
  const typeScrollContainerRef = useRef<HTMLElement>(null);

  const toggle = (key: string) => {
    if (keptOpenBranches.has(key)) return;
    setSessionExpansion((previous) => {
      const next = new Set(previous.vaultLocation === vaultLocation ? previous.keys : []);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return { vaultLocation, keys: next };
    });
  };

  const keepOpen = (path: string[], checked: boolean) => {
    const key = typeKey(path);
    const next = new Set(keptOpenTypes);
    if (checked) next.add(key);
    else next.delete(key);
    onKeptOpenTypesChange([...next]);
  };

  const loadMoreTypes = (parentKey: string) => {
    setVisibleTypeCounts((previous) => ({
      ...previous,
      [parentKey]:
        (previous[parentKey] ?? TYPE_TREE_PAGE_SIZE) + TYPE_TREE_PAGE_SIZE,
    }));
  };

  const vaultName = vaultLocation ? vaultNameFromPath(vaultLocation) : null;

  const [settingsOpen, setSettingsOpen] = useState(false);
  const [vaultsOpen, setVaultsOpen] = useState(false);

  return (
    <div className={cn("flex h-full flex-col bg-zerus-sidebar", !collapsed && "pt-4")}>
      {collapsed ? (
        <CollapsedSidebar
          notes={notes}
          extraTypes={extraTypes}
          typeIcons={typeIcons}
          typeOrder={typeOrder}
          keptOpenBranches={keptOpenBranches}
          filter={filter}
          isDesktop={isDesktop}
          defaultNoteType={defaultNoteType}
          hideSubtypeNotes={hideSubtypeNotes}
          onDefaultNoteTypeChange={onDefaultNoteTypeChange}
          onHideSubtypeNotesChange={onHideSubtypeNotesChange}
          onFilterChange={onFilterChange}
          onOpenFilterInNewTab={onOpenFilterInNewTab}
          onRestore={onRestore}
          renderTypeContextMenu={(node, button) => {
            const siblings = node.path.slice(0, -1).reduce<TypeNode[]>(
              (nodes, name) => nodes.find((parent) => parent.name === name)?.children ?? [],
              tree,
            );
            const key = typeKey(node.path);
            const index = siblings.findIndex((sibling) => typeKey(sibling.path) === key);
            const previous = siblings[index - 1];
            const next = siblings[index + 1];
            return (
              <TypeContextMenu
                key={key}
                node={node}
                canMoveUp={!!previous}
                canMoveDown={!!next}
                keptOpen={keptOpenSet.has(key)}
                onKeepOpenChange={(checked) => keepOpen(node.path, checked)}
                onOpenTypeInNewTab={onOpenTypeInNewTab}
                onRenameType={startRename}
                onAddSubtype={(target) => startTypeCreation(target.path)}
                onDeleteType={setDeleteTarget}
                onChangeIcon={setIconTarget}
                onMoveUp={() => previous && reorderTypes(key, typeKey(previous.path), "before")}
                onMoveDown={() => next && reorderTypes(key, typeKey(next.path), "after")}
              >
                {button}
              </TypeContextMenu>
            );
          }}
        />
      ) : (
        <>
          <div className="flex items-center justify-between px-4 pb-3">
            <h1 className="flex min-w-0 items-center gap-2 text-sm font-semibold tracking-wide text-zerus-sidebar-fg/90">
              <ZerusLogo
                alt=""
                className="h-6 w-6 shrink-0 rounded-sm"
              />
              <span className="truncate">Zerus</span>
            </h1>
            <button
              type="button"
              onClick={onCollapse}
              title="Collapse navigation sidebar"
              aria-label="Collapse navigation sidebar"
              className="text-zerus-sidebar-fg/50 transition-colors hover:text-zerus-sidebar-fg/90"
            >
              <ChevronsLeft size={15} />
            </button>
          </div>
          <nav
            ref={typeScrollContainerRef}
            className="flex-1 space-y-0.5 overflow-y-auto px-2"
          >
            <SidebarRow
              active={filter.kind === "all"}
              onClick={() => onFilterChange({ kind: "all" })}
              onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "all" })}
              icon={<Notebook size={15} />}
              label="All Notes"
              count={activeCount}
            />
            <SidebarRow
              active={filter.kind === "tasks"}
              onClick={() => onFilterChange({ kind: "tasks" })}
              onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "tasks" })}
              icon={<CheckSquare size={15} />}
              label="Tasks"
              count={taskCount}
            />
            {isDesktop && (
              <>
                <SidebarRow
                  active={filter.kind === "external"}
                  onClick={() => onFilterChange({ kind: "external" })}
                  onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "external" })}
                  icon={<Files size={15} />}
                  label="External Notes"
                  count={externalCount}
                />
                <SidebarRow
                  active={filter.kind === "files"}
                  onClick={() => onFilterChange({ kind: "files" })}
                  onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "files" })}
                  icon={<FileStack size={15} />}
                  label="Files"
                  count={fileCount}
                />
              </>
            )}
            <SidebarRow
              active={filter.kind === "links"}
              onClick={() => onFilterChange({ kind: "links" })}
              onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "links" })}
              icon={<Link2 size={15} />}
              label="Links"
              count={linkCount}
            />
            <div className="flex items-center justify-between pb-1 pl-3 pr-2 pt-4">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-zerus-sidebar-fg/40">
                Types
              </span>
              <button
                onClick={() => startTypeCreation()}
                title="New type — it can stay empty until you add notes"
                className="text-zerus-sidebar-fg/40 transition-colors hover:text-zerus-sidebar-fg/90"
              >
                <Plus size={13} />
              </button>
            </div>
            <DndContext
              sensors={typeSensors}
              collisionDetection={closestCenter}
              onDragEnd={handleTypeDragEnd}
            >
              <TypeTreeRows
                nodes={tree}
                depth={0}
                parentKey=""
                filter={filter}
                expanded={expanded}
                keptOpenTypes={keptOpenSet}
                keptOpenBranches={keptOpenBranches}
                visibleCounts={visibleTypeCounts}
                typeIcons={typeIcons}
                onFilterChange={onFilterChange}
                onOpenTypeInNewTab={onOpenTypeInNewTab}
                onToggle={toggle}
                onKeepOpenChange={keepOpen}
                onRenameType={startRename}
                onAddSubtype={(node) => startTypeCreation(node.path)}
                onDeleteType={setDeleteTarget}
                onChangeIcon={setIconTarget}
                onReorder={reorderTypes}
                scrollContainerRef={typeScrollContainerRef}
                onLoadMore={loadMoreTypes}
              />
            </DndContext>
          </nav>
          <div className="space-y-0.5 border-t border-zerus-sidebar-fg/10 p-2">
            <GlobalSearchButton className="w-full px-2 py-1.5 text-zerus-sidebar-fg/70 transition-colors hover:bg-zerus-sidebar-fg/5 hover:text-zerus-sidebar-fg/90 [&>svg]:size-[15px] [&>svg]:shrink-0 [&>svg]:opacity-80" />
            <SidebarRow
              active={settingsOpen}
              onClick={() => setSettingsOpen(true)}
              icon={<Settings size={15} />}
              label="Settings"
            />
            <SidebarRow
              active={filter.kind === "trash"}
              onClick={() => onFilterChange({ kind: "trash" })}
              onOpenInNewTab={() => onOpenFilterInNewTab({ kind: "trash" })}
              icon={<Trash2 size={15} />}
              label="Trash"
              count={trashCount}
            />
            {isDesktop && (
              <button
                type="button"
                onClick={() => setVaultsOpen(true)}
                title={vaultLocation ?? undefined}
                className="w-full truncate rounded-md px-3 py-1 text-left text-[11px] text-zerus-sidebar-fg/40 transition-colors hover:bg-zerus-sidebar-fg/5 hover:text-zerus-sidebar-fg/70"
              >
                Vault: {vaultName ?? "choose folder…"}
              </button>
            )}
          </div>
        </>
      )}
      <ThemeSettingsDialog
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        defaultNoteType={defaultNoteType}
        hideSubtypeNotes={hideSubtypeNotes}
        existingTypePaths={getAllTypePaths(notes, extraTypes)}
        onDefaultNoteTypeChange={onDefaultNoteTypeChange}
        onHideSubtypeNotesChange={onHideSubtypeNotesChange}
      />
      <VaultSwitcherDialog
        currentPath={vaultLocation}
        open={vaultsOpen}
        onOpenChange={setVaultsOpen}
      />
      <IconPickerDialog
        open={iconTarget !== null}
        typeName={iconTarget?.name ?? ""}
        value={iconTarget ? typeIcons[typeKey(iconTarget.path)] : undefined}
        onOpenChange={(open) => {
          if (!open) setIconTarget(null);
        }}
        onPick={(icon) => {
          if (iconTarget) setTypeIcon(iconTarget.path, icon);
        }}
      />
      <TypeCreationDialog
        open={typeDraft !== null}
        parentPath={typeParentPath}
        draft={typeDraft ?? ""}
        onDraftChange={setTypeDraft}
        onOpenChange={(open) => {
          if (!open) closeTypeCreation();
        }}
        onSubmit={(name) => void submitNewType(name)}
      />
      <Dialog
        open={renameTarget !== null}
        onOpenChange={(open) => {
          if (!open) setRenameTarget(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rename type "{renameTarget?.name}"</DialogTitle>
          </DialogHeader>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void submitRename();
            }}
          >
            <Input
              autoFocus
              value={renameDraft}
              onChange={(event) => setRenameDraft(event.target.value)}
              placeholder="type (e.g. work/projects)"
            />
            <DialogFooter className="mt-4">
              <Button
                type="button"
                variant="outline"
                onClick={() => setRenameTarget(null)}
              >
                Cancel
              </Button>
              <Button type="submit">Rename</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
      <AlertDialog
        open={deleteTarget !== null}
        onOpenChange={(open) => {
          if (!open) setDeleteTarget(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete type "{deleteTarget?.name}"?
            </AlertDialogTitle>
            <AlertDialogDescription>
              {deleteTarget && deleteTarget.count > 0
                ? `${deleteTarget.count} note${deleteTarget.count === 1 ? "" : "s"} in this type will be moved to Trash.`
                : "This type has no notes."}
              {deleteTarget && deleteTarget.children.length > 0 && (
                <> Its sub-types will be deleted too.</>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => void confirmDeleteType()}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
