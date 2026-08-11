import { useEffect, useRef, useState } from "react";
import { EditorView, placeholder, keymap } from "@codemirror/view";
import {
  ChangeSpec,
  Compartment,
  EditorSelection,
  EditorState,
} from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { languages } from "@codemirror/language-data";
import { history, defaultKeymap, historyKeymap } from "@codemirror/commands";
import { completionKeymap } from "@codemirror/autocomplete";
import {
  editorTheme,
  markdownHighlighting,
  titleLineExtension,
  wikilinkExtension,
  inlineTagExtension,
  wikilinkAutocomplete,
} from "./markdown-extensions";
import { imagePasteExtension, imagePreviewExtension } from "./image-extension";
import { livePreviewExtension } from "./live-preview";
import { getImageUrl, savePastedImage } from "@/store/notes-store";
import { Button } from "@/components/ui/button";
import {
  Bold,
  Code2,
  Heading1,
  Heading2,
  Heading3,
  Italic,
  Link,
  List,
  ListOrdered,
  Maximize,
  Minimize,
  Quote,
  Strikethrough,
  Table2,
} from "@/lib/icons";
import { insertMarkdownTable } from "./markdown-table";
import { TableSizeDialog } from "./TableSizeDialog";
import { openExternalUrl } from "@/lib/external-links";

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
  isFullHeight?: boolean;
  onToggleFullHeight?: () => void;
}

function toggleInlineMarkup(
  view: EditorView,
  marker: string,
  placeholder: string,
) {
  const { from, to } = view.state.selection.main;
  const selectedText = view.state.sliceDoc(from, to);
  const hasMarkup =
    selectedText.startsWith(marker) &&
    selectedText.endsWith(marker) &&
    selectedText.length >= marker.length * 2;

  if (hasMarkup) {
    const unwrappedText = selectedText.slice(marker.length, -marker.length);
    view.dispatch({
      changes: { from, to, insert: unwrappedText },
      selection: EditorSelection.range(from, from + unwrappedText.length),
    });
  } else {
    const content = selectedText || placeholder;
    const wrappedText = `${marker}${content}${marker}`;
    view.dispatch({
      changes: { from, to, insert: wrappedText },
      selection: EditorSelection.range(
        from + marker.length,
        from + marker.length + content.length,
      ),
    });
  }

  view.focus();
}

function toggleLinePrefix(
  view: EditorView,
  prefix: string | ((index: number) => string),
  prefixPattern: RegExp,
) {
  const { anchor, head, from, to } = view.state.selection.main;
  const firstLine = view.state.doc.lineAt(from);
  const lastPosition =
    to > from && view.state.doc.lineAt(to).from === to ? to - 1 : to;
  const lastLine = view.state.doc.lineAt(lastPosition);
  const lines = [];

  for (let lineNumber = firstLine.number; lineNumber <= lastLine.number; lineNumber += 1) {
    lines.push(view.state.doc.line(lineNumber));
  }

  const shouldRemovePrefix = lines.every((line) => prefixPattern.test(line.text));
  const changes = lines.map((line, index) => {
    if (shouldRemovePrefix) {
      const match = line.text.match(prefixPattern);
      return {
        from: line.from,
        to: line.from + (match?.[0].length ?? 0),
        insert: "",
      };
    }

    return {
      from: line.from,
      insert: typeof prefix === "function" ? prefix(index) : prefix,
    };
  });

  dispatchLineChanges(view, changes, anchor, head);
}

function dispatchLineChanges(
  view: EditorView,
  changes: ChangeSpec,
  anchor: number,
  head: number,
) {
  const changeSet = view.state.changes(changes);
  view.dispatch({
    changes: changeSet,
    selection: EditorSelection.range(
      changeSet.mapPos(anchor, 1),
      changeSet.mapPos(head, 1),
    ),
  });
  view.focus();
}

function setHeadingLevel(view: EditorView, level: 1 | 2 | 3) {
  const { anchor, head, from, to } = view.state.selection.main;
  const firstLine = view.state.doc.lineAt(from);
  const lastPosition =
    to > from && view.state.doc.lineAt(to).from === to ? to - 1 : to;
  const lastLine = view.state.doc.lineAt(lastPosition);
  const lines = [];
  const prefix = `${"#".repeat(level)} `;
  const headingPattern = /^#{1,6}\s/;

  for (let lineNumber = firstLine.number; lineNumber <= lastLine.number; lineNumber += 1) {
    lines.push(view.state.doc.line(lineNumber));
  }

  const shouldRemoveHeading = lines.every((line) => line.text.startsWith(prefix));
  const changes = lines.map((line) => {
    const existingHeading = line.text.match(headingPattern);

    if (shouldRemoveHeading) {
      return {
        from: line.from,
        to: line.from + (existingHeading?.[0].length ?? 0),
        insert: "",
      };
    }

    return {
      from: line.from,
      to: line.from + (existingHeading?.[0].length ?? 0),
      insert: prefix,
    };
  });

  dispatchLineChanges(view, changes, anchor, head);
}

function insertLink(view: EditorView) {
  const { from, to } = view.state.selection.main;
  const selectedText = view.state.sliceDoc(from, to) || "link text";
  const markdownLink = `[${selectedText}](url)`;
  const urlFrom = from + selectedText.length + 3;

  view.dispatch({
    changes: { from, to, insert: markdownLink },
    selection: EditorSelection.range(urlFrom, urlFrom + 3),
  });
  view.focus();
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
  isFullHeight = false,
  onToggleFullHeight,
}: MarkdownEditorProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const applyingExternalContentRef = useRef(false);
  const readOnlyCompartmentRef = useRef(new Compartment());
  const [tableDialogOpen, setTableDialogOpen] = useState(false);

  // Keep latest callbacks without recreating the editor
  const callbacksRef = useRef({
    getLinkableTitles,
    isTitleResolved,
    onChange,
    onFollowLink,
  });
  callbacksRef.current = {
    getLinkableTitles,
    isTitleResolved,
    onChange,
    onFollowLink,
  };

  useEffect(() => {
    if (!containerRef.current) return;

    const state = EditorState.create({
      doc: initialContent,
      extensions: [
        history(),
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
          ...defaultKeymap,
          ...historyKeymap,
          ...completionKeymap,
        ]),
        markdown({
          base: markdownLanguage,
          codeLanguages: languages,
          extensions: GFM,
        }),
        markdownHighlighting,
        firstLineIsTitle ? titleLineExtension : [],
        livePreviewExtension((url) => void openExternalUrl(url)),
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
        }),
        wikilinkAutocomplete(() => callbacksRef.current.getLinkableTitles()),
        imagePreviewExtension(getImageUrl),
        imagePasteExtension(savePastedImage),
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !applyingExternalContentRef.current) {
            callbacksRef.current.onChange(update.state.doc.toString());
          }
        }),
      ],
    });

    const view = new EditorView({ state, parent: containerRef.current });
    viewRef.current = view;
    if (autoFocus) view.focus();

    return () => {
      view.destroy();
      viewRef.current = null;
    };
    // Recreate the editor only when switching notes; content edits flow
    // outward through the update listener, never back in.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [noteId]);

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

  const handleInsertTable = (columns: number, rows: number) => {
    const view = viewRef.current;
    setTableDialogOpen(false);
    if (view) {
      requestAnimationFrame(() => insertMarkdownTable(view, columns, rows));
    }
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
      icon: Heading1,
      action: withEditor((view) => setHeadingLevel(view, 1)),
    },
    {
      label: "Heading 2",
      icon: Heading2,
      action: withEditor((view) => setHeadingLevel(view, 2)),
    },
    {
      label: "Heading 3",
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
      icon: Link,
      action: withEditor(insertLink),
    },
  ];

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div
        className="flex h-9 shrink-0 items-center gap-0.5 overflow-x-auto border-b border-border/40 px-4"
        role="toolbar"
        aria-label="Text formatting"
      >
        {formattingActions.map(({ label, shortcut, icon: Icon, action }) => (
          <Button
            key={label}
            type="button"
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0 text-muted-foreground"
            title={`${label}${shortcut ? ` (${shortcut})` : ""}`}
            aria-label={label}
            disabled={readOnly}
            onClick={action}
          >
            <Icon size={15} />
          </Button>
        ))}
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
      <TableSizeDialog
        open={tableDialogOpen}
        onOpenChange={setTableDialogOpen}
        onInsert={handleInsertTable}
      />
    </div>
  );
}
