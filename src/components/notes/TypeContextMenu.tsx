import type { ReactNode } from "react";
import {
  ArrowDown,
  ArrowUp,
  FilePlus2,
  FolderPlus,
  Pencil,
  Smile,
  Trash2,
} from "@/lib/icons";
import { MAX_TYPE_DEPTH, type TypeNode } from "@/lib/note-utils";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuCheckboxItem,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";

interface TypeContextMenuProps {
  node: TypeNode;
  children: ReactNode;
  canMoveUp: boolean;
  canMoveDown: boolean;
  keptOpen: boolean;
  onKeepOpenChange: (keptOpen: boolean) => void;
  onOpenTypeInNewTab: (typePath: string[]) => void;
  onRenameType: (node: TypeNode) => void;
  onAddSubtype: (node: TypeNode) => void;
  onDeleteType: (node: TypeNode) => void;
  onChangeIcon: (node: TypeNode) => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
}

export function TypeContextMenu({
  node,
  children,
  canMoveUp,
  canMoveDown,
  keptOpen,
  onKeepOpenChange,
  onOpenTypeInNewTab,
  onRenameType,
  onAddSubtype,
  onDeleteType,
  onChangeIcon,
  onMoveUp,
  onMoveDown,
}: TypeContextMenuProps) {
  return (
    <ContextMenu>
      <ContextMenuTrigger asChild>{children}</ContextMenuTrigger>
      <ContextMenuContent>
        <ContextMenuItem onClick={() => onOpenTypeInNewTab(node.path)}>
          <FilePlus2 size={14} className="mr-2" /> Open in new tab
        </ContextMenuItem>
        <ContextMenuCheckboxItem
          checked={keptOpen}
          onCheckedChange={(checked) => onKeepOpenChange(checked === true)}
        >
          Keep folder open
        </ContextMenuCheckboxItem>
        <ContextMenuItem disabled={!canMoveUp} onClick={onMoveUp}>
          <ArrowUp size={14} className="mr-2" /> Move up
        </ContextMenuItem>
        <ContextMenuItem disabled={!canMoveDown} onClick={onMoveDown}>
          <ArrowDown size={14} className="mr-2" /> Move down
        </ContextMenuItem>
        <ContextMenuItem onClick={() => onChangeIcon(node)}>
          <Smile size={14} className="mr-2" /> Change icon
        </ContextMenuItem>
        <ContextMenuItem
          disabled={node.path.length >= MAX_TYPE_DEPTH}
          onClick={() => onAddSubtype(node)}
        >
          <FolderPlus size={14} className="mr-2" /> Add subtype
        </ContextMenuItem>
        <ContextMenuItem onClick={() => onRenameType(node)}>
          <Pencil size={14} className="mr-2" /> Rename type
        </ContextMenuItem>
        <ContextMenuItem
          className="text-destructive"
          onClick={() => onDeleteType(node)}
        >
          <Trash2 size={14} className="mr-2" /> Delete type
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  );
}
