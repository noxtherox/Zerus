import type { NewChatImageAttachment } from "@/lib/mobile-chat-history";

export const CHAT_IMAGE_MAX_EDGE = 1_024;
export const CHAT_IMAGE_MAX_BYTES = 3 * 1_024 * 1_024;

export interface PreparedChatImage extends NewChatImageAttachment {
  previewUrl: string;
}

export function constrainedImageSize(
  width: number,
  height: number,
  maxEdge = CHAT_IMAGE_MAX_EDGE,
): { width: number; height: number } {
  if (width <= 0 || height <= 0) throw new Error("The selected image has invalid dimensions.");
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("This image format could not be opened."));
    };
    image.src = url;
  });
}

function canvasBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("The image could not be prepared."));
    }, "image/jpeg", quality);
  });
}

export async function prepareChatImage(file: File): Promise<PreparedChatImage> {
  if (!file.type.startsWith("image/")) throw new Error("Choose an image file.");
  const source = await loadImage(file);
  const size = constrainedImageSize(source.naturalWidth, source.naturalHeight);
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Image processing is unavailable on this device.");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, size.width, size.height);
  context.drawImage(source, 0, 0, size.width, size.height);

  let blob = await canvasBlob(canvas, 0.82);
  if (blob.size > CHAT_IMAGE_MAX_BYTES) blob = await canvasBlob(canvas, 0.68);
  if (blob.size > CHAT_IMAGE_MAX_BYTES) {
    throw new Error("The prepared image is still too large. Choose a smaller image.");
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  return {
    bytes,
    mimeType: "image/jpeg",
    width: size.width,
    height: size.height,
    name: file.name,
    previewUrl: URL.createObjectURL(blob),
  };
}

export function questionReferencesImage(question: string): boolean {
  return /\b(image|photo|picture|screenshot|scan|imagem|foto|fotografia|captura|documento)\b/i.test(question);
}
