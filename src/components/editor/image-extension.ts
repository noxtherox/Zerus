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

/**
 * Renders the image below the markdown that references it, with a drag handle
 * on the right edge. Dragging writes the new width back into the markdown as
 * `![alt|320](path)`, which is what persists the size.
 */
class ImagePreviewWidget extends WidgetType {
  constructor(
    private readonly path: string,
    private readonly alt: string,
    private readonly width: number | null,
    private readonly getUrl: GetImageUrl,
  ) {
    super();
  }

  override eq(other: ImagePreviewWidget): boolean {
    return (
      other.path === this.path &&
      other.width === this.width &&
      other.alt === this.alt
    );
  }

  override toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-image-preview";
    wrap.setAttribute("aria-label", `Image: ${this.path}`);

    const img = document.createElement("img");
    img.alt = this.alt;
    img.draggable = false;
    if (this.width) img.style.width = `${this.width}px`;
    wrap.appendChild(img);

    // The image gets its intrinsic height after the block widget has already
    // been mounted. Refresh CodeMirror's height map once that happens so
    // pointer hit-testing and vertical cursor motion below the preview stay
    // aligned with the rendered document.
    const requestLayoutMeasure = () => {
      if (wrap.isConnected) view.requestMeasure();
    };
    img.addEventListener("load", requestLayoutMeasure, { once: true });
    img.addEventListener("error", requestLayoutMeasure, { once: true });

    void this.getUrl(this.path).then((url) => {
      if (url) {
        img.src = url;
        return;
      }
      wrap.classList.add("cm-image-preview-missing");
      img.remove();
      wrap.textContent = `Image not found: ${this.path}`;
      requestLayoutMeasure();
    });

    const handle = document.createElement("div");
    handle.className = "cm-image-resize-handle";
    handle.title = "Drag to resize";
    wrap.appendChild(handle);

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
  getUrl: GetImageUrl,
): DecorationSet {
  const widgets: Range<Decoration>[] = [];
  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo);
    for (const match of line.text.matchAll(IMAGE_MD_REGEX)) {
      const { alt, width } = parseImageAlt(match[1]);
      widgets.push(
        Decoration.widget({
          widget: new ImagePreviewWidget(match[2], alt, width, getUrl),
          block: true,
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
export function imagePreviewExtension(getUrl: GetImageUrl): Extension {
  return StateField.define<DecorationSet>({
    create: (state) => buildImageDecorations(state, getUrl),
    update: (decorations, tr) =>
      tr.docChanged ? buildImageDecorations(tr.state, getUrl) : decorations,
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
