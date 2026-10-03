import { invoke, isTauri } from "@tauri-apps/api/core";
import { detectDownloadPlatform } from "./download-platform";

/** Resolve vault images through their display URL, then export actual bytes. */
export async function loadClipboardImage(url: string | null): Promise<Blob> {
  if (!url) throw new Error("The copied image is no longer available.");
  const response = await fetch(url);
  if (!response.ok) throw new Error("The copied image could not be opened.");
  return response.blob();
}

export function imageDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error("The copied image could not be read."));
    reader.readAsDataURL(blob);
  });
}

/** PNG is supported by both the web clipboard and native image paste targets. */
async function clipboardPng(blob: Blob): Promise<Blob> {
  if (blob.type === "image/png") return blob;
  const url = URL.createObjectURL(blob);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error("This image format could not be copied."));
      image.src = url;
    });
    const canvas = document.createElement("canvas");
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Image copying is unavailable on this device.");
    context.drawImage(image, 0, 0);
    return await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(result => result ? resolve(result)
        : reject(new Error("The copied image could not be prepared.")), "image/png");
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}

interface ImageClipboardContent {
  image?: Promise<Blob>;
  html?: Promise<string>;
  plain?: string;
}

/** Call during the copy gesture; defer loading through ClipboardItem promises. */
export async function writeImageClipboard({ image, html, plain }: ImageClipboardContent): Promise<void> {
  const png = image?.then(clipboardPng);
  if (isTauri() && detectDownloadPlatform(navigator) === "macos") {
    const [blob, markup] = await Promise.all([png, html]);
    await invoke("copy_image_clipboard", {
      png: blob ? Array.from(new Uint8Array(await blob.arrayBuffer())) : null,
      html: markup ?? null,
      plain: plain ?? null,
    });
    return;
  }
  if (!navigator.clipboard?.write || typeof ClipboardItem === "undefined") {
    throw new Error("Image copying is unavailable on this device.");
  }
  const data: Record<string, Blob | Promise<Blob>> = {};
  if (png) data["image/png"] = png;
  if (html) data["text/html"] = html.then(markup => new Blob([markup], { type: "text/html" }));
  if (plain !== undefined) data["text/plain"] = new Blob([plain], { type: "text/plain" });
  // WebKit rejects writes started after asynchronous image loading has consumed
  // the user activation. Start the write now, with promises for the bytes.
  await navigator.clipboard.write([new ClipboardItem(data)]);
}
