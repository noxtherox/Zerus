import type {
  KeyboardEventHandler,
  RefObject,
} from "react";
import { Button } from "@/components/ui/button";
import {
  Check,
  Copy,
  ExternalLink,
  ImageIcon,
  Link2,
  Link2Off,
  Pencil,
  RefreshCw,
  Trash2,
  X,
} from "@/lib/icons";
import type { EditorImageMatch } from "./image-extension";
import type { ExternalLinkMatch } from "./live-preview";
import type {
  PasteChoice,
  PasteChoiceSession,
} from "./paste-options";

export interface LinkPopoverState {
  link: ExternalLinkMatch;
  target: HTMLElement;
  left: number;
  top: number;
  width: number;
}

export interface PastePopoverState extends PasteChoiceSession {
  left: number;
  top: number;
  width: number;
}

export interface ImagePopoverState {
  image: EditorImageMatch;
  target: HTMLElement;
  left: number;
  top: number;
  width: number;
}

interface PasteOptionsPopoverProps {
  state: PastePopoverState;
  elementRef: RefObject<HTMLDivElement | null>;
  onKeyDown: KeyboardEventHandler<HTMLDivElement>;
  onClose: () => void;
  onSelect: (choice: PasteChoice) => void;
}

export function PasteOptionsPopover({
  state,
  elementRef,
  onKeyDown,
  onClose,
  onSelect,
}: PasteOptionsPopoverProps) {
  return (
    <div
      ref={elementRef}
      className="absolute z-50 overflow-hidden rounded-xl border border-border bg-popover p-1.5 text-popover-foreground shadow-[0_14px_38px_rgb(0_0_0/0.3)]"
      style={{ left: state.left, top: state.top, width: state.width }}
      role="menu"
      aria-label="Paste options"
      onMouseDown={(event) => event.stopPropagation()}
      onKeyDown={onKeyDown}
    >
      <div className="flex items-center justify-between gap-2 pb-1.5 pl-2.5 pr-1 pt-1">
        <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          Paste options
        </span>
        <button
          type="button"
          role="menuitem"
          className="flex h-5 w-5 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent/70 hover:text-popover-foreground focus-visible:bg-accent/70 focus-visible:text-popover-foreground focus-visible:outline-none"
          title="Close paste options"
          aria-label="Close paste options"
          onClick={onClose}
        >
          <X size={13} aria-hidden="true" />
        </button>
      </div>
      {state.choices.map((choice) => {
        const selected = state.selectedMode === choice.mode;
        return (
          <button
            key={choice.mode}
            type="button"
            role="menuitemradio"
            aria-checked={selected}
            className="flex min-h-11 w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left hover:bg-accent/70 focus-visible:bg-accent/70 focus-visible:outline-none"
            onClick={() => onSelect(choice)}
          >
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-medium">
                {choice.label}
              </span>
              <span className="block truncate text-[11px] text-muted-foreground">
                {choice.description}
              </span>
            </span>
            <Check
              size={15}
              className={
                selected
                  ? "shrink-0 text-zerus-accent"
                  : "shrink-0 opacity-0"
              }
              aria-hidden="true"
            />
          </button>
        );
      })}
    </div>
  );
}

interface ImageActionsPopoverProps {
  state: ImagePopoverState;
  elementRef: RefObject<HTMLDivElement | null>;
  readOnly: boolean;
  editAlt: string | null;
  copied: boolean;
  onEditAltChange: (value: string | null) => void;
  onSaveAlt: () => void;
  onOpen: () => void;
  onReplace: () => void;
  onCopy: () => void;
  onRemove: () => void;
}

export function ImageActionsPopover({
  state,
  elementRef,
  readOnly,
  editAlt,
  copied,
  onEditAltChange,
  onSaveAlt,
  onOpen,
  onReplace,
  onCopy,
  onRemove,
}: ImageActionsPopoverProps) {
  return (
    <div
      ref={elementRef}
      className="absolute z-10 flex h-12 items-center overflow-hidden rounded-lg border border-border bg-popover px-2 text-popover-foreground shadow-[0_12px_32px_rgb(0_0_0/0.28)]"
      style={{ left: state.left, top: state.top, width: state.width }}
      role="toolbar"
      aria-label="Image actions"
      onMouseDown={(event) => event.stopPropagation()}
    >
      <ImageIcon
        size={16}
        className="mx-1 shrink-0 text-muted-foreground"
        aria-hidden="true"
      />
      {editAlt == null ? (
        <span
          className="min-w-0 flex-1 truncate px-2 text-sm text-muted-foreground"
          title={state.image.path}
        >
          {state.image.path.split("/").pop() || "Image"}
        </span>
      ) : (
        <div className="min-w-0 flex-1 px-1">
          <input
            autoFocus
            className="h-8 w-full rounded-md border border-border/70 bg-background/60 px-2 text-sm outline-none focus:border-zerus-accent"
            value={editAlt}
            aria-label="Image alt text"
            placeholder="Describe this image"
            onChange={(event) => onEditAltChange(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                onSaveAlt();
              } else if (event.key === "Escape") {
                event.preventDefault();
                onEditAltChange(null);
              }
            }}
          />
        </div>
      )}
      <div className="mx-1 h-6 w-px shrink-0 bg-border/70" aria-hidden="true" />
      {editAlt == null ? (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
            title="Open image"
            aria-label="Open image"
            onClick={onOpen}
          >
            <ExternalLink size={16} />
          </Button>
          {!readOnly && (
            <>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-8 w-8 shrink-0 text-muted-foreground"
                title="Replace image"
                aria-label="Replace image"
                onClick={onReplace}
              >
                <RefreshCw size={16} />
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-8 w-8 shrink-0 text-muted-foreground"
                title="Edit alt text"
                aria-label="Edit image alt text"
                onClick={() => onEditAltChange(state.image.alt)}
              >
                <Pencil size={16} />
              </Button>
            </>
          )}
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-muted-foreground"
            title={copied ? "Copied" : "Copy image"}
            aria-label={copied ? "Image copied" : "Copy image"}
            onClick={onCopy}
          >
            {copied ? <Check size={16} /> : <Copy size={16} />}
          </Button>
          {!readOnly && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-8 w-8 shrink-0 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
              title="Remove image"
              aria-label="Remove image"
              onClick={onRemove}
            >
              <Trash2 size={16} />
            </Button>
          )}
        </>
      ) : (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
            title="Save alt text"
            aria-label="Save image alt text"
            onClick={onSaveAlt}
          >
            <Check size={16} />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-muted-foreground"
            title="Cancel editing"
            aria-label="Cancel editing image alt text"
            onClick={() => onEditAltChange(null)}
          >
            <X size={16} />
          </Button>
        </>
      )}
      <span className="sr-only" aria-live="polite">
        {copied ? "Image copied" : ""}
      </span>
    </div>
  );
}

interface LinkActionsPopoverProps {
  state: LinkPopoverState;
  elementRef: RefObject<HTMLDivElement | null>;
  readOnly: boolean;
  sourceUrl: string;
  editUrl: string | null;
  editUrlError: boolean;
  copied: boolean;
  onEditUrlChange: (value: string | null) => void;
  onClearEditError: () => void;
  onSave: () => void;
  onOpen: () => void;
  onBeginEditing: () => void;
  onCopy: () => void;
  onRemove: () => void;
}

export function LinkActionsPopover({
  state,
  elementRef,
  readOnly,
  sourceUrl,
  editUrl,
  editUrlError,
  copied,
  onEditUrlChange,
  onClearEditError,
  onSave,
  onOpen,
  onBeginEditing,
  onCopy,
  onRemove,
}: LinkActionsPopoverProps) {
  const cancelEditing = () => {
    onEditUrlChange(null);
    onClearEditError();
  };

  return (
    <div
      ref={elementRef}
      className="absolute z-10 flex h-12 items-center overflow-hidden rounded-lg border border-border bg-popover px-2 text-popover-foreground shadow-[0_12px_32px_rgb(0_0_0/0.28)]"
      style={{ left: state.left, top: state.top, width: state.width }}
      role="toolbar"
      aria-label="Link actions"
      onMouseDown={(event) => event.stopPropagation()}
    >
      <Link2
        size={16}
        className="mx-1 shrink-0 text-muted-foreground"
        aria-hidden="true"
      />
      {editUrl == null ? (
        <span
          className="min-w-0 flex-1 truncate px-2 text-sm text-muted-foreground"
          title={sourceUrl}
        >
          {sourceUrl}
        </span>
      ) : (
        <div className="min-w-0 flex-1 px-1">
          <input
            autoFocus
            className="h-8 w-full rounded-md border border-border/70 bg-background/60 px-2 text-sm outline-none focus:border-zerus-accent"
            value={editUrl}
            aria-label="Link destination"
            aria-invalid={editUrlError}
            onChange={(event) => {
              onEditUrlChange(event.target.value);
              onClearEditError();
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                onSave();
              } else if (event.key === "Escape") {
                event.preventDefault();
                cancelEditing();
              }
            }}
          />
          {editUrlError && (
            <span className="sr-only" role="alert">
              Enter a complete http or https URL.
            </span>
          )}
        </div>
      )}
      <div className="mx-1 h-6 w-px shrink-0 bg-border/70" aria-hidden="true" />
      {editUrl == null ? (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
            title="Open link"
            aria-label="Open link"
            onClick={onOpen}
          >
            <ExternalLink size={16} />
          </Button>
          <div className="mx-1 h-6 w-px shrink-0 bg-border/70" aria-hidden="true" />
          {!readOnly && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-8 w-8 shrink-0 text-muted-foreground"
              title="Edit destination"
              aria-label="Edit link destination"
              onClick={onBeginEditing}
            >
              <Pencil size={16} />
            </Button>
          )}
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-muted-foreground"
            title={copied ? "Copied" : "Copy link"}
            aria-label={copied ? "Link copied" : "Copy link"}
            onClick={onCopy}
          >
            {copied ? <Check size={16} /> : <Copy size={16} />}
          </Button>
          {!readOnly && state.link.kind === "markdown" && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-8 w-8 shrink-0 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
              title="Remove link"
              aria-label="Remove link"
              onClick={onRemove}
            >
              <Link2Off size={16} />
            </Button>
          )}
        </>
      ) : (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
            title="Save destination"
            aria-label="Save link destination"
            onClick={onSave}
          >
            <Check size={16} />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 text-muted-foreground"
            title="Cancel editing"
            aria-label="Cancel editing link"
            onClick={cancelEditing}
          >
            <X size={16} />
          </Button>
        </>
      )}
      <span className="sr-only" aria-live="polite">
        {copied ? "Link copied" : ""}
      </span>
    </div>
  );
}
