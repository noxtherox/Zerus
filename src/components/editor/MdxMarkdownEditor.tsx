import { createContext, useContext, useEffect, useMemo, useRef } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  BlockTypeSelect,
  BoldItalicUnderlineToggles,
  ChangeCodeMirrorLanguage,
  CodeToggle,
  ConditionalContents,
  CreateLink,
  InsertCodeBlock,
  InsertImage,
  InsertTable,
  InsertThematicBreak,
  ListsToggle,
  MDXEditor,
  type MDXEditorMethods,
  Separator,
  UndoRedo,
  codeBlockPlugin,
  codeMirrorPlugin,
  frontmatterPlugin,
  headingsPlugin,
  imagePlugin,
  linkDialogPlugin,
  linkPlugin,
  listsPlugin,
  markdownShortcutPlugin,
  quotePlugin,
  searchPlugin,
  tablePlugin,
  thematicBreakPlugin,
  toolbarPlugin,
  useEditorSearch,
} from "@mdxeditor/editor";
import "@mdxeditor/editor/style.css";
import "./mdx-editor.css";
import {
  ChevronLeft,
  ChevronRight,
  Maximize,
  Minimize,
  Paperclip,
  Search,
  X,
} from "@/lib/icons";
import { getImageUrl, savePastedImage } from "@/store/notes-store";
import { isImageAttachmentPath, type NoteAttachment } from "@/lib/note-attachments";
import {
  consumeLocalMarkdownEcho,
  recordLocalMarkdownEcho,
} from "./mdx-sync";
import { prepareMarkdownForMdxEditor } from "./mdx-compat";
import { toast } from "sonner";

type AttachmentAction = "open" | "reveal" | "copy" | "external";

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
  followLinksOnClick?: boolean;
  isFullHeight?: boolean;
  onToggleFullHeight?: () => void;
  findRequest?: number;
  insertTextRequest?: { id: number; text: string; at?: number } | null;
  onTextSelectionChange?: (hasSelection: boolean) => void;
  attachments?: NoteAttachment[];
  onAttachmentAction?: (id: string, action: AttachmentAction) => void;
  onAttachmentDrop?: (paths: string[], at: number) => void;
  onRequestAttachments?: () => void;
}

interface ToolbarContextValue {
  findRequest: number;
  isFullHeight: boolean;
  onRequestAttachments?: () => void;
  onToggleFullHeight?: () => void;
}

const ToolbarContext = createContext<ToolbarContextValue>({
  findRequest: 0,
  isFullHeight: false,
});

function SearchControl() {
  const { findRequest } = useContext(ToolbarContext);
  const inputRef = useRef<HTMLInputElement>(null);
  const {
    closeSearch,
    cursor,
    isSearchOpen,
    next,
    openSearch,
    prev,
    search,
    setSearch,
    total,
  } = useEditorSearch();
  const previousRequest = useRef(findRequest);

  useEffect(() => {
    if (findRequest !== previousRequest.current) openSearch();
    previousRequest.current = findRequest;
  }, [findRequest, openSearch]);

  useEffect(() => {
    if (isSearchOpen) inputRef.current?.focus();
  }, [isSearchOpen]);

  if (isSearchOpen) {
    return (
      <div className="zerus-mdx-search">
        <Search size={14} aria-hidden="true" />
        <input
          ref={inputRef}
          value={search}
          aria-label="Search this note"
          placeholder="Find…"
          onChange={(event) => setSearch(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              if (event.shiftKey) prev();
              else next();
            } else if (event.key === "Escape") {
              event.preventDefault();
              closeSearch();
            }
          }}
        />
        <span className="zerus-mdx-search-count">
          {total ? `${cursor}/${total}` : "0/0"}
        </span>
        <button type="button" aria-label="Previous match" onClick={prev}>
          <ChevronLeft size={14} />
        </button>
        <button type="button" aria-label="Next match" onClick={next}>
          <ChevronRight size={14} />
        </button>
        <button type="button" aria-label="Close find" onClick={closeSearch}>
          <X size={14} />
        </button>
      </div>
    );
  }

  return (
    <button
      type="button"
      className="zerus-mdx-toolbar-action"
      title="Find in note"
      aria-label="Find in note"
      onClick={openSearch}
    >
      <Search size={16} />
    </button>
  );
}

function ZerusToolbarControls() {
  const {
    isFullHeight,
    onRequestAttachments,
    onToggleFullHeight,
  } = useContext(ToolbarContext);

  return (
    <>
      <SearchControl />
      {onRequestAttachments && (
        <button
          type="button"
          className="zerus-mdx-toolbar-action"
          title="Attach files"
          aria-label="Attach files"
          onClick={onRequestAttachments}
        >
          <Paperclip size={16} />
        </button>
      )}
      {onToggleFullHeight && (
        <button
          type="button"
          className="zerus-mdx-toolbar-action zerus-mdx-toolbar-action-end"
          title={isFullHeight ? "Restore preview split" : "Expand editor"}
          aria-label={isFullHeight ? "Restore preview split" : "Expand editor"}
          aria-pressed={isFullHeight}
          onClick={onToggleFullHeight}
        >
          {isFullHeight ? <Minimize size={16} /> : <Maximize size={16} />}
        </button>
      )}
    </>
  );
}

const editorPlugins = [
  headingsPlugin(),
  quotePlugin(),
  listsPlugin(),
  linkPlugin(),
  linkDialogPlugin(),
  imagePlugin({
    imageUploadHandler: async (file) => {
      const path = await savePastedImage(
        new Uint8Array(await file.arrayBuffer()),
        file.type,
      );
      if (!path) throw new Error("The image could not be saved.");
      return path;
    },
    imagePreviewHandler: async (source) => (await getImageUrl(source)) ?? source,
  }),
  tablePlugin(),
  thematicBreakPlugin(),
  frontmatterPlugin(),
  codeBlockPlugin({ defaultCodeBlockLanguage: "" }),
  codeMirrorPlugin({ codeBlockLanguages: [] }),
  markdownShortcutPlugin(),
  searchPlugin(),
  toolbarPlugin({
    toolbarClassName: "zerus-mdx-toolbar",
    toolbarContents: () => (
      <>
        <UndoRedo />
        <Separator />
        <BlockTypeSelect />
        <BoldItalicUnderlineToggles />
        <CodeToggle />
        <CreateLink />
        <ListsToggle />
        <Separator />
        <ConditionalContents
          options={[
            {
              when: (editor) => editor?.editorType === "codeblock",
              contents: () => <ChangeCodeMirrorLanguage />,
            },
            {
              fallback: () => (
                <>
                  <InsertTable />
                  <InsertImage />
                  <InsertThematicBreak />
                  <InsertCodeBlock />
                </>
              ),
            },
          ]}
        />
        <Separator />
        <ZerusToolbarControls />
      </>
    ),
  }),
];

export function MarkdownEditor({
  noteId,
  initialContent,
  onChange,
  readOnly = false,
  autoFocus = true,
  placeholderText = "Title",
  firstLineIsTitle = true,
  isFullHeight = false,
  onToggleFullHeight,
  findRequest = 0,
  insertTextRequest = null,
  onTextSelectionChange,
  onAttachmentAction,
  onAttachmentDrop,
  onRequestAttachments,
}: MarkdownEditorProps) {
  const editorRef = useRef<MDXEditorMethods>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const lastInsertRequest = useRef<number | null>(null);
  const pendingLocalEchoes = useRef<string[]>([]);

  const toolbarContext = useMemo<ToolbarContextValue>(
    () => ({
      findRequest,
      isFullHeight,
      onRequestAttachments,
      onToggleFullHeight,
    }),
    [findRequest, isFullHeight, onRequestAttachments, onToggleFullHeight],
  );

  useEffect(() => {
    pendingLocalEchoes.current = [];
  }, [noteId]);

  useEffect(() => {
    if (consumeLocalMarkdownEcho(pendingLocalEchoes.current, initialContent)) return;
    const editor = editorRef.current;
    const compatibleMarkdown = prepareMarkdownForMdxEditor(initialContent);
    if (!editor || editor.getMarkdown() === compatibleMarkdown) return;
    editor.setMarkdown(compatibleMarkdown);
  }, [initialContent]);

  useEffect(() => {
    if (
      !insertTextRequest ||
      lastInsertRequest.current === insertTextRequest.id ||
      readOnly
    ) {
      return;
    }
    lastInsertRequest.current = insertTextRequest.id;
    editorRef.current?.focus(() => {
      editorRef.current?.insertMarkdown(
        prepareMarkdownForMdxEditor(insertTextRequest.text),
      );
    });
  }, [insertTextRequest, readOnly]);

  useEffect(() => {
    if (!isTauri() || !onAttachmentDrop) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .onDragDropEvent(async ({ payload }) => {
        if (payload.type !== "drop" || readOnly) return;
        const paths = payload.paths.filter((path) => !isImageAttachmentPath(path));
        if (!paths.length) return;
        const scale = await getCurrentWindow().scaleFactor();
        const bounds = wrapperRef.current?.getBoundingClientRect();
        if (!bounds) return;
        const x = payload.position.x / scale;
        const y = payload.position.y / scale;
        if (x < bounds.left || x > bounds.right || y < bounds.top || y > bounds.bottom) return;
        onAttachmentDrop(paths, editorRef.current?.getMarkdown().length ?? 0);
      })
      .then((stop) => {
        if (disposed) stop();
        else unlisten = stop;
      });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [onAttachmentDrop, readOnly]);

  const reportSelection = () => {
    onTextSelectionChange?.(
      (editorRef.current?.getSelectionMarkdown().length ?? 0) > 0,
    );
  };

  const handleClick = (event: React.MouseEvent<HTMLDivElement>) => {
    const anchor = (event.target as Element).closest<HTMLAnchorElement>("a");
    const href = anchor?.getAttribute("href") ?? "";
    const attachment = href.match(/^zerus-attachment:([a-zA-Z0-9-]+)$/);
    if (!attachment || !onAttachmentAction) return;
    event.preventDefault();
    onAttachmentAction(attachment[1], "open");
  };

  return (
    <ToolbarContext.Provider value={toolbarContext}>
      <div
        ref={wrapperRef}
        className="zerus-mdx-shell"
        onClick={handleClick}
        onKeyUp={reportSelection}
        onPointerUp={reportSelection}
        onBlur={() => onTextSelectionChange?.(false)}
      >
        <MDXEditor
          key={noteId}
          ref={editorRef}
          markdown={prepareMarkdownForMdxEditor(initialContent)}
          plugins={editorPlugins}
          readOnly={readOnly}
          autoFocus={autoFocus}
          placeholder={placeholderText}
          className="zerus-mdx-editor"
          contentEditableClassName={`zerus-mdx-content${firstLineIsTitle ? " zerus-mdx-title-first-line" : ""}`}
          toMarkdownOptions={{ bullet: "-" }}
          onChange={(markdown, initialMarkdownNormalize) => {
            if (initialMarkdownNormalize) return;
            recordLocalMarkdownEcho(pendingLocalEchoes.current, markdown);
            onChange(markdown);
          }}
          onError={({ error }) => toast.error(`Markdown could not be opened: ${error}`)}
        />
      </div>
    </ToolbarContext.Provider>
  );
}
