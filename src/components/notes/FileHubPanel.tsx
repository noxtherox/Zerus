import { lazy, Suspense, useCallback, useEffect, useState } from "react";
import {
  ExternalLink,
  File,
  FileSearch,
  FolderSearch,
  MapPin,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { fileManagerName } from "@/lib/desktop-platform";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import type { Note } from "@/lib/note-utils";
import {
  getFileHubStatus,
  mapFileLocation,
  openFileHub,
  readFileHubBytes,
  revealFileHub,
  type FileHubStatus,
} from "@/store/notes-store";

const PdfViewer = lazy(() =>
  import("@/components/notes/PdfViewer").then((module) => ({
    default: module.PdfViewer,
  })),
);

function formatBytes(bytes: number | null): string {
  if (bytes === null) return "Unknown size";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
}

export function FileHubPanel({
  note,
  showPdf,
  isPdfFullHeight = false,
  onTogglePdfFullHeight,
}: {
  note: Note;
  showPdf: boolean;
  isPdfFullHeight?: boolean;
  onTogglePdfFullHeight?: () => void;
}) {
  const reference = getFileHubReference(note);
  const [status, setStatus] = useState<FileHubStatus | null>(null);
  const [version, setVersion] = useState("");

  const refresh = useCallback(async () => {
    const next = await getFileHubStatus(note.id);
    setStatus(next);
    setVersion(`${next?.modifiedAt ?? "missing"}:${next?.size ?? 0}`);
  }, [note.id]);

  useEffect(() => {
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [note.content, refresh]);

  const loadBytes = useCallback(() => readFileHubBytes(note.id), [note.id]);
  if (!reference) return null;
  const locationLabel =
    reference.kind === "vault"
      ? reference.managed
        ? "Managed vault copy"
        : "Vault link"
      : reference.kind === "local"
        ? "Local to this device"
        : status?.resolved.location?.name ?? "Unknown location";
  const detailPath =
    reference.kind === "local"
      ? status?.resolved.absolutePath ?? "Not located on this device"
      : reference.path ?? "Missing path";

  return (
    <div className="flex h-full min-h-0 flex-col bg-grim-editor">
      <div className="shrink-0 border-b border-border/60 bg-background/70 p-3">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 rounded-md bg-muted p-2 text-grim-accent">
            {showPdf ? <FileSearch size={20} /> : <File size={20} />}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">{reference.name}</p>
            <p className="mt-0.5 truncate text-xs text-muted-foreground" title={detailPath}>
              {locationLabel} · {fileExtension(reference.name).toUpperCase() || "FILE"}
              {status?.exists ? ` · ${formatBytes(status.size)}` : " · File unavailable"}
            </p>
            <p className="mt-0.5 truncate text-[11px] text-muted-foreground" title={detailPath}>{detailPath}</p>
          </div>
          <div className="flex flex-wrap justify-end gap-1">
            <Button size="sm" className="h-8 gap-1.5 text-xs" disabled={!status?.exists} onClick={() => void openFileHub(note.id)}>
              <ExternalLink size={13} /> Open in Default App
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="h-8 gap-1.5 text-xs"
              title={`Reveal in ${fileManagerName}`}
              disabled={!status?.exists}
              onClick={() => void revealFileHub(note.id)}
            >
              <FolderSearch size={13} /> Reveal
            </Button>
            {status?.resolved.missingMapping && reference.locationId && (
              <Button variant="ghost" size="sm" className="h-8 gap-1.5 text-xs" onClick={() => void mapFileLocation(reference.locationId!).then(refresh)}>
                <MapPin size={13} /> Configure Location
              </Button>
            )}
          </div>
        </div>
      </div>
      {showPdf && status?.exists && (
        <div className="min-h-0 flex-1">
          <Suspense
            fallback={
              <div className="flex h-full min-h-36 items-center justify-center text-sm text-muted-foreground">
                Loading PDF preview…
              </div>
            }
          >
            <PdfViewer
              loadBytes={loadBytes}
              version={version}
              isFullHeight={isPdfFullHeight}
              onToggleFullHeight={onTogglePdfFullHeight}
            />
          </Suspense>
        </div>
      )}
      {showPdf && status && !status.exists && (
        <div className="flex min-h-36 flex-1 items-center justify-center p-6 text-center text-sm text-muted-foreground">
          This PDF is unavailable on this device. Configure its location or locate the file to restore the preview.
        </div>
      )}
    </div>
  );
}
