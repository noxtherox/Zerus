import { useEffect, useRef, useState } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  drawSelection,
  EditorView,
  placeholder,
  keymap,
} from "@codemirror/view";
import {
  Compartment,
  EditorSelection,
  EditorState,
} from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentLess,
  indentMore,
  indentWithTab,
} from "@codemirror/commands";
import { completionKeymap } from "@codemirror/autocomplete";
import {
  editorTheme,
  currentLineTripleClickSelection,
  markdownHighlighting,
  titleLineExtension,
  wikilinkExtension,
  inlineTagExtension,
  wikilinkAutocomplete,
} from "./markdown-extensions";
import {
  type EditorImageMatch,
  imagePasteExtension,
  imagePreviewExtension,
} from "./image-extension";
import {
  type AttachmentAction,
  attachmentCardExtension,
} from "./attachment-extension";
import {
  type ExternalLinkMatch,
  livePreviewExtension,
  setEditorPresentationMode,
  toggleEditorPresentationMode,
} from "./live-preview";
import {
  copyImageToClipboard,
  discardUnsavedImage,
  getImageUrl,
  openImageInDefaultApp,
  restoreTrashedImage,
  savePastedImage,
  trashImageForNote,
} from "@/store/notes-store";
import { Button } from "@/components/ui/button";
import {
  Bold,
  Code2,
  Heading1,
  Heading2,
  Heading3,
  IndentDecrease,
  IndentIncrease,
  Italic,
  Link,
  List,
  ListOrdered,
  Maximize,
  Markdown,
  Minimize,
  Paperclip,
  Quote,
  Search,
  Sparkles,
  Strikethrough,
  Table2,
} from "@/lib/icons";
import { insertMarkdownTable } from "./markdown-table";
import { TableSizeDialog } from "./TableSizeDialog";
import { LinkDialog } from "./LinkDialog";
import { formatMarkdownLink } from "./link-format";
import { openExternalUrl } from "@/lib/external-links";
import { findInNoteExtension, openFindInNote } from "./find-in-note";
import { richCopyExtension } from "./rich-copy";
import {
  applyPasteChoice,
  joinEditorHistoryEvent,
  type PasteChoice,
  type PasteChoiceSession,
  pasteHistoryTracking,
  pasteOptionsExtension,
} from "./paste-options";
import { markdownListIndentation } from "./list-indentation";
import {
  literalMarkdownSymbolTyping,
  markdownEditingMechanics,
} from "./editing-mechanics";
import {
  isImageAttachmentPath,
  type NoteAttachment,
} from "@/lib/note-attachments";
import {
  EDITOR_MODE_CHANGE_EVENT,
  loadEditorMode,
  loadMarkdownTypingEnabled,
  MARKDOWN_TYPING_CHANGE_EVENT,
  saveEditorMode,
  type EditorMode,
} from "@/lib/note-preferences";
import { formatImageMarkdown } from "@/lib/note-utils";
import { toast } from "sonner";
import { editorPopoverPosition } from "./popover-position";
import { shouldDismissImagePopover } from "./image-popover-dismiss";
import {
  interpretSelectionAsMarkdown,
  setHeadingLevel,
  toggleInlineMarkup,
  toggleLinePrefix,
} from "./editor-commands";
import {
  ImageActionsPopover,
  LinkActionsPopover,
  PasteOptionsPopover,
  type ImagePopoverState,
  type LinkPopoverState,
  type PastePopoverState,
} from "./EditorPopovers";
import { imageEditIsCurrent } from "./image-edit-guard";

interface MarkdownEditorProps {
  noteId: string;
  initialContent: string;
  getLinkableTitles: () => string[];
  isTitleResolved: (title: string) => boolean;
  onChange: (content: string) => void;
  onFollowLink: (title: string) => void;
  readOnly?: boolean;
  autoFocus?: boolean;
  placeholderText?: string;
  firstLineIsTitle?: boolean;
  /** Follow wikilinks with a normal click/tap instead of requiring Cmd/Ctrl. */
  followLinksOnClick?: boolean;
  isFullHeight?: boolean;
  onToggleFullHeight?: () => void;
  findRequest?: number;
  insertTextRequest?: { id: number; text: string; at?: number } | null;
  interpretMarkdownRequest?: number;
  onTextSelectionChange?: (hasSelection: boolean) => void;
  attachments?: NoteAttachment[];
  onAttachmentAction?: (id: string, action: AttachmentAction) => void;
  onAttachmentDrop?: (paths: string[], at: number) => void;
  onRequestAttachments?: () => void;
}

export function MarkdownEditor({
  noteId,
  initialContent,
  getLinkableTitles,
  isTitleResolved,
  onChange,
  onFollowLink,
  readOnly = false,
  autoFocus = true,
  placeholderText = "Start writing… the first line becomes the title.",
  firstLineIsTitle = true,
  followLinksOnClick = false,
  isFullHeight = false,
  onToggleFullHeight,
  findRequest = 0,
  insertTextRequest = null,
  interpretMarkdownRequest = 0,
  onTextSelectionChange,
  attachments = [],
  onAttachmentAction,
  onAttachmentDrop,
  onRequestAttachments,
}: MarkdownEditorProps) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const linkPopoverRef = useRef<HTMLDivElement>(null);
  const imagePopoverRef = useRef<HTMLDivElement>(null);
  const pastePopoverRef = useRef<HTMLDivElement>(null);
  const replaceImageInputRef = useRef<HTMLInputElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const selectedImageElementRef = useRef<HTMLElement | null>(null);
  const selectedImageEditorRef = useRef<HTMLElement | null>(null);
  const copiedLinkResetRef = useRef<number | null>(null);
  const copiedImageResetRef = useRef<number | null>(null);
  const applyingExternalContentRef = useRef(false);
  const readOnlyCompartmentRef = useRef(new Compartment());
  const markdownLanguageCompartmentRef = useRef(new Compartment());
  const markdownTypingEnabledRef = useRef(loadMarkdownTypingEnabled());
  const [tableDialogOpen, setTableDialogOpen] = useState(false);
  const [linkDialogSelection, setLinkDialogSelection] = useState<{
    from: number;
    to: number;
    label: string;
  } | null>(null);
  const [linkPopover, setLinkPopover] = useState<LinkPopoverState | null>(null);
  const [editUrl, setEditUrl] = useState<string | null>(null);
  const [editUrlError, setEditUrlError] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);
  const [editorMode, setEditorMode] = useState<EditorMode>(loadEditorMode);
  const [pastePopover, setPastePopover] = useState<PastePopoverState | null>(null);
  const [imagePopover, setImagePopover] = useState<ImagePopoverState | null>(null);
  const [editImageAlt, setEditImageAlt] = useState<string | null>(null);
  const [copiedImage, setCopiedImage] = useState(false);
  const [hasTextSelection, setHasTextSelection] = useState(false);

  const dismissLinkPopover = () => {
    setLinkPopover(null);
    setEditUrl(null);
    setEditUrlError(false);
    setCopiedLink(false);
  };

  const dismissPastePopover = () => setPastePopover(null);

  const dismissImagePopover = () => {
    selectedImageElementRef.current?.classList.remove("cm-image-selected");
    selectedImageEditorRef.current?.classList.remove(
      "cm-image-selection-active",
    );
    selectedImageElementRef.current = null;
    selectedImageEditorRef.current = null;
    setImagePopover(null);
    setEditImageAlt(null);
    setCopiedImage(false);
  };

  const closePastePopover = () => {
    dismissPastePopover();
    viewRef.current?.focus();
  };

  const showLinkPopover = (
    link: ExternalLinkMatch,
    anchor: { element: HTMLElement },
  ) => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const position = editorPopoverPosition(
      wrapper.getBoundingClientRect(),
      anchor.element.getBoundingClientRect(),
      280,
    );
    setEditUrl(null);
    setEditUrlError(false);
    setCopiedLink(false);
    dismissPastePopover();
    dismissImagePopover();
    setLinkPopover({
      link,
      target: anchor.element,
      ...position,
    });
  };

  const showImagePopover = (
    image: EditorImageMatch,
    anchor: { element: HTMLElement },
  ) => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const positionTarget =
      anchor.element.querySelector<HTMLElement>(".cm-image-preview-media") ??
      anchor.element;
    const position = editorPopoverPosition(
      wrapper.getBoundingClientRect(),
      positionTarget.getBoundingClientRect(),
      300,
      "center",
    );
    dismissLinkPopover();
    dismissPastePopover();
    selectedImageElementRef.current?.classList.remove("cm-image-selected");
    selectedImageEditorRef.current?.classList.remove(
      "cm-image-selection-active",
    );
    const editor = anchor.element.closest<HTMLElement>(".cm-editor");
    anchor.element.classList.add("cm-image-selected");
    editor?.classList.add("cm-image-selection-active");
    selectedImageElementRef.current = anchor.element;
    selectedImageEditorRef.current = editor;
    setEditImageAlt(null);
    setCopiedImage(false);
    setImagePopover({
      image,
      target: positionTarget,
      ...position,
    });
  };

  const showPastePopover = (session: PasteChoiceSession) => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    dismissLinkPopover();
    dismissImagePopover();
    const bounds = wrapper.getBoundingClientRect();
    const width = Math.min(260, Math.max(220, bounds.width - 24));
    const estimatedHeight = 42 + session.choices.length * 48;
    const below = session.anchor.bottom - bounds.top + 8;
    const top =
      below + estimatedHeight <= bounds.height - 12
        ? below
        : Math.max(12, below - estimatedHeight - 24);
    setPastePopover({
      ...session,
      left: Math.min(
        Math.max(12, session.anchor.left - bounds.left),
        Math.max(12, bounds.width - width - 12),
      ),
      top,
      width,
    });
  };

  const openLinkDialog = (view: EditorView) => {
    const { from, to } = view.state.selection.main;
    dismissLinkPopover();
    dismissPastePopover();
    dismissImagePopover();
    setLinkDialogSelection({
      from,
      to,
      label: view.state.sliceDoc(from, to),
    });
  };

  // Keep latest callbacks without recreating the editor
  const callbacksRef = useRef({
    getLinkableTitles,
    isTitleResolved,
    onChange,
    onFollowLink,
    attachments,
    onAttachmentAction,
    onAttachmentDrop,
    onTextSelectionChange,
  });
  callbacksRef.current = {
    getLinkableTitles,
    isTitleResolved,
    onChange,
    onFollowLink,
    attachments,
    onAttachmentAction,
    onAttachmentDrop,
    onTextSelectionChange,
  };

  useEffect(() => {
    if (!containerRef.current) return;
    const initialEditorMode = loadEditorMode();
    setEditorMode(initialEditorMode);

    const state = EditorState.create({
      doc: initialContent,
      extensions: [
        pasteHistoryTracking,
        history({ joinToEvent: joinEditorHistoryEvent }),
        findInNoteExtension,
        keymap.of([
          {
            key: "Mod-b",
            run: (view) => {
              if (view.state.readOnly) return false;
              toggleInlineMarkup(view, "**", "bold text");
              return true;
            },
          },
          {
            key: "Mod-i",
            run: (view) => {
              if (view.state.readOnly) return false;
              toggleInlineMarkup(view, "*", "italic text");
              return true;
            },
          },
          {
            key: "Mod-Shift-t",
            run: (view) => {
              if (view.state.readOnly) return false;
              setTableDialogOpen(true);
              return true;
            },
          },
          {
            key: "Mod-k",
            run: (view) => {
              if (view.state.readOnly) return false;
              openLinkDialog(view);
              return true;
            },
          },
          ...([1, 2, 3] as const).map((level) => ({
            key: `Mod-Alt-${level}`,
            run: (view: EditorView) => {
              if (view.state.readOnly) return false;
              setHeadingLevel(view, level);
              return true;
            },
          })),
          indentWithTab,
          ...defaultKeymap,
          ...historyKeymap,
          ...completionKeymap,
        ]),
        markdownLanguageCompartmentRef.current.of(
          markdown({ base: markdownLanguage, extensions: GFM }),
        ),
        markdownListIndentation,
        markdownEditingMechanics,
        literalMarkdownSymbolTyping(() => markdownTypingEnabledRef.current),
        markdownHighlighting,
        firstLineIsTitle ? titleLineExtension : [],
        livePreviewExtension({
          initialMode: initialEditorMode,
          markdownTypingEnabled: () => markdownTypingEnabledRef.current,
          onOpen: (url) => void openExternalUrl(url),
          onModeChange: saveEditorMode,
          onSelect: showLinkPopover,
          onDismiss: dismissLinkPopover,
        }),
        // Live-preview replacements can leave WebKit's native caret painted at
        // its previous DOM position. CodeMirror's caret layer stays tied to the
        // document selection as Markdown delimiters appear and disappear.
        drawSelection(),
        currentLineTripleClickSelection,
        editorTheme,
        EditorView.lineWrapping,
        readOnlyCompartmentRef.current.of([
          EditorState.readOnly.of(readOnly),
          EditorView.editable.of(!readOnly),
        ]),
        placeholder(placeholderText),
        inlineTagExtension,
        wikilinkExtension({
          isResolved: (title) => callbacksRef.current.isTitleResolved(title),
          onFollow: (title) => callbacksRef.current.onFollowLink(title),
          followOnClick: followLinksOnClick,
        }),
        wikilinkAutocomplete(() => callbacksRef.current.getLinkableTitles()),
        imagePreviewExtension({
          getUrl: getImageUrl,
          onSelect: showImagePopover,
          onOpen: (image) => {
            dismissImagePopover();
            void openImageInDefaultApp(image.path);
          },
          onDismiss: dismissImagePopover,
        }),
        imagePasteExtension(savePastedImage),
        pasteOptionsExtension({
          onShow: showPastePopover,
          onDismiss: dismissPastePopover,
        }),
        attachmentCardExtension({
          getAttachment: (id) =>
            callbacksRef.current.attachments.find(
              (attachment) => attachment.id === id,
            ) ?? null,
          onAction: (id, action) =>
            callbacksRef.current.onAttachmentAction?.(id, action),
        }),
        richCopyExtension(firstLineIsTitle),
        EditorView.updateListener.of((update) => {
          if (update.selectionSet) {
            const selected = update.state.selection.ranges.some(
              (range) => !range.empty,
            );
            setHasTextSelection(selected);
            callbacksRef.current.onTextSelectionChange?.(selected);
          }
          if (update.docChanged && !applyingExternalContentRef.current) {
            dismissLinkPopover();
            dismissImagePopover();
            dismissPastePopover();
            callbacksRef.current.onChange(update.state.doc.toString());
          }
        }),
      ],
    });

    const view = new EditorView({ state, parent: containerRef.current });
    viewRef.current = view;
    if (autoFocus) view.focus();
    let disposed = false;
    void import("@codemirror/language-data")
      .then(({ languages }) => {
        if (disposed || viewRef.current !== view) return;
        view.dispatch({
          effects: markdownLanguageCompartmentRef.current.reconfigure(
            markdown({
              base: markdownLanguage,
              codeLanguages: languages,
              extensions: GFM,
            }),
          ),
        });
      })
      .catch(() => {
        // Markdown editing remains available if an optional language chunk
        // cannot be loaded.
      });

    return () => {
      disposed = true;
      view.destroy();
      viewRef.current = null;
    };
    // Recreate the editor only when switching notes; content edits flow
    // outward through the update listener, never back in.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [noteId]);

  useEffect(() => {
    if (!interpretMarkdownRequest) return;
    const view = viewRef.current;
    if (view && !view.state.readOnly) interpretSelectionAsMarkdown(view);
  }, [interpretMarkdownRequest]);

  useEffect(() => {
    const view = viewRef.current;
    if (!view) return;
    const current = view.state.doc.toString();
    if (current === initialContent) return;

    let prefix = 0;
    const prefixLimit = Math.min(current.length, initialContent.length);
    while (prefix < prefixLimit && current[prefix] === initialContent[prefix]) {
      prefix += 1;
    }
    let currentSuffix = current.length;
    let nextSuffix = initialContent.length;
    while (
      currentSuffix > prefix &&
      nextSuffix > prefix &&
      current[currentSuffix - 1] === initialContent[nextSuffix - 1]
    ) {
      currentSuffix -= 1;
      nextSuffix -= 1;
    }

    applyingExternalContentRef.current = true;
    try {
      view.dispatch({
        changes: {
          from: prefix,
          to: currentSuffix,
          insert: initialContent.slice(prefix, nextSuffix),
        },
      });
    } finally {
      applyingExternalContentRef.current = false;
    }
  }, [initialContent]);

  useEffect(() => {
    const view = viewRef.current;
    if (!view) return;
    view.dispatch({
      effects: readOnlyCompartmentRef.current.reconfigure([
        EditorState.readOnly.of(readOnly),
        EditorView.editable.of(!readOnly),
      ]),
    });
  }, [readOnly]);

  useEffect(() => {
    const handleEditorModeChange = (event: Event) => {
      const mode = (event as CustomEvent<EditorMode>).detail;
      if (mode !== "clean" && mode !== "markdown-aware") return;
      setEditorMode(mode);
      const view = viewRef.current;
      if (view) setEditorPresentationMode(view, mode);
    };
    window.addEventListener(EDITOR_MODE_CHANGE_EVENT, handleEditorModeChange);
    return () => {
      window.removeEventListener(
        EDITOR_MODE_CHANGE_EVENT,
        handleEditorModeChange,
      );
    };
  }, []);

  useEffect(
    () => () => {
      if (copiedLinkResetRef.current != null) {
        window.clearTimeout(copiedLinkResetRef.current);
      }
      if (copiedImageResetRef.current != null) {
        window.clearTimeout(copiedImageResetRef.current);
      }
    },
    [],
  );

  useEffect(() => {
    const handleMarkdownTypingChange = (event: Event) => {
      const enabled = (event as CustomEvent<boolean>).detail;
      if (typeof enabled !== "boolean") return;
      markdownTypingEnabledRef.current = enabled;
    };
    window.addEventListener(
      MARKDOWN_TYPING_CHANGE_EVENT,
      handleMarkdownTypingChange,
    );
    return () => {
      window.removeEventListener(
        MARKDOWN_TYPING_CHANGE_EVENT,
        handleMarkdownTypingChange,
      );
    };
  }, []);

  useEffect(() => {
    if (!linkPopover) return;
    const editorScroller = viewRef.current?.scrollDOM;
    const dismissOnPointerDown = (event: MouseEvent) => {
      if (linkPopoverRef.current?.contains(event.target as Node)) return;
      if (
        event.target instanceof Element &&
        event.target.closest(".cm-external-link")
      ) {
        return;
      }
      dismissLinkPopover();
    };
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && editUrl == null) dismissLinkPopover();
    };
    const updatePosition = () => {
      const wrapper = wrapperRef.current;
      if (!wrapper) return;
      setLinkPopover((current) => {
        if (!current || !current.target.isConnected) return null;
        const position = editorPopoverPosition(
          wrapper.getBoundingClientRect(),
          current.target.getBoundingClientRect(),
          280,
        );
        if (
          position.left === current.left &&
          position.top === current.top &&
          position.width === current.width
        ) {
          return current;
        }
        return { ...current, ...position };
      });
    };

    document.addEventListener("mousedown", dismissOnPointerDown);
    window.addEventListener("resize", updatePosition);
    editorScroller?.addEventListener("scroll", updatePosition, { passive: true });
    window.addEventListener("keydown", dismissOnEscape);
    return () => {
      document.removeEventListener("mousedown", dismissOnPointerDown);
      window.removeEventListener("resize", updatePosition);
      editorScroller?.removeEventListener("scroll", updatePosition);
      window.removeEventListener("keydown", dismissOnEscape);
    };
  }, [editUrl, linkPopover]);

  useEffect(() => {
    if (!imagePopover) return;
    const editorScroller = viewRef.current?.scrollDOM;
    const dismissOnPointerDown = (event: PointerEvent) => {
      if (
        !shouldDismissImagePopover(
          event.composedPath(),
          imagePopoverRef.current,
          selectedImageElementRef.current,
        )
      ) return;
      dismissImagePopover();
    };
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && editImageAlt == null) {
        dismissImagePopover();
      }
    };
    const updatePosition = () => {
      const wrapper = wrapperRef.current;
      if (!wrapper) return;
      setImagePopover((current) => {
        if (!current || !current.target.isConnected) return null;
        const position = editorPopoverPosition(
          wrapper.getBoundingClientRect(),
          current.target.getBoundingClientRect(),
          300,
          "center",
        );
        if (
          position.left === current.left &&
          position.top === current.top &&
          position.width === current.width
        ) {
          return current;
        }
        return { ...current, ...position };
      });
    };
    document.addEventListener("pointerdown", dismissOnPointerDown, true);
    window.addEventListener("keydown", dismissOnEscape);
    window.addEventListener("resize", updatePosition);
    editorScroller?.addEventListener("scroll", updatePosition, { passive: true });
    return () => {
      document.removeEventListener("pointerdown", dismissOnPointerDown, true);
      window.removeEventListener("keydown", dismissOnEscape);
      window.removeEventListener("resize", updatePosition);
      editorScroller?.removeEventListener("scroll", updatePosition);
    };
  }, [editImageAlt, imagePopover]);

  useEffect(() => {
    if (!pastePopover) return;
    const editorContainer = containerRef.current;
    const dismissOnPointerDown = (event: MouseEvent) => {
      if (pastePopoverRef.current?.contains(event.target as Node)) return;
      dismissPastePopover();
    };
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismissPastePopover();
    };
    const focusPasteOptions = (event: KeyboardEvent) => {
      if (
        event.key !== "Tab" ||
        event.shiftKey ||
        !containerRef.current?.contains(document.activeElement)
      ) {
        return;
      }
      const selected =
        pastePopoverRef.current?.querySelector<HTMLButtonElement>(
          '[role="menuitemradio"][aria-checked="true"]',
        ) ??
        pastePopoverRef.current?.querySelector<HTMLButtonElement>(
          '[role="menuitemradio"]',
        );
      if (!selected) return;
      event.preventDefault();
      event.stopPropagation();
      selected.focus();
    };
    const dismissOnViewportChange = () => dismissPastePopover();

    document.addEventListener("mousedown", dismissOnPointerDown);
    window.addEventListener("keydown", focusPasteOptions, true);
    window.addEventListener("keydown", dismissOnEscape);
    window.addEventListener("resize", dismissOnViewportChange);
    editorContainer?.addEventListener("scroll", dismissOnViewportChange);
    return () => {
      document.removeEventListener("mousedown", dismissOnPointerDown);
      window.removeEventListener("keydown", focusPasteOptions, true);
      window.removeEventListener("keydown", dismissOnEscape);
      window.removeEventListener("resize", dismissOnViewportChange);
      editorContainer?.removeEventListener("scroll", dismissOnViewportChange);
    };
  }, [pastePopover]);

  useEffect(() => {
    if (!isTauri()) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .onDragDropEvent(async ({ payload }) => {
        if (
          payload.type !== "drop" ||
          !callbacksRef.current.onAttachmentDrop ||
          viewRef.current?.state.readOnly
        ) {
          return;
        }
        const paths = payload.paths.filter(
          (path) => !isImageAttachmentPath(path),
        );
        if (!paths.length) return;
        const view = viewRef.current;
        const container = containerRef.current;
        if (!view || !container) return;
        const scale = await getCurrentWindow().scaleFactor();
        const point = {
          x: payload.position.x / scale,
          y: payload.position.y / scale,
        };
        const bounds = container.getBoundingClientRect();
        if (
          point.x < bounds.left ||
          point.x > bounds.right ||
          point.y < bounds.top ||
          point.y > bounds.bottom
        ) {
          return;
        }
        const at = view.posAtCoords(point) ?? view.state.selection.main.from;
        callbacksRef.current.onAttachmentDrop(paths, at);
      })
      .then((stop) => {
        if (disposed) stop();
        else unlisten = stop;
      });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    const handleFindShortcut = (event: KeyboardEvent) => {
      if (
        event.defaultPrevented ||
        (!event.metaKey && !event.ctrlKey) ||
        event.shiftKey ||
        event.altKey ||
        event.key.toLowerCase() !== "f"
      ) {
        return;
      }

      const view = viewRef.current;
      if (!view) return;
      event.preventDefault();
      openFindInNote(view);
    };

    window.addEventListener("keydown", handleFindShortcut);
    return () => window.removeEventListener("keydown", handleFindShortcut);
  }, []);

  useEffect(() => {
    if (findRequest === 0) return;
    const frame = requestAnimationFrame(() => {
      const view = viewRef.current;
      if (view) openFindInNote(view);
    });
    return () => cancelAnimationFrame(frame);
  }, [findRequest]);

  useEffect(() => {
    const view = viewRef.current;
    if (!view || !insertTextRequest || view.state.readOnly) return;
    const requestedAt = insertTextRequest.at;
    const position = Math.min(requestedAt ?? 0, view.state.doc.length);
    const { from, to } = requestedAt == null
      ? view.state.selection.main
      : { from: position, to: position };
    view.dispatch({
      changes: { from, to, insert: insertTextRequest.text },
      selection: EditorSelection.cursor(from + insertTextRequest.text.length),
    });
    view.focus();
  }, [insertTextRequest]);

  const handleInsertTable = (columns: number, rows: number) => {
    const view = viewRef.current;
    setTableDialogOpen(false);
    if (view) {
      requestAnimationFrame(() => insertMarkdownTable(view, columns, rows));
    }
  };

  const handleInsertLink = (label: string, url: string) => {
    const view = viewRef.current;
    const selection = linkDialogSelection;
    setLinkDialogSelection(null);
    if (!view || !selection) return;
    const markdownLink = formatMarkdownLink(label, url);
    view.dispatch({
      changes: {
        from: selection.from,
        to: selection.to,
        insert: markdownLink,
      },
      selection: EditorSelection.cursor(selection.from + markdownLink.length),
    });
    requestAnimationFrame(() => view.focus());
  };

  const linkSourceUrl = () => {
    const view = viewRef.current;
    if (!view || !linkPopover) return "";
    return view.state.sliceDoc(
      linkPopover.link.urlFrom,
      linkPopover.link.urlTo,
    );
  };

  const beginEditingLink = () => {
    setEditUrl(linkSourceUrl());
    setEditUrlError(false);
  };

  const saveEditedLink = () => {
    const view = viewRef.current;
    if (!view || !linkPopover || editUrl == null) return;
    const value = editUrl.trim();
    if (!/^https?:\/\/\S+$/i.test(value)) {
      setEditUrlError(true);
      return;
    }
    view.dispatch({
      changes: {
        from: linkPopover.link.urlFrom,
        to: linkPopover.link.urlTo,
        insert: value,
      },
    });
    dismissLinkPopover();
    view.focus();
  };

  const copyActiveLink = async () => {
    if (!linkPopover) return;
    try {
      await navigator.clipboard.writeText(linkPopover.link.url);
      setCopiedLink(true);
      if (copiedLinkResetRef.current != null) {
        window.clearTimeout(copiedLinkResetRef.current);
      }
      copiedLinkResetRef.current = window.setTimeout(
        () => setCopiedLink(false),
        1200,
      );
    } catch {
      setCopiedLink(false);
    }
  };

  const removeActiveLink = () => {
    const view = viewRef.current;
    if (!view || !linkPopover || linkPopover.link.kind !== "markdown") return;
    const label = view.state.sliceDoc(
      linkPopover.link.labelFrom,
      linkPopover.link.labelTo,
    );
    view.dispatch({
      changes: {
        from: linkPopover.link.from,
        to: linkPopover.link.to,
        insert: label,
      },
      selection: EditorSelection.cursor(linkPopover.link.from + label.length),
    });
    dismissLinkPopover();
    view.focus();
  };

  const activeImageMarkdown = () => {
    const view = viewRef.current;
    if (!view || !imagePopover) return "";
    return view.state.sliceDoc(
      imagePopover.image.from,
      imagePopover.image.to,
    );
  };

  const restoreRemovedImage = async (
    trashedId: string | null,
    markdown: string,
    position: number,
  ) => {
    if (trashedId && !(await restoreTrashedImage(trashedId, { reattach: false }))) {
      toast.error("The image could not be restored from Trash.");
      return;
    }
    const view = viewRef.current;
    if (!view) return;
    const at = Math.min(position, view.state.doc.length);
    view.dispatch({
      changes: { from: at, insert: markdown },
      selection: EditorSelection.cursor(at + markdown.length),
    });
    view.focus();
  };

  const removeActiveImage = async () => {
    const view = viewRef.current;
    if (!view || !imagePopover) return;
    const { image } = imagePopover;
    const markdown = activeImageMarkdown();
    if (!markdown) return;
    try {
      const result = await trashImageForNote(noteId, image.path, markdown);
      if (!imageEditIsCurrent(viewRef.current, view, image, markdown)) {
        if (
          result.kind === "trashed" &&
          !(await restoreTrashedImage(result.image.id, { reattach: false }))
        ) {
          toast.error("The image changed while it was being removed and could not be restored.");
          return;
        }
        toast.error("The note changed before the image could be removed.");
        return;
      }
      view.dispatch({
        changes: { from: image.from, to: image.to },
        selection: EditorSelection.cursor(image.from),
      });
      dismissImagePopover();
      const trashedId = result.kind === "trashed" ? result.image.id : null;
      const message = result.kind === "trashed"
        ? "Image moved to Trash"
        : result.kind === "shared"
          ? "Image removed · still used by another note"
          : "Image reference removed";
      toast(message, {
        action: {
          label: "Undo",
          onClick: () => void restoreRemovedImage(
            trashedId,
            markdown,
            image.from,
          ),
        },
      });
      view.focus();
    } catch {
      toast.error("The image could not be removed.");
    }
  };

  const saveImageAlt = () => {
    const view = viewRef.current;
    if (!view || !imagePopover || editImageAlt == null) return;
    const { image } = imagePopover;
    const markdown = formatImageMarkdown(
      editImageAlt.replace(/[\r\n\]]+/g, " ").trim(),
      image.width,
      image.path,
    );
    view.dispatch({ changes: { from: image.from, to: image.to, insert: markdown } });
    dismissImagePopover();
    view.focus();
  };

  const copyActiveImage = async () => {
    if (!imagePopover) return;
    const copied = await copyImageToClipboard(imagePopover.image.path);
    setCopiedImage(copied);
    if (!copied) toast.error("The image could not be copied.");
    else {
      if (copiedImageResetRef.current != null) {
        window.clearTimeout(copiedImageResetRef.current);
      }
      copiedImageResetRef.current = window.setTimeout(
        () => setCopiedImage(false),
        1200,
      );
    }
  };

  const replaceActiveImage = async (file: File | undefined) => {
    if (!file || !file.type.startsWith("image/") || !imagePopover) return;
    const view = viewRef.current;
    if (!view) return;
    const { image } = imagePopover;
    const oldMarkdown = activeImageMarkdown();
    let nextPath: string | null = null;
    try {
      nextPath = await savePastedImage(
        new Uint8Array(await file.arrayBuffer()),
        file.type,
      );
    } catch {
      toast.error("The replacement image could not be read.");
      return;
    }
    if (!nextPath) return;
    const nextMarkdown = formatImageMarkdown(
      image.alt || file.name.replace(/\.[^.]+$/, ""),
      image.width,
      nextPath,
    );
    if (!imageEditIsCurrent(viewRef.current, view, image, oldMarkdown)) {
      await discardUnsavedImage(nextPath);
      toast.error("The note changed before the image could be replaced.");
      return;
    }
    let result: Awaited<ReturnType<typeof trashImageForNote>> | null = null;
    try {
      result = await trashImageForNote(noteId, image.path, oldMarkdown);
      if (!imageEditIsCurrent(viewRef.current, view, image, oldMarkdown)) {
        if (
          result.kind === "trashed" &&
          !(await restoreTrashedImage(result.image.id, { reattach: false }))
        ) {
          toast.error("The image changed during replacement and could not be restored.");
        } else {
          toast.error("The note changed before the image could be replaced.");
        }
        await discardUnsavedImage(nextPath);
        return;
      }
      view.dispatch({
        changes: {
          from: image.from,
          to: image.to,
          insert: nextMarkdown,
        },
      });
      dismissImagePopover();
      if (result.kind === "trashed") {
        const trashedImageId = result.image.id;
        toast("Previous image moved to Trash", {
          action: {
            label: "Undo",
            onClick: async () => {
              const current = viewRef.current;
              if (!current) return;
              const from = Math.min(image.from, current.state.doc.length);
              const to = Math.min(from + nextMarkdown.length, current.state.doc.length);
              if (current.state.sliceDoc(from, to) !== nextMarkdown) return;
              if (!(await restoreTrashedImage(trashedImageId, { reattach: false }))) return;
              if (
                viewRef.current !== current ||
                current.state.sliceDoc(from, to) !== nextMarkdown
              ) {
                await trashImageForNote(noteId, image.path, oldMarkdown);
                return;
              }
              current.dispatch({ changes: { from, to, insert: oldMarkdown } });
              await discardUnsavedImage(nextPath);
            },
          },
        });
      }
      view.focus();
    } catch {
      if (result?.kind === "trashed") {
        await restoreTrashedImage(result.image.id, { reattach: false });
      }
      await discardUnsavedImage(nextPath);
      toast.error("The image could not be replaced.");
    }
  };

  const selectPasteChoice = (choice: PasteChoice) => {
    const view = viewRef.current;
    if (!view || !pastePopover) return;
    const next = applyPasteChoice(view, pastePopover, choice);
    setPastePopover({
      ...pastePopover,
      ...next,
    });
    view.focus();
  };

  const movePasteMenuFocus = (
    event: React.KeyboardEvent<HTMLDivElement>,
  ) => {
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      return;
    }
    const items = [...event.currentTarget.querySelectorAll<HTMLButtonElement>(
      '[role="menuitemradio"]',
    )];
    if (items.length === 0) return;

    event.preventDefault();
    const current = items.indexOf(document.activeElement as HTMLButtonElement);
    const next =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? items.length - 1
          : event.key === "ArrowUp"
            ? current <= 0
              ? items.length - 1
              : current - 1
            : current < 0 || current === items.length - 1
              ? 0
              : current + 1;
    items[next].focus();
  };

  const withEditor = (action: (view: EditorView) => void) => () => {
    const view = viewRef.current;
    if (view && !view.state.readOnly) action(view);
  };

  const formattingActions = [
    {
      label: "Bold",
      shortcut: "Ctrl/⌘+B",
      icon: Bold,
      action: withEditor((view) => toggleInlineMarkup(view, "**", "bold text")),
    },
    {
      label: "Italic",
      shortcut: "Ctrl/⌘+I",
      icon: Italic,
      action: withEditor((view) => toggleInlineMarkup(view, "*", "italic text")),
    },
    {
      label: "Strikethrough",
      icon: Strikethrough,
      action: withEditor((view) => toggleInlineMarkup(view, "~~", "strikethrough text")),
    },
    {
      label: "Heading 1",
      shortcut: "Ctrl/⌘+Alt/⌥+1",
      icon: Heading1,
      action: withEditor((view) => setHeadingLevel(view, 1)),
    },
    {
      label: "Heading 2",
      shortcut: "Ctrl/⌘+Alt/⌥+2",
      icon: Heading2,
      action: withEditor((view) => setHeadingLevel(view, 2)),
    },
    {
      label: "Heading 3",
      shortcut: "Ctrl/⌘+Alt/⌥+3",
      icon: Heading3,
      action: withEditor((view) => setHeadingLevel(view, 3)),
    },
    {
      label: "Bulleted list",
      icon: List,
      action: withEditor((view) => toggleLinePrefix(view, "- ", /^[-*+]\s/)),
    },
    {
      label: "Numbered list",
      icon: ListOrdered,
      action: withEditor((view) => toggleLinePrefix(view, (index) => `${index + 1}. `, /^\d+\.\s/)),
    },
    {
      label: "Increase indent",
      shortcut: "Tab",
      icon: IndentIncrease,
      action: withEditor((view) => {
        indentMore(view);
        view.focus();
      }),
    },
    {
      label: "Decrease indent",
      shortcut: "Shift+Tab",
      icon: IndentDecrease,
      action: withEditor((view) => {
        indentLess(view);
        view.focus();
      }),
    },
    {
      label: "Quote",
      icon: Quote,
      action: withEditor((view) => toggleLinePrefix(view, "> ", /^>\s/)),
    },
    {
      label: "Inline code",
      icon: Code2,
      action: withEditor((view) => toggleInlineMarkup(view, "`", "code")),
    },
    {
      label: "Link",
      shortcut: "Ctrl/⌘+K",
      icon: Link,
      action: withEditor(openLinkDialog),
    },
    {
      label: "Interpret as Markdown",
      icon: Sparkles,
      action: withEditor(interpretSelectionAsMarkdown),
      requiresSelection: true,
    },
  ];

  return (
    <div ref={wrapperRef} className="relative flex h-full min-h-0 flex-col">
      <div
        className="cm-editor-toolbar relative z-20 flex h-9 shrink-0 items-center gap-0.5 overflow-x-auto border-b border-border/40 bg-zerus-editor px-4"
        role="toolbar"
        aria-label="Text formatting"
      >
        {formattingActions.map(({ label, shortcut, icon: Icon, action, requiresSelection }) => (
          <Button
            key={label}
            type="button"
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0 text-muted-foreground"
            title={`${label}${shortcut ? ` (${shortcut})` : ""}`}
            aria-label={label}
            disabled={readOnly || (requiresSelection === true && !hasTextSelection)}
            onClick={action}
          >
            <Icon size={15} />
          </Button>
        ))}
        {onRequestAttachments && (
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0 text-muted-foreground"
            title="Attach files"
            aria-label="Attach files"
            disabled={readOnly}
            onClick={onRequestAttachments}
          >
            <Paperclip size={15} />
          </Button>
        )}
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0 text-muted-foreground"
          title="Find in note (Ctrl/⌘+F)"
          aria-label="Find in note"
          onClick={() => {
            const view = viewRef.current;
            if (view) openFindInNote(view);
          }}
        >
          <Search size={15} />
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0 text-muted-foreground"
          title="Insert table (Ctrl/⌘+Shift+T)"
          aria-label="Insert Markdown table"
          disabled={readOnly}
          onClick={() => setTableDialogOpen(true)}
        >
          <Table2 size={15} />
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0 text-muted-foreground"
          title={
            editorMode === "clean"
              ? "Switch to Markdown-aware mode (Ctrl/⌘+E)"
              : "Switch to clean mode (Ctrl/⌘+E)"
          }
          aria-label={
            editorMode === "clean"
              ? "Switch to Markdown-aware mode"
              : "Switch to clean mode"
          }
          aria-pressed={editorMode === "markdown-aware"}
          onClick={() => {
            const view = viewRef.current;
            if (!view) return;
            saveEditorMode(toggleEditorPresentationMode(view));
            view.focus();
          }}
        >
          <Markdown size={15} />
        </Button>
        {onToggleFullHeight && (
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="ml-auto h-7 w-7 shrink-0 text-muted-foreground"
            title={isFullHeight ? "Restore PDF and Markdown split" : "Expand Markdown to full height"}
            aria-label={isFullHeight ? "Restore PDF and Markdown split" : "Expand Markdown to full height"}
            aria-pressed={isFullHeight}
            onClick={onToggleFullHeight}
          >
            {isFullHeight ? <Minimize size={15} /> : <Maximize size={15} />}
          </Button>
        )}
      </div>
      <div ref={containerRef} className="min-h-0 flex-1 overflow-y-auto" />
      {pastePopover && (
        <PasteOptionsPopover
          state={pastePopover}
          elementRef={pastePopoverRef}
          onKeyDown={movePasteMenuFocus}
          onClose={closePastePopover}
          onSelect={selectPasteChoice}
        />
      )}
      <input
        ref={replaceImageInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        aria-hidden="true"
        tabIndex={-1}
        onChange={(event) => {
          void replaceActiveImage(event.currentTarget.files?.[0]);
          event.currentTarget.value = "";
        }}
      />
      {imagePopover && (
        <ImageActionsPopover
          state={imagePopover}
          elementRef={imagePopoverRef}
          readOnly={readOnly}
          editAlt={editImageAlt}
          copied={copiedImage}
          onEditAltChange={setEditImageAlt}
          onSaveAlt={saveImageAlt}
          onOpen={() => {
            void openImageInDefaultApp(imagePopover.image.path);
            dismissImagePopover();
          }}
          onReplace={() => replaceImageInputRef.current?.click()}
          onCopy={() => void copyActiveImage()}
          onRemove={() => void removeActiveImage()}
        />
      )}
      {linkPopover && (
        <LinkActionsPopover
          state={linkPopover}
          elementRef={linkPopoverRef}
          readOnly={readOnly}
          sourceUrl={linkSourceUrl()}
          editUrl={editUrl}
          editUrlError={editUrlError}
          copied={copiedLink}
          onEditUrlChange={setEditUrl}
          onClearEditError={() => setEditUrlError(false)}
          onSave={saveEditedLink}
          onOpen={() => {
            void openExternalUrl(linkPopover.link.url);
            dismissLinkPopover();
          }}
          onBeginEditing={beginEditingLink}
          onCopy={() => void copyActiveLink()}
          onRemove={removeActiveLink}
        />
      )}
      <TableSizeDialog
        open={tableDialogOpen}
        onOpenChange={setTableDialogOpen}
        onInsert={handleInsertTable}
      />
      <LinkDialog
        open={linkDialogSelection != null}
        initialLabel={linkDialogSelection?.label ?? ""}
        onOpenChange={(open) => {
          if (!open) {
            setLinkDialogSelection(null);
            requestAnimationFrame(() => viewRef.current?.focus());
          }
        }}
        onInsert={handleInsertLink}
      />
    </div>
  );
}
