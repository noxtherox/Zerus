import { useState } from "react";
import { FileStack, Files, Link2, Notebook, Settings, Trash2 } from "@/lib/icons";
import { ZerusLogo } from "@/components/ZerusLogo";
import type { NoteFilter } from "@/lib/filters";
import {
  buildTypeTree,
  getAllTypePaths,
  type Note,
  type TypeNode,
  typeKey,
} from "@/lib/note-utils";
import type { TypeIcons } from "@/lib/type-icons";
import { cn } from "@/lib/utils";
import { ThemeSettingsDialog } from "./ThemeSettingsDialog";
import { TypeIcon } from "./TypeIcon";

interface CollapsedSidebarProps {
  notes: Note[];
  extraTypes: string[][];
  typeIcons: TypeIcons;
  typeOrder: string[];
  filter: NoteFilter;
  isDesktop: boolean;
  defaultNoteType: string[];
  hideSubtypeNotes: boolean;
  onDefaultNoteTypeChange: (typePath: string[]) => void;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
  onFilterChange: (filter: NoteFilter) => void;
  onRestore: () => void;
}

function pathsMatch(left: string[], right: string[]): boolean {
  return (
    left.length === right.length &&
    left.every((part, index) => part === right[index])
  );
}

function isPathPrefix(prefix: string[], path: string[]): boolean {
  return (
    prefix.length <= path.length &&
    prefix.every((part, index) => part === path[index])
  );
}

function visibleTypeNodes(
  nodes: TypeNode[],
  selectedPath: string[] | null,
): TypeNode[] {
  return nodes.flatMap((node) => [
    node,
    ...(selectedPath && isPathPrefix(node.path, selectedPath)
      ? visibleTypeNodes(node.children, selectedPath)
      : []),
  ]);
}

export function CollapsedSidebar({
  notes,
  extraTypes,
  typeIcons,
  typeOrder,
  filter,
  isDesktop,
  defaultNoteType,
  hideSubtypeNotes,
  onDefaultNoteTypeChange,
  onHideSubtypeNotesChange,
  onFilterChange,
  onRestore,
}: CollapsedSidebarProps) {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const types = buildTypeTree(notes, extraTypes, typeOrder);
  const selectedTypePath = filter.kind === "type" ? filter.path : null;
  const visibleTypes = visibleTypeNodes(types, selectedTypePath);

  const iconButtonClass = (active: boolean) =>
    cn(
      "flex h-8 w-8 shrink-0 items-center justify-center rounded-md transition-colors",
      active
        ? "bg-zerus-sidebar-fg/15 text-zerus-sidebar-fg"
        : "text-zerus-sidebar-fg/60 hover:bg-zerus-sidebar-fg/10 hover:text-zerus-sidebar-fg/90",
    );

  const renderType = (node: TypeNode) => {
    const key = typeKey(node.path);
    const selected = selectedTypePath
      ? pathsMatch(node.path, selectedTypePath)
      : false;
    const selectedSubfolder = selected && node.path.length > 1;
    const immediateParent = selectedTypePath
      ? node.path.length + 1 === selectedTypePath.length &&
        isPathPrefix(node.path, selectedTypePath)
      : false;
    const directChild = selectedTypePath
      ? selectedTypePath.length + 1 === node.path.length &&
        isPathPrefix(selectedTypePath, node.path)
      : false;
    const topLevelAncestor = selectedTypePath
      ? node.path.length === 1 &&
        selectedTypePath.length >= 3 &&
        isPathPrefix(node.path, selectedTypePath)
      : false;
    const expanded = selectedTypePath
      ? node.children.length > 0 && isPathPrefix(node.path, selectedTypePath)
      : false;
    const label = node.path.join(" / ");
    const contextual = immediateParent || directChild;

    return (
      <button
        key={key}
        type="button"
        onClick={() => onFilterChange({ kind: "type", path: node.path })}
        title={label}
        aria-label={`Type: ${label}`}
        aria-current={selected ? "page" : undefined}
        aria-expanded={node.children.length > 0 ? expanded : undefined}
        className={cn(
          iconButtonClass(selected),
          selected && !selectedSubfolder && "bg-zerus-sidebar-fg/25",
          contextual && !selected && "text-zerus-sidebar-fg/90",
        )}
        style={
          selectedSubfolder
            ? {
                backgroundColor: "rgb(var(--zerus-sidebar-fg) / 0.18)",
                backgroundImage:
                  "repeating-linear-gradient(45deg, transparent 0 3px, rgb(var(--zerus-sidebar-fg) / 0.24) 3px 4px)",
                boxShadow:
                  "inset 0 0 0 1px rgb(var(--zerus-sidebar-fg) / 0.42)",
              }
            : selected
            ? {
                boxShadow:
                  "inset 0 0 0 1px rgb(var(--zerus-sidebar-fg) / 0.32)",
              }
            : contextual
              ? {
                  backgroundColor: "rgb(var(--zerus-sidebar-fg) / 0.07)",
                  backgroundImage:
                    "repeating-linear-gradient(135deg, transparent 0 3px, rgb(var(--zerus-sidebar-fg) / 0.16) 3px 4px)",
                }
              : topLevelAncestor
                ? {
                    boxShadow:
                      "inset 0 0 0 1px rgb(var(--zerus-sidebar-fg) / 0.3)",
                  }
                : undefined
        }
      >
        <TypeIcon icon={typeIcons[key]} size={16} />
      </button>
    );
  };

  return (
    <nav
      className="flex h-full w-12 flex-col items-center bg-zerus-sidebar py-3"
      aria-label="Collapsed navigation sidebar"
    >
      <button
        type="button"
        onClick={onRestore}
        title="Expand navigation sidebar"
        aria-label="Expand navigation sidebar to default width"
        className="mb-2 flex h-8 w-8 shrink-0 items-center justify-center rounded-md transition-colors hover:bg-zerus-sidebar-fg/10"
      >
        <ZerusLogo
          alt=""
          className="h-6 w-6 rounded-sm"
        />
      </button>

      <div className="flex min-h-0 w-full flex-1 flex-col items-center overflow-x-hidden overflow-y-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <button
          type="button"
          onClick={() => onFilterChange({ kind: "all" })}
          title="All Notes"
          aria-label="All Notes"
          className={iconButtonClass(filter.kind === "all")}
        >
          <Notebook size={16} />
        </button>

        {isDesktop && (
          <>
            <button
              type="button"
              onClick={() => onFilterChange({ kind: "external" })}
              title="External Notes"
              aria-label="External Notes"
              className={iconButtonClass(filter.kind === "external")}
            >
              <Files size={16} />
            </button>
            <button
              type="button"
              onClick={() => onFilterChange({ kind: "files" })}
              title="Files"
              aria-label="Files"
              className={iconButtonClass(filter.kind === "files")}
            >
              <FileStack size={16} />
            </button>
            <button
              type="button"
              onClick={() => onFilterChange({ kind: "links" })}
              title="Links"
              aria-label="Links"
              className={iconButtonClass(filter.kind === "links")}
            >
              <Link2 size={16} />
            </button>
          </>
        )}

        <div className="my-2 h-px w-7 shrink-0 bg-zerus-sidebar-fg/15" />

        <div className="flex w-full flex-col items-center gap-0.5">
          {visibleTypes.map(renderType)}
        </div>
      </div>

      <div className="mt-2 flex w-full shrink-0 flex-col items-center border-t border-zerus-sidebar-fg/15 pt-2">
        <button
          type="button"
          onClick={() => setSettingsOpen(true)}
          title="Settings"
          aria-label="Settings"
          className={iconButtonClass(settingsOpen)}
        >
          <Settings size={16} />
        </button>
        <button
          type="button"
          onClick={() => onFilterChange({ kind: "trash" })}
          title="Trash"
          aria-label="Trash"
          className={iconButtonClass(filter.kind === "trash")}
        >
          <Trash2 size={16} />
        </button>
      </div>

      <ThemeSettingsDialog
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        defaultNoteType={defaultNoteType}
        hideSubtypeNotes={hideSubtypeNotes}
        existingTypePaths={getAllTypePaths(notes, extraTypes)}
        onDefaultNoteTypeChange={onDefaultNoteTypeChange}
        onHideSubtypeNotesChange={onHideSubtypeNotesChange}
      />
    </nav>
  );
}
