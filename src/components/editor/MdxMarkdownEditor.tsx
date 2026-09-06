import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { createPortal } from "react-dom";
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
  thematicBreakPlugin,
  toolbarPlugin,
  useEditorSearch,
} from "@mdxeditor/editor";
import "@mdxeditor/editor/style.css";
import "./mdx-editor.css";
import {
  ChevronDown,
  ChevronUp,
  Copy,
  ExternalLink,
  FolderSearch,
  Maximize,
  Minimize,
  Paperclip,
  Search,
  X,
} from "@/lib/icons";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { getImageUrl, savePastedImage } from "@/store/notes-store";
import { isImageAttachmentPath, type NoteAttachment } from "@/lib/note-attachments";
import { fileManagerName } from "@/lib/desktop-platform";
import {
  consumeLocalMarkdownEcho,
  recordLocalMarkdownEcho,
} from "./mdx-sync";
import {
  cleanMarkdownFromMdxEditor,
  prepareMarkdownForMdxEditor,
} from "./mdx-compat";
import { preserveEmptyParagraphsPlugin } from "./empty-paragraphs";
import { linkDialogPositionPlugin } from "./link-dialog-position";
import {
  attachmentClickAction,
  attachmentIdFromHref,
} from "./attachment-link";
import {
  InsertElementTable,
} from "./element-table-controls";
import { EditorRecoveryBoundary } from "./editor-recovery";
import { elementTablePlugin } from "./element-table-plugin";

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
  searchContainer: HTMLDivElement | null;
  restoreEditorFocus: () => void;
  onRequestAttachments?: () => void;
  onToggleFullHeight?: () => void;
}

const ToolbarContext = createContext<ToolbarContextValue>({
  findRequest: 0,
  isFullHeight: false,
  searchContainer: null,
  restoreEditorFocus: () => undefined,
});

const CODE_BLOCK_LANGUAGES = {
  "": "Plain text",
  bash: "Shell",
  css: "CSS",
  html: "HTML",
  java: "Java",
  js: "JavaScript",
  jsx: "JavaScript (React)",
  json: "JSON",
  markdown: "Markdown",
  python: "Python",
  rust: "Rust",
  sql: "SQL",
  swift: "Swift",
  ts: "TypeScript",
  tsx: "TypeScript (React)",
  xml: "XML",
  yaml: "YAML",
};

function SearchControl() {
  const { findRequest, restoreEditorFocus, searchContainer } =
    useContext(ToolbarContext);
  const inputRef = useRef<HTMLInputElement>(null);
  const {
    closeSearch,
    cursor,
    isSearchOpen,
    next,
    openSearch,
    prev,
    setSearch,
    total,
  } = useEditorSearch();
  const [inputValue, setInputValue] = useState("");
  const previousRequest = useRef(findRequest);

  useEffect(() => {
    if (findRequest !== previousRequest.current) openSearch();
    previousRequest.current = findRequest;
  }, [findRequest, openSearch]);

  useEffect(() => {
    if (isSearchOpen) {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [isSearchOpen]);

  const close = () => {
    closeSearch();
    requestAnimationFrame(restoreEditorFocus);
  };

  const updateSearch = (value: string) => {
    setInputValue(value);
    // The editor search API accepts a regular expression. Escaping turns the
    // control into the literal, accent-tolerant find people expect from an app.
    setSearch(
      value
        .normalize("NFKD")
        .replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
    );
  };

  if (isSearchOpen && searchContainer) {
    return createPortal(
      <div className="zerus-note-find" role="search" aria-label="Find in note">
        <Search size={14} aria-hidden="true" />
        <input
          ref={inputRef}
          value={inputValue}
          aria-label="Search this note"
          placeholder="Find in note"
          autoCapitalize="none"
          autoCorrect="off"
          enterKeyHint="search"
          onChange={(event) => updateSearch(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              if (event.shiftKey) prev();
              else next();
            } else if (event.key === "Escape") {
              event.preventDefault();
              close();
            }
          }}
        />
        <span className="zerus-note-find-count" aria-live="polite">
          {inputValue ? (total ? `${cursor} of ${total}` : "No results") : ""}
        </span>
        <span className="zerus-note-find-divider" aria-hidden="true" />
        <button type="button" aria-label="Previous match" disabled={!total} onClick={prev}>
          <ChevronUp size={16} />
        </button>
        <button type="button" aria-label="Next match" disabled={!total} onClick={next}>
          <ChevronDown size={16} />
        </button>
        <button type="button" aria-label="Close find" onClick={close}>
          <X size={16} />
        </button>
      </div>,
      searchContainer,
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
    <div className="zerus-mdx-toolbar-end">
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
    </div>
  );
}

const editorPlugins = [
  headingsPlugin(),
  quotePlugin(),
  listsPlugin(),
  linkPlugin(),
  linkDialogPlugin(),
  linkDialogPositionPlugin(),
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
  elementTablePlugin(),
  thematicBreakPlugin(),
  frontmatterPlugin(),
  codeBlockPlugin({ defaultCodeBlockLanguage: "" }),
  codeMirrorPlugin({ codeBlockLanguages: CODE_BLOCK_LANGUAGES }),
  markdownShortcutPlugin(),
  searchPlugin(),
  preserveEmptyParagraphsPlugin(),
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
              contents: () => (
                <div className="zerus-mdx-code-language">
                  <ChangeCodeMirrorLanguage />
                </div>
              ),
            },
            {
              fallback: () => (
                <>
                  <InsertElementTable />
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
  attachments = [],
  onAttachmentAction,
  onAttachmentDrop,
  onRequestAttachments,
}: MarkdownEditorProps) {
  const editorRef = useRef<MDXEditorMethods>(null);
  const recoveryRef = useRef<EditorRecoveryBoundary>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [searchContainer, setSearchContainer] = useState<HTMLDivElement | null>(
    null,
  );
  const [keyboardFindRequest, setKeyboardFindRequest] = useState(0);
  const lastInsertRequest = useRef<number | null>(null);
  const pendingLocalEchoes = useRef<string[]>([]);
  const [attachmentMenu, setAttachmentMenu] = useState<{
    id: string;
    left: number;
    top: number;
  } | null>(null);

  const captureWrapper = useCallback((element: HTMLDivElement | null) => {
    wrapperRef.current = element;
    setSearchContainer(element);
  }, []);

  const toolbarContext = useMemo<ToolbarContextValue>(
    () => ({
      findRequest: findRequest + keyboardFindRequest,
      isFullHeight,
      searchContainer,
      restoreEditorFocus: () => editorRef.current?.focus(),
      onRequestAttachments,
      onToggleFullHeight,
    }),
    [
      findRequest,
      isFullHeight,
      keyboardFindRequest,
      onRequestAttachments,
      onToggleFullHeight,
      searchContainer,
    ],
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
    const attachmentId = attachmentIdFromHref(href);
    if (!anchor || !attachmentId || !onAttachmentAction) return;
    event.preventDefault();
    event.stopPropagation();
    const rect = anchor.getBoundingClientRect();
    if (attachmentClickAction(rect.right, event.clientX) === "menu") {
      setAttachmentMenu({ id: attachmentId, left: rect.right, top: rect.bottom });
    } else {
      onAttachmentAction(attachmentId, "open");
    }
  };

  const menuAttachment = attachmentMenu
    ? attachments.find((attachment) => attachment.id === attachmentMenu.id)
    : null;

  return (
    <ToolbarContext.Provider value={toolbarContext}>
      <div
        ref={captureWrapper}
        className="zerus-mdx-shell"
        onClickCapture={handleClick}
        onKeyDownCapture={(event) => {
          if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
            event.preventDefault();
            setKeyboardFindRequest((request) => request + 1);
          }
        }}
        onKeyUp={reportSelection}
        onPointerUp={reportSelection}
        onBlur={() => onTextSelectionChange?.(false)}
      >
        <EditorRecoveryBoundary
          key={noteId}
          ref={recoveryRef}
          markdown={initialContent}
          onChange={onChange}
          readOnly={readOnly}
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
              const cleanedMarkdown = cleanMarkdownFromMdxEditor(markdown);
              recordLocalMarkdownEcho(pendingLocalEchoes.current, cleanedMarkdown);
              onChange(cleanedMarkdown);
            }}
            onError={({ error }) => recoveryRef.current?.recover(error)}
          />
        </EditorRecoveryBoundary>
        <DropdownMenu
          open={!!menuAttachment}
          onOpenChange={(open) => {
            if (!open) setAttachmentMenu(null);
          }}
        >
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              tabIndex={-1}
              aria-hidden="true"
              className="pointer-events-none fixed h-px w-px opacity-0"
              style={{
                left: attachmentMenu?.left ?? 0,
                top: attachmentMenu?.top ?? 0,
              }}
            />
          </DropdownMenuTrigger>
          {menuAttachment && (
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem
                onSelect={() => onAttachmentAction?.(menuAttachment.id, "open")}
              >
                <ExternalLink className="mr-2" size={14} />
                Open in default app
              </DropdownMenuItem>
              <DropdownMenuItem
                onSelect={() => onAttachmentAction?.(menuAttachment.id, "reveal")}
              >
                <FolderSearch className="mr-2" size={14} />
                Reveal in {fileManagerName}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onSelect={() =>
                  onAttachmentAction?.(
                    menuAttachment.id,
                    menuAttachment.kind === "vault" ? "external" : "copy",
                  )
                }
              >
                {menuAttachment.kind === "vault" ? (
                  <ExternalLink className="mr-2" size={14} />
                ) : (
                  <Copy className="mr-2" size={14} />
                )}
                {menuAttachment.kind === "vault"
                  ? "Keep as external link"
                  : "Copy into vault"}
              </DropdownMenuItem>
            </DropdownMenuContent>
          )}
        </DropdownMenu>
      </div>
    </ToolbarContext.Provider>
  );
}
