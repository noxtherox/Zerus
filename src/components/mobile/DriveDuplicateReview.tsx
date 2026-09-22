import { useState } from "react";
import { DRIVE_FOLDER } from "@/lib/google-drive";
import { DriveDuplicateError, GoogleDriveVault } from "@/lib/vault/google-drive";

interface Props {
  vault: GoogleDriveVault;
  conflict: DriveDuplicateError;
  onRefresh: () => Promise<void>;
  onClose: () => void;
}

export function DriveDuplicateReview({ vault, conflict, onRefresh, onClose }: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [previews, setPreviews] = useState<Record<string, string>>({});
  const [names, setNames] = useState<Record<string, string>>({});
  const run = async (action: () => Promise<void>) => {
    setBusy(true); setError(null);
    try { await action(); }
    catch (error) { setError(error instanceof Error ? error.message : String(error)); }
    finally { setBusy(false); }
  };
  const date = (value?: string) => value ? new Date(value).toLocaleString() : "Unknown";

  return <section role="dialog" aria-modal="true" aria-labelledby="drive-duplicates-title" className="absolute inset-0 z-[60] flex flex-col bg-[#1c1d1e] px-5 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-[calc(env(safe-area-inset-top)+1rem)] text-[#f5f3ef]">
    <header className="flex shrink-0 items-center justify-between gap-3">
      <h2 id="drive-duplicates-title" className="text-lg font-semibold">Review duplicate names</h2>
      <button disabled={busy} onClick={onClose} className="p-3 text-sm disabled:opacity-40">Back</button>
    </header>
    <div className="min-h-0 flex-1 overflow-y-auto pb-4">
      <p className="mt-3 break-words text-sm text-[#ef847d]">{conflict.path}</p>
      <p className="mt-3 text-sm leading-5 text-[#aaa6a1]">These items share a name. Preview the copies, then rename the ones you want to distinguish. Keep the original name on the copy your existing links should open. Renaming changes Google Drive on all devices and preserves both copies.</p>
      {conflict.items.map((item, index) => {
        const suggested = item.mimeType === DRIVE_FOLDER ? `${item.name} (copy ${index + 1})` : item.name.replace(/(\.[^.]+)?$/, ` (copy ${index + 1})$1`);
        const canPreview = !item.mimeType.startsWith("application/vnd.google-apps.") && (item.mimeType.startsWith("text/") || /\.(md|txt|json|csv)$/i.test(item.name));
        return <article key={item.id} className="mt-4 rounded-xl bg-[#292a2b] p-4">
          <h3 className="break-words font-semibold">Copy {index + 1}: {item.name}</h3>
          <p className="mt-2 text-xs text-[#aaa6a1]">{item.mimeType === DRIVE_FOLDER ? "Folder" : item.mimeType === "application/vnd.google-apps.shortcut" ? "Shortcut" : "File"} · Modified {date(item.modifiedTime)}</p>
          <p className="mt-1 text-xs text-[#aaa6a1]">Created {date(item.createdTime)}</p>
          {canPreview ? <button disabled={busy} onClick={() => void run(async () => {
            const text = await vault.previewDuplicate(conflict, item.id);
            setPreviews((value) => ({ ...value, [item.id]: text }));
          })} className="mt-3 py-2 text-sm underline disabled:opacity-40">Preview this copy</button> : <p className="mt-3 text-xs text-[#aaa6a1]">Text preview unavailable for this item.</p>}
          {previews[item.id] !== undefined && <pre tabIndex={0} aria-label={`Preview of copy ${index + 1}`} className="mt-2 max-h-52 overflow-auto whitespace-pre-wrap break-words rounded bg-black/20 p-3 text-xs">{previews[item.id] || "Empty file"}</pre>}
          <label className="mt-3 block text-sm">New name for copy {index + 1}
            <input disabled={busy} value={names[item.id] ?? suggested} onChange={(event) => setNames((value) => ({ ...value, [item.id]: event.target.value }))} className="mt-2 w-full rounded border border-white/20 bg-[#1c1d1e] p-3" />
          </label>
          <button disabled={busy || !(names[item.id] ?? suggested).trim()} onClick={() => void run(async () => {
            await vault.renameDuplicate(conflict, item.id, names[item.id] ?? suggested);
            await onRefresh();
          })} className="mt-3 w-full rounded-lg bg-[#df5149] px-3 py-3 text-sm font-semibold disabled:opacity-40">Rename this copy and continue</button>
        </article>;
      })}
      {error && <p role="alert" className="mt-4 text-sm text-[#ef847d]">{error}</p>}
    </div>
    {busy && <p role="status" className="py-2 text-center text-sm">Checking Google Drive…</p>}
    <button disabled={busy} onClick={() => void run(onRefresh)} className="shrink-0 py-3 text-sm underline disabled:opacity-40">Refresh review / retry opening vault</button>
  </section>;
}
