import { Pin, X } from "@/lib/icons";
import { noteTitle, type Note } from "@/lib/note-utils";
import type { WorkspaceTab } from "@/lib/note-tabs";
import type { TypeIcons } from "@/lib/type-icons";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { cn } from "@/lib/utils";
import { TypeIcon } from "./TypeIcon";

interface NoteTabsProps {
  tabs: WorkspaceTab[];
  activeTabId: string | null;
  notes: Note[];
  typeIcons: TypeIcons;
  onActivate: (tabId: string) => void;
  onTogglePinned: (tabId: string) => void;
  onClose: (tabId: string) => void;
}

export function NoteTabs({
  tabs,
  activeTabId,
  notes,
  typeIcons,
  onActivate,
  onTogglePinned,
  onClose,
}: NoteTabsProps) {
  return (
    <div
      className="flex h-9 shrink-0 overflow-x-auto border-b border-border/60 bg-zerus-surface px-1 pt-1"
      role="tablist"
      aria-label="Open workspaces"
    >
      {tabs.map((tab) => {
        const note =
          tab.kind === "note"
            ? notes.find((candidate) => candidate.id === tab.noteId)
            : null;
        const title =
          tab.kind === "type"
            ? (tab.typePath.at(-1) ?? "Type")
            : note
              ? noteTitle(note)
              : "Closed note";
        const fullTitle =
          tab.kind === "type" ? tab.typePath.join(" / ") : title;
        const active = tab.id === activeTabId;
        return (
          <ContextMenu key={tab.id}>
            <ContextMenuTrigger asChild>
              <button
                type="button"
                role="tab"
                aria-selected={active}
                title={fullTitle}
                onClick={() => onActivate(tab.id)}
                onAuxClick={(event) => {
                  if (event.button !== 1) return;
                  event.preventDefault();
                  onClose(tab.id);
                }}
                className={cn(
                  "group flex h-8 min-w-28 max-w-56 items-center gap-1.5 rounded-t-md border border-b-0 px-2.5 text-xs transition-colors",
                  active
                    ? "border-border/70 bg-zerus-editor text-foreground"
                    : "border-transparent text-muted-foreground hover:bg-zerus-text/[0.04] hover:text-foreground",
                )}
              >
                {tab.kind === "type" && (
                  <TypeIcon
                    icon={typeIcons[tab.typePath.join("/")]}
                    size={13}
                  />
                )}
                {tab.pinned && (
                  <Pin size={12} className="shrink-0 text-zerus-accent" />
                )}
                <span className="min-w-0 flex-1 truncate text-left">{title}</span>
                {!tab.pinned && (
                  <span
                    role="button"
                    tabIndex={-1}
                    aria-label={`Close ${fullTitle}`}
                    className="flex h-4 w-4 shrink-0 items-center justify-center rounded opacity-0 hover:bg-muted group-hover:opacity-70"
                    onClick={(event) => {
                      event.stopPropagation();
                      onClose(tab.id);
                    }}
                  >
                    <X size={11} />
                  </span>
                )}
              </button>
            </ContextMenuTrigger>
            <ContextMenuContent>
              <ContextMenuItem onClick={() => onTogglePinned(tab.id)}>
                <Pin size={14} className="mr-2" />
                {tab.pinned ? "Unpin tab" : "Pin tab"}
              </ContextMenuItem>
              <ContextMenuSeparator />
              <ContextMenuItem onClick={() => onClose(tab.id)}>
                <X size={14} className="mr-2" /> Close tab
              </ContextMenuItem>
            </ContextMenuContent>
          </ContextMenu>
        );
      })}
    </div>
  );
}
