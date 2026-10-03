import { $isImageNode, createActiveEditorSubscription$, realmPlugin } from "@mdxeditor/editor";
import { $getClipboardDataFromSelection, setLexicalClipboardDataTransfer, type LexicalClipboardData } from "@lexical/clipboard";
import {
  $getNodeByKey,
  $getSelection,
  $isRangeSelection,
  $setSelection,
  COMMAND_PRIORITY_CRITICAL,
  COPY_COMMAND,
  HISTORY_PUSH_TAG,
  PASTE_COMMAND,
} from "lexical";
import { toast } from "sonner";
import {
  discardUnsavedImage,
  getVaultBackend,
  getImageUrl,
  getVaultImagePathForUrl,
  savePastedImage,
} from "@/store/notes-store";
import { imageDataUrl, loadClipboardImage, writeImageClipboard } from "@/lib/image-clipboard";

let copiedContent: { token: string; data: LexicalClipboardData; backend: ReturnType<typeof getVaultBackend> } | null = null;

function isTemporaryImage(source: string): boolean {
  return /^(blob:|data:image\/)/i.test(source);
}

/** Export portable image bytes and save incoming session-only image URLs. */
export const imageClipboardPlugin = realmPlugin({
  init(realm) {
    realm.pub(createActiveEditorSubscription$, (editor) => {
      let disposed = false;
      const unregisterCopy = editor.registerCommand(COPY_COMMAND, event => {
        const selection = $getSelection();
        if (!selection || !selection.getNodes().some($isImageNode)) return false;
        const data = $getClipboardDataFromSelection(selection);
        const document = new DOMParser().parseFromString(data["text/html"] ?? "", "text/html");
        const images = Array.from(document.querySelectorAll("img"));
        if (!images.length) return false;
        const token = crypto.randomUUID();
        const backend = getVaultBackend();
        const blobs = images.map(image => {
          const path = image.getAttribute("src") ?? "";
          return (isTemporaryImage(path) ? Promise.resolve(path) : getImageUrl(path)).then(loadClipboardImage);
        });
        const html = Promise.all(blobs.map(blob => blob.then(imageDataUrl))).then(sources => {
          images.forEach((image, index) => image.setAttribute("src", sources[index]));
          const wrapper = document.createElement("div");
          wrapper.setAttribute("data-zerus-clipboard", token);
          wrapper.append(...Array.from(document.body.childNodes));
          return wrapper.outerHTML;
        });
        const imageOnly = images.length === 1 && !document.body.textContent?.trim();
        event?.preventDefault();
        // Keep the matching native/internal representation private to this
        // session and vault. Foreign HTML cannot supply trusted asset paths.
        void writeImageClipboard({
          image: imageOnly ? blobs[0] : undefined,
          html,
          plain: data["text/plain"],
        }).then(() => { copiedContent = { token, data, backend }; }).catch((error: unknown) => {
          toast.error(error instanceof Error ? error.message : "The image could not be copied.");
        });
        return true;
      }, COMMAND_PRIORITY_CRITICAL);
      const unregister = editor.registerCommand(PASTE_COMMAND, (event) => {
        if (!event || !("clipboardData" in event) || !event.clipboardData || !editor.isEditable()) return false;
        const data = event.clipboardData;
        // Lexical copies already contain the original asset path, dimensions,
        // and surrounding content. Let its importer preserve that information.
        try {
          const serialized = JSON.parse(data.getData("application/x-lexical-editor"));
          if (serialized?.namespace === editor._config.namespace && Array.isArray(serialized.nodes)) return false;
        } catch { /* Other applications do not provide Lexical clipboard data. */ }

        const files = Array.from(data.files).filter(file => file.type.startsWith("image/"));
        const html = data.getData("text/html");
        const plain = data.getData("text/plain");
        if (!files.length && !/<img\b/i.test(html)) return false;
        const document = new DOMParser().parseFromString(html, "text/html");
        if (copiedContent && copiedContent.backend === getVaultBackend() &&
            document.querySelector("[data-zerus-clipboard]")?.getAttribute("data-zerus-clipboard") === copiedContent.token) {
          const clipboard = new DataTransfer();
          setLexicalClipboardDataTransfer(clipboard, copiedContent.data);
          event.preventDefault();
          return editor.dispatchCommand(PASTE_COMMAND, new ClipboardEvent("paste", { clipboardData: clipboard }));
        }
        const images = Array.from(document.querySelectorAll("img"));
        if (!files.length && !images.some(image => isTemporaryImage(image.getAttribute("src") ?? ""))) return false;
        const selection = $getSelection()?.clone();
        if (!selection) return false;
        event.preventDefault();
        const targetBackend = getVaultBackend();
        const savedPaths: string[] = [];
        const discard = async () => {
          if (getVaultBackend() === targetBackend) await Promise.all(savedPaths.map(discardUnsavedImage));
        };

        const save = async (blob: Blob) => {
          const bytes = new Uint8Array(await blob.arrayBuffer());
          if (disposed || getVaultBackend() !== targetBackend) throw new Error("The paste was cancelled because the note or vault changed.");
          const path = await savePastedImage(bytes, blob.type);
          if (!path) throw new Error("The image could not be saved to the vault.");
          savedPaths.push(path);
          return path;
        };

        void (async () => {
          if (!images.length) {
            for (const file of files) {
              const image = document.createElement("img");
              image.setAttribute("src", await save(file));
              image.setAttribute("alt", file.name);
              document.body.append(image);
            }
          } else {
            let fileIndex = 0;
            const resolved = new Map<string, string>();
            for (const [index, image] of images.entries()) {
              const source = image.getAttribute("src") ?? "";
              const cached = getVaultImagePathForUrl(source) ?? resolved.get(source);
              const file = files.length === images.length ? files[index]
                : isTemporaryImage(source) ? files[fileIndex++] : undefined;
              let path = cached;
              if (!path && file) path = await save(file);
              if (!path && isTemporaryImage(source)) {
                const response = await fetch(source);
                if (!response.ok) throw new Error("The copied image is no longer available. Copy it again from its source.");
                path = await save(await response.blob());
              }
              if (path) {
                image.setAttribute("src", path);
                resolved.set(source, path);
              }
            }
          }

          const clipboard = new DataTransfer();
          clipboard.setData("text/html", document.body.innerHTML);
          clipboard.setData("text/plain", plain);
          let inserted = false;
          if (!disposed && getVaultBackend() === targetBackend && editor.isEditable()) editor.update(() => {
            if ($isRangeSelection(selection) &&
                (!$getNodeByKey(selection.anchor.key) || !$getNodeByKey(selection.focus.key))) return;
            $setSelection(selection);
            inserted = editor.dispatchCommand(PASTE_COMMAND, new ClipboardEvent("paste", { clipboardData: clipboard }));
          }, { tag: HISTORY_PUSH_TAG, discrete: true });
          if (!inserted) await discard();
        })().catch(async (error: unknown) => {
          await discard();
          if (!disposed) toast.error(error instanceof Error ? error.message : "The pasted image could not be saved.");
        });
        return true;
      }, COMMAND_PRIORITY_CRITICAL);
      return () => { disposed = true; unregisterCopy(); unregister(); };
    });
  },
});
