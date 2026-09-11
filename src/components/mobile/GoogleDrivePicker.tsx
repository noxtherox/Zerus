import { useEffect, useState } from "react";
import { ArrowLeft, Cloud, Folder, Loader2, X } from "lucide-react";
import {
  DRIVE_FOLDER, driveCommand, driveTransport, listDriveChildren,
  type DriveAccount, type DriveFile, type DriveStatus, type DriveVaultSelection,
} from "@/lib/google-drive";

interface Props {
  onClose: () => void;
  onChoose: (selection: DriveVaultSelection) => Promise<boolean>;
}

export function GoogleDrivePicker({ onClose, onChoose }: Props) {
  const [account, setAccount] = useState<DriveAccount | null>(null);
  const [trail, setTrail] = useState([{ id: "root", name: "My Drive" }]);
  const [folders, setFolders] = useState<DriveFile[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState(0);
  const current = trail[trail.length - 1];

  useEffect(() => {
    let cancelled = false;
    setBusy(true);
    setError(null);
    setFolders([]);
    void (async () => {
      const status = await driveCommand<DriveStatus>({ operation: "status" });
      if (!status.account) return;
      if (!cancelled) setAccount(status.account);
      const entries = await listDriveChildren(driveTransport(status.account.accountId), current.id);
      if (!cancelled) setFolders(entries.filter((file) => file.mimeType === DRIVE_FOLDER).sort((a, b) => a.name.localeCompare(b.name)));
    })().catch((error: unknown) => { if (!cancelled) setError(String(error)); })
      .finally(() => { if (!cancelled) setBusy(false); });
    return () => { cancelled = true; };
  }, [current.id, retry]);

  const connect = async (reconnect = false) => {
    setBusy(true); setError(null);
    try {
      const status = await driveCommand<DriveStatus>({ operation: reconnect ? "reconnect" : "connect" });
      setAccount(status.account);
      setTrail([{ id: "root", name: "My Drive" }]);
      setRetry((value) => value + 1);
    } catch (error) { setError(String(error)); }
    finally { setBusy(false); }
  };
  const choose = async () => {
    if (!account || current.id === "root") return;
    setBusy(true); setError(null);
    try {
      if (await onChoose({ ...account, folderId: current.id, name: current.name })) onClose();
      else setError("The vault could not be opened. Check the connection and try again.");
    } catch (error) { setError(String(error)); }
    finally { setBusy(false); }
  };

  return <section role="dialog" aria-modal="true" aria-label="Open a Google Drive vault" className="absolute inset-0 z-[60] flex flex-col bg-[#1c1d1e] px-5 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-[calc(env(safe-area-inset-top)+1rem)]">
    <header className="flex items-center justify-between gap-3">
      <h2 className="flex items-center gap-2 text-lg font-semibold"><Cloud className="h-5 w-5" />Google Drive</h2>
      <button type="button" disabled={busy} onClick={onClose} aria-label="Close Google Drive" className="rounded-full p-3 disabled:opacity-40"><X className="h-5 w-5" /></button>
    </header>
    <p className="mt-3 text-sm leading-5 text-[#9a9691]">Choose the folder containing your vault. Changes save directly to Google Drive while you’re online.</p>
    {account ? <>
      <p className="mt-3 truncate text-xs text-[#9a9691]">{account.email}</p>
      <div className="mt-5 flex items-center gap-2 border-b border-white/10 pb-3">
        <button type="button" aria-label="Parent folder" disabled={busy || trail.length === 1} onClick={() => setTrail((value) => value.slice(0, -1))} className="p-2 disabled:opacity-30"><ArrowLeft className="h-5 w-5" /></button>
        <span className="truncate font-semibold">{current.name}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto py-2">
        {folders.map((folder) => <button key={folder.id} type="button" disabled={busy} onClick={() => setTrail((value) => [...value, { id: folder.id, name: folder.name }])} className="flex w-full items-center gap-3 border-b border-white/5 py-4 text-left disabled:opacity-40"><Folder className="h-5 w-5 shrink-0 text-[#ef6b62]" /><span className="break-words">{folder.name}</span></button>)}
        {!busy && !error && folders.length === 0 && <p className="py-6 text-sm text-[#9a9691]">No subfolders. You can use this folder as your vault.</p>}
      </div>
      <button type="button" disabled={busy || current.id === "root"} onClick={() => void choose()} className="mt-4 rounded-xl bg-[#df5149] px-4 py-4 font-semibold disabled:opacity-40">Open this vault</button>
      <button type="button" disabled={busy} onClick={() => void connect(true)} className="mt-3 py-2 text-xs text-[#9a9691]">Reconnect Google account</button>
    </> : <div className="flex flex-1 flex-col justify-center">
      <p className="mb-5 text-sm leading-6 text-[#9a9691]">Google will ask for permission to access your Drive files so Zerus can open an existing vault. Zerus uses the folder you choose. Your sign-in stays on this iPhone.</p>
      <button type="button" disabled={busy} onClick={() => void connect()} className="rounded-xl bg-[#df5149] px-4 py-4 font-semibold disabled:opacity-40">Connect Google Drive</button>
    </div>}
    {busy && <p role="status" className="mt-3 flex items-center justify-center gap-2 text-sm text-[#9a9691]"><Loader2 className="h-4 w-4 animate-spin" />Connecting…</p>}
    {error && <div role="alert" className="mt-3 rounded-xl bg-[#df5149]/10 p-3 text-sm text-[#ef847d]">{error}<button type="button" disabled={busy} onClick={() => setRetry((value) => value + 1)} className="mt-2 block underline">Retry</button></div>}
  </section>;
}
