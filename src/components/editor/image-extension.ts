import {
  Decoration,
  type DecorationSet,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import {
  type EditorState,
  type Extension,
  type Range,
  StateField,
} from "@codemirror/state";
import {
  IMAGE_MD_REGEX,
  formatImageMarkdown,
  parseImageAlt,
} from "@/lib/note-utils";

const MIN_WIDTH = 48;

type GetImageUrl = (path: string) => Promise<string | null>;
type SaveImage = (bytes: Uint8Array, mime: string) => Promise<string | null>;

export interface EditorImageMatch {
  path: string;
  alt: string;
  width: number | null;
  from: number;
  to: number;
}

export interface ImageInteractionOptions {
  getUrl: GetImageUrl;
  onSelect?: (
    image: EditorImageMatch,
    anchor: { element: HTMLElement },
  ) => void;
  onOpen?: (image: EditorImageMatch) => void;
  onDismiss?: () => void;
}

export function shouldOpenEditorImage(
  event: Pick<MouseEvent, "button" | "metaKey" | "ctrlKey" | "detail">,
): boolean {
  return (
    event.button === 0 &&
    (event.metaKey || event.ctrlKey || event.detail >= 2)
  );
}

/** Resolve the real document line immediately following an image preview. */
export function caretAfterEditorImage(state: EditorState, imageTo: number): number {
  const imageLine = state.doc.lineAt(Math.min(imageTo, state.doc.length));
  return imageLine.number < state.doc.lines
    ? state.doc.line(imageLine.number + 1).from
    : imageLine.to;
}

/** Whether the visual row immediately after an image is an empty document line. */
export function hasBlankLineAfterEditorImage(
  state: EditorState,
  imageTo: number,
): boolean {
  const imageLine = state.doc.lineAt(Math.min(imageTo, state.doc.length));
  return (
    imageLine.number < state.doc.lines &&
    state.doc.line(imageLine.number + 1).text.length === 0
  );
}

/**
 * Renders the image below the markdown that references it, with a drag handle
 * on the right edge. Dragging writes the new width back into the markdown as
 * `![alt|320](path)`, which is what persists the size.
 */
class ImagePreviewWidget extends WidgetType {
  private layoutObserver: ResizeObserver | null = null;

  constructor(
    private readonly path: string,
    private readonly alt: string,
    private readonly width: number | null,
    private readonly from: number,
    private readonly to: number,
    private readonly options: ImageInteractionOptions,
  ) {
    super();
  }

  override eq(other: ImagePreviewWidget): boolean {
    return (
      other.path === this.path &&
      other.width === this.width &&
      other.alt === this.alt &&
      other.from === this.from &&
      other.to === this.to
    );
  }

  override toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-image-preview";
    wrap.setAttribute("aria-label", `Image: ${this.path}`);

    const media = document.createElement("div");
    media.className = "cm-image-preview-media";
    wrap.appendChild(media);

    const img = document.createElement("img");
    img.alt = this.alt;
    img.draggable = false;
    if (this.width) img.style.width = `${this.width}px`;
    media.appendChild(img);

    // The image gets its intrinsic height after the block widget has already
    // been mounted. Refresh CodeMirror's height map once that happens so
    // pointer hit-testing and vertical cursor motion below the preview stay
    // aligned with the rendered document.
    const requestLayoutMeasure = () => {
      if (wrap.isConnected) view.requestMeasure();
    };
    img.addEventListener("load", requestLayoutMeasure, { once: true });
    img.addEventListener("error", requestLayoutMeasure, { once: true });
    if (typeof ResizeObserver !== "undefined") {
      this.layoutObserver = new ResizeObserver(requestLayoutMeasure);
      this.layoutObserver.observe(wrap);
    }

    void this.options.getUrl(this.path).then((url) => {
      if (url) {
        img.src = url;
        return;
      }
      wrap.classList.add("cm-image-preview-missing");
      img.remove();
      media.textContent = `Image not found: ${this.path}`;
      requestLayoutMeasure();
    });

    const handle = document.createElement("div");
    handle.className = "cm-image-resize-handle";
    handle.title = "Drag to resize";
    media.appendChild(handle);

    if (hasBlankLineAfterEditorImage(view.state, this.to)) {
      const afterHitArea = document.createElement("div");
      afterHitArea.className = "cm-image-after-hit-area";
      afterHitArea.setAttribute("aria-hidden", "true");
      wrap.appendChild(afterHitArea);
    }

    const imageMatch = (): EditorImageMatch => ({
      path: this.path,
      alt: this.alt,
      width: this.width,
      from: this.from,
      to: this.to,
    });

    const placeCaretAfterImage = () => {
      view.dispatch({
        selection: { anchor: caretAfterEditorImage(view.state, this.to) },
        scrollIntoView: true,
        userEvent: "select.pointer",
      });
      view.focus();
      this.options.onDismiss?.();
    };

    // A block widget is much taller than the hidden Markdown line it belongs
    // to. Do not let CodeMirror reinterpret a click through stale document
    // coordinates; the preview is focusable and behaves as one selected object.
    wrap.addEventListener("mousedown", (event) => {
      if (event.target === handle || event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
    });

    wrap.addEventListener("click", (event) => {
      if (event.target === handle || event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
      if (
        event.target instanceof HTMLElement &&
        event.target.classList.contains("cm-image-after-hit-area")
      ) {
        placeCaretAfterImage();
        return;
      }
      if (shouldOpenEditorImage(event)) {
        this.options.onOpen?.(imageMatch());
        return;
      }
      wrap.focus({ preventScroll: true });
      this.options.onSelect?.(imageMatch(), {
        element: wrap,
      });
    });

    wrap.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        event.stopPropagation();
        placeCaretAfterImage();
        return;
      }
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      event.stopPropagation();
      this.options.onSelect?.(imageMatch(), {
        element: wrap,
      });
    });
    wrap.tabIndex = 0;

    handle.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      handle.setPointerCapture(event.pointerId);
      wrap.classList.add("cm-image-resizing");
      const startX = event.clientX;
      const startWidth = img.getBoundingClientRect().width;
      let currentWidth = startWidth;

      const onMove = (move: PointerEvent) => {
        currentWidth = Math.max(MIN_WIDTH, startWidth + move.clientX - startX);
        img.style.width = `${currentWidth}px`;
      };
      const onUp = () => {
        handle.removeEventListener("pointermove", onMove);
        handle.removeEventListener("pointerup", onUp);
        wrap.classList.remove("cm-image-resizing");
        const finalWidth = Math.round(currentWidth);
        if (finalWidth !== Math.round(startWidth)) {
          this.commitWidth(view, wrap, finalWidth);
        }
      };
      handle.addEventListener("pointermove", onMove);
      handle.addEventListener("pointerup", onUp);
    });

    return wrap;
  }

  override destroy(): void {
    this.layoutObserver?.disconnect();
    this.layoutObserver = null;
  }

  /** Rewrites this image's markdown on the line the widget is attached to. */
  private commitWidth(view: EditorView, dom: HTMLElement, width: number) {
    const pos = view.posAtDOM(dom);
    if (pos == null) return;
    const line = view.state.doc.lineAt(Math.min(pos, view.state.doc.length));
    for (const match of line.text.matchAll(IMAGE_MD_REGEX)) {
      if (match[2] !== this.path) continue;
      const from = line.from + (match.index ?? 0);
      const { alt } = parseImageAlt(match[1]);
      view.dispatch({
        changes: {
          from,
          to: from + match[0].length,
          insert: formatImageMarkdown(alt, width, this.path),
        },
      });
      return;
    }
  }
}

function buildImageDecorations(
  state: EditorState,
  options: ImageInteractionOptions,
): DecorationSet {
  const widgets: Range<Decoration>[] = [];
  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo);
    for (const match of line.text.matchAll(IMAGE_MD_REGEX)) {
      const { alt, width } = parseImageAlt(match[1]);
      const from = line.from + (match.index ?? 0);
      widgets.push(
        Decoration.widget({
          widget: new ImagePreviewWidget(
            match[2],
            alt,
            width,
            from,
            from + match[0].length,
            options,
          ),
          block: true,
          // Keep the block after its source line. Clicks explicitly select the
          // following document line, avoiding the synthetic blank row that a
          // negative side creates around block widgets.
          side: 1,
        }).range(line.to),
      );
    }
  }
  return Decoration.set(widgets);
}

/**
 * Shows resizable previews under image markdown. A state field (not a view
 * plugin) because block decorations must come from the state.
 */
export function imagePreviewExtension(
  getUrlOrOptions: GetImageUrl | ImageInteractionOptions,
): Extension {
  const options =
    typeof getUrlOrOptions === "function"
      ? { getUrl: getUrlOrOptions }
      : getUrlOrOptions;
  return StateField.define<DecorationSet>({
    create: (state) => buildImageDecorations(state, options),
    update: (decorations, tr) =>
      tr.docChanged ? buildImageDecorations(tr.state, options) : decorations,
    provide: (field) => EditorView.decorations.from(field),
  });
}

/** Saves pasted or dropped image files into the vault and inserts markdown. */
export function imagePasteExtension(saveImage: SaveImage): Extension {
  const insertImages = async (
    view: EditorView,
    files: File[],
    at?: number,
  ) => {
    for (const file of files) {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const path = await saveImage(bytes, file.type);
      if (!path) continue;
      const markdown = `![](${path})`;
      if (at != null) {
        view.dispatch({
          changes: { from: at, insert: markdown },
          selection: { anchor: at + markdown.length },
        });
        at += markdown.length;
      } else {
        view.dispatch(view.state.replaceSelection(markdown));
      }
    }
  };

  const imageFiles = (list: DataTransferItemList | undefined): File[] => {
    if (!list) return [];
    return [...list]
      .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter((file): file is File => file !== null);
  };

  return EditorView.domEventHandlers({
    paste: (event, view) => {
      const files = imageFiles(event.clipboardData?.items);
      if (!files.length) return false;
      event.preventDefault();
      void insertImages(view, files);
      return true;
    },
    drop: (event, view) => {
      const files = [...(event.dataTransfer?.files ?? [])].filter((file) =>
        file.type.startsWith("image/"),
      );
      if (!files.length) return false;
      event.preventDefault();
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      void insertImages(view, files, pos ?? view.state.selection.main.from);
      return true;
    },
  });
}
