import { useCallback, useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import {
  AlertTriangle,
  Check,
  History,
  Loader2,
  Pin,
  RotateCcw,
  Trash2,
  X,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import type { Note } from "@/lib/note-utils";
import { historyRelevantContent, type NoteHistoryVersion } from "@/lib/note-history";
import {
  clearNoteVersionHistory,
  getNoteHistoryVersions,
  restoreNoteHistoryVersion,
  setNoteHistoryVersion,
} from "@/store/notes-store";
import { cn } from "@/lib/utils";

type DiffLine = { kind: "same" | "add" | "remove"; text: string };

function lineDiff(before: string, after: string): DiffLine[] {
  const left = before.split("\n");
  const right = after.split("\n");
  if (left.length * right.length > 120_000) {
    return [
      ...left.map((text) => ({ kind: "remove" as const, text })),
      ...right.map((text) => ({ kind: "add" as const, text })),
    ];
  }
  const table = Array.from({ length: left.length + 1 }, () => new Uint32Array(right.length + 1));
  for (let i = left.length - 1; i >= 0; i -= 1) {
    for (let j = right.length - 1; j >= 0; j -= 1) {
      table[i][j] = left[i] === right[j]
        ? table[i + 1][j + 1] + 1
        : Math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  const result: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] === right[j]) {
      result.push({ kind: "same", text: left[i++] });
      j += 1;
    } else if (j < right.length && (i === left.length || table[i][j + 1] >= table[i + 1][j])) {
      result.push({ kind: "add", text: right[j++] });
    } else {
      result.push({ kind: "remove", text: left[i++] });
    }
  }
  return result;
}

function highlightedText(line: DiffLine, neighbor?: DiffLine) {
  if (!neighbor || line.kind === "same" || neighbor.kind === "same" || line.kind === neighbor.kind) {
    return line.text || " ";
  }
  let prefix = 0;
  while (prefix < line.text.length && prefix < neighbor.text.length && line.text[prefix] === neighbor.text[prefix]) prefix += 1;
  let suffix = 0;
  while (
    suffix < line.text.length - prefix &&
    suffix < neighbor.text.length - prefix &&
    line.text[line.text.length - suffix - 1] === neighbor.text[neighbor.text.length - suffix - 1]
  ) suffix += 1;
  if (prefix === line.text.length) return line.text || " ";
  return <>{line.text.slice(0, prefix)}<mark className="rounded-sm bg-current/20 text-inherit">{line.text.slice(prefix, suffix ? -suffix : undefined) || " "}</mark>{suffix ? line.text.slice(-suffix) : ""}</>;
}

function sourceLabel(version: NoteHistoryVersion): string {
  if (version.source === "external") return "External change";
  if (version.source === "restore") return "Restore";
  return `${version.source[0].toUpperCase()}${version.source.slice(1)} ${version.originId.slice(0, 4)} autosave`;
}

export function VersionHistoryPanel({
  note,
  onClose,
  mobile = false,
}: {
  note: Note;
  onClose: () => void;
  mobile?: boolean;
}) {
  const [versions, setVersions] = useState<NoteHistoryVersion[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [fullPreview, setFullPreview] = useState(false);
  const [showInternal, setShowInternal] = useState(false);
  const [restoreOpen, setRestoreOpen] = useState(false);
  const [clearOpen, setClearOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const next = await getNoteHistoryVersions(note.id);
      setVersions(next);
      setSelectedId((current) => next.some((version) => version.id === current) ? current : next[0]?.id ?? null);
      setError(null);
    } catch (reason) {
      setError(String(reason));
    } finally {
      setLoading(false);
    }
  }, [note.id]);

  useEffect(() => { void reload(); }, [reload]);
  const selected = versions.find((version) => version.id === selectedId) ?? null;
  const parent = selected?.parentId
    ? versions.find((version) => version.id === selected.parentId) ?? null
    : null;
  const before = parent?.content ?? "";
  const visibleBefore = showInternal ? before : historyRelevantContent(before);
  const visibleAfter = selected
    ? showInternal ? selected.content : historyRelevantContent(selected.content)
    : "";
  const diff = useMemo(() => lineDiff(visibleBefore, visibleAfter), [visibleAfter, visibleBefore]);

  const updateSelected = async (patch: { kept?: boolean; label?: string | null }) => {
    if (!selected) return;
    await setNoteHistoryVersion(note.id, selected.id, patch);
    await reload();
  };

  const restore = async () => {
    if (!selected) return;
    setBusy(true);
    const restored = await restoreNoteHistoryVersion(note.id, selected.id);
    setBusy(false);
    setRestoreOpen(false);
    if (restored) await reload();
    else setError("This version could not be restored. A required parent or image may still be syncing.");
  };

  return (
    <section className={cn(
      "flex min-h-0 flex-col border-l border-border bg-background",
      mobile ? "absolute inset-0 z-40 border-l-0 bg-[#1c1d1e] text-[#f5f3ef]" : "w-[390px] shrink-0",
    )} aria-label="Version history">
      <header className={cn("flex h-12 shrink-0 items-center gap-2 border-b px-3", mobile && "border-white/[0.08]")}>
        <History size={17} className="text-zerus-accent" />
        <h2 className="min-w-0 flex-1 truncate text-sm font-semibold">Version history</h2>
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onClose} aria-label="Close version history"><X size={16} /></Button>
      </header>
      {loading ? (
        <div className="flex flex-1 items-center justify-center"><Loader2 className="animate-spin" size={20} /></div>
      ) : versions.length === 0 ? (
        <div className="flex flex-1 flex-col items-center justify-center px-8 text-center text-sm text-muted-foreground">
          <History className="mb-3 opacity-50" size={30} />
          <p>No versions yet.</p>
          <p className="mt-1 text-xs">The first content autosave will establish this note’s history.</p>
        </div>
      ) : (
        <div className={cn("grid min-h-0 flex-1", mobile ? "grid-rows-[minmax(0,0.42fr)_minmax(0,0.58fr)]" : "grid-rows-[minmax(150px,0.42fr)_minmax(240px,0.58fr)]")}>
          <div className={cn("overflow-y-auto border-b", mobile && "border-white/[0.08]")}>
            {versions.map((version) => (
              <button key={version.id} type="button" onClick={() => setSelectedId(version.id)} className={cn(
                "flex w-full items-start gap-2 border-b border-border/60 px-3 py-2.5 text-left last:border-0",
                version.id === selectedId && "bg-muted",
                mobile && "border-white/[0.06]",
              )}>
                <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">{version.kept ? <Pin size={13} /> : version.checkpoint ? <Check size={13} /> : <span className="h-1.5 w-1.5 rounded-full bg-current" />}</span>
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-1.5 text-xs font-medium"><span>{format(new Date(version.timestamp), "MMM d, HH:mm:ss")}</span>{version.alternateBranch && <span className="rounded bg-amber-500/15 px-1 text-[10px] text-amber-600">Alternate branch</span>}</span>
                  <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">{version.label || sourceLabel(version)} · <span className="text-emerald-600">+{version.addedLines}</span> <span className="text-red-500">−{version.removedLines}</span></span>
                </span>
              </button>
            ))}
          </div>
          {selected && (
            <div className="flex min-h-0 flex-col">
              <div className={cn("flex flex-wrap items-center gap-2 border-b px-3 py-2", mobile && "border-white/[0.08]")}>
                <Button size="sm" variant={selected.kept ? "secondary" : "outline"} className="h-7 gap-1 text-xs" onClick={() => void updateSelected({ kept: !selected.kept })}><Pin size={13} />{selected.kept ? "Kept" : "Keep"}</Button>
                <Input defaultValue={selected.label ?? ""} key={`${selected.id}-${selected.label}`} placeholder="Optional label" className="h-7 min-w-28 flex-1 text-xs" onBlur={(event) => void updateSelected({ label: event.target.value })} />
                <label className="flex items-center gap-1.5 text-[11px] text-muted-foreground"><Switch checked={fullPreview} onCheckedChange={setFullPreview} className="scale-75" />Full</label>
              </div>
              <div className="min-h-0 flex-1 overflow-auto bg-muted/25 font-mono text-[11px] leading-5">
                {selected.incomplete && <div className="flex gap-2 border-b border-amber-500/20 bg-amber-500/10 px-3 py-2 font-sans text-xs text-amber-700"><AlertTriangle size={15} />Some data is missing or still syncing. Restore is unavailable.</div>}
                {fullPreview ? <pre className="whitespace-pre-wrap break-words p-3">{visibleAfter}</pre> : diff.map((line, index) => {
                  const neighbor = line.kind === "remove" ? diff[index + 1] : line.kind === "add" ? diff[index - 1] : undefined;
                  return <div key={index} className={cn("grid grid-cols-[22px_1fr] px-2", line.kind === "add" && "bg-emerald-500/10 text-emerald-700", line.kind === "remove" && "bg-red-500/10 text-red-700")}><span className="select-none opacity-60">{line.kind === "add" ? "+" : line.kind === "remove" ? "−" : " "}</span><span className="whitespace-pre-wrap break-all">{highlightedText(line, neighbor)}</span></div>;
                })}
              </div>
              <div className={cn("flex items-center gap-2 border-t p-3", mobile && "border-white/[0.08] pb-[calc(env(safe-area-inset-bottom)+0.75rem)]")}>
                <label className="flex min-w-0 flex-1 items-center gap-1.5 text-[11px] text-muted-foreground"><Switch checked={showInternal} onCheckedChange={setShowInternal} className="scale-75" />Internal metadata</label>
                <Button variant="ghost" size="icon" className="h-8 w-8 text-destructive" onClick={() => setClearOpen(true)} aria-label="Clear version history"><Trash2 size={15} /></Button>
                <Button size="sm" className="h-8 gap-1.5" disabled={busy || selected.incomplete} onClick={() => setRestoreOpen(true)}>{busy ? <Loader2 className="animate-spin" size={14} /> : <RotateCcw size={14} />}Restore</Button>
              </div>
              {error && <p className="px-3 pb-2 text-xs text-destructive">{error}</p>}
            </div>
          )}
        </div>
      )}
      <AlertDialog open={restoreOpen} onOpenChange={setRestoreOpen}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Restore this version?</AlertDialogTitle><AlertDialogDescription>{selected ? `Restore the version from ${format(new Date(selected.timestamp), "PPpp")}. Your current content will remain recoverable as a new version.` : ""}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={() => void restore()}>Restore version</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
      <AlertDialog open={clearOpen} onOpenChange={setClearOpen}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Clear this note’s history?</AlertDialogTitle><AlertDialogDescription>This permanently deletes every automatic and kept version for this note. The current note and its live images are not changed.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction className="bg-destructive text-destructive-foreground" onClick={() => void clearNoteVersionHistory(note.id).then(() => { setClearOpen(false); return reload(); })}>Clear history</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    </section>
  );
}
