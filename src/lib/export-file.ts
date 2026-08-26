import { isTauri } from "@tauri-apps/api/core";
import { save as saveDialog } from "@tauri-apps/plugin-dialog";
import { writeFile } from "@tauri-apps/plugin-fs";
import type { NoteExportArtifact } from "@/lib/note-export";

const MIME_BY_FORMAT = {
  html: "text/html",
  pdf: "application/pdf",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
} as const;

export async function saveExportArtifact(
  artifact: NoteExportArtifact,
): Promise<"cancelled" | "saved" | "shared"> {
  const file = new File([artifact.blob], artifact.fileName, {
    type: MIME_BY_FORMAT[artifact.format],
  });

  if (/iPhone|iPad|iPod/i.test(navigator.userAgent) && navigator.share) {
    const canShare = !navigator.canShare || navigator.canShare({ files: [file] });
    if (canShare) {
      try {
        await navigator.share({ files: [file], title: artifact.fileName });
        return "shared";
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
          return "cancelled";
        }
        // Fall back to the native save dialog if sharing is unavailable.
      }
    }
  }

  if (isTauri()) {
    const path = await saveDialog({
      defaultPath: artifact.fileName,
      filters: [{
        name: artifact.format.toUpperCase(),
        extensions: [artifact.format],
      }],
    });
    if (!path) return "cancelled";
    await writeFile(path, new Uint8Array(await artifact.blob.arrayBuffer()));
    return "saved";
  }

  const url = URL.createObjectURL(artifact.blob);
  try {
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = artifact.fileName;
    anchor.click();
  } finally {
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
  return "saved";
}
