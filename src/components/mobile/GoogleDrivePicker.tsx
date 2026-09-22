import { useEffect, useState } from "react";
import { ArrowLeft, Cloud, Folder, Loader2, X } from "lucide-react";
import { DriveDuplicateReview } from "./DriveDuplicateReview";
import { DriveDuplicateError, GoogleDriveVault } from "@/lib/vault/google-drive";
import {
  DRIVE_FOLDER, driveCommand, driveTransport, listDriveChildren,
  isDriveSignInExpired,
  type DriveAccount, type DriveFile, type DriveStatus, type DriveVaultSelection,
} from "@/lib/google-drive";

interface Props {
  onClose: () => void;
  onChoose: (selection: DriveVaultSelection) => Promise<boolean>;
  purpose?: "vault" | "file-location";
}

export function GoogleDrivePicker({ onClose, onChoose, purpose = "vault" }: Props) {
  const [account, setAccount] = useState<DriveAccount | null>(null);
  const [trail, setTrail] = useState([{ id: "root", name: "My Drive" }]);
  const [folders, setFolders] = useState<DriveFile[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState(0);
  const [review, setReview] = useState<{ vault: GoogleDriveVault; conflict: DriveDuplicateError } | null>(null);
  const current = trail[trail.length - 1];
  const reconnectRequired = error !== null && isDriveSignInExpired(error);

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
    if (!account || (purpose === "vault" && current.id === "root")) return;
    setBusy(true); setError(null);
    const selection = { ...account, folderId: current.id, name: current.name };
    const vault = new GoogleDriveVault(selection);
    try {
      // Vaults need a full ambiguity check. File locations resolve only the
      // linked file when opened, keeping large folder mappings quick.
      if (purpose === "vault") await vault.listNoteEntries();
      setReview(null);
      if (await onChoose(selection)) onClose();
      else setError("The vault could not be opened. Check the connection and try again.");
    } catch (error) {
      if (error instanceof DriveDuplicateError) setReview({ vault, conflict: error });
      else { setError(String(error)); if (review) throw error; }
    }
    finally { setBusy(false); }
  };

  if (review) return <DriveDuplicateReview key={`${review.conflict.path}:${review.conflict.items.map((item) => `${item.id}:${item.version}`).join(",")}`} vault={review.vault} conflict={review.conflict} onRefresh={choose} onClose={() => setReview(null)} />;

  const fileLocation = purpose === "file-location";
  return <section role="dialog" aria-modal="true" aria-label={fileLocation ? "Map a Google Drive file location" : "Open a Google Drive vault"} className="absolute inset-0 z-[60] flex flex-col bg-[#1c1d1e] px-5 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-[calc(env(safe-area-inset-top)+1rem)]">
    <header className="flex items-center justify-between gap-3">
      <h2 className="flex items-center gap-2 text-lg font-semibold"><Cloud className="h-5 w-5" />Google Drive</h2>
      <button type="button" disabled={busy} onClick={onClose} aria-label="Close Google Drive" className="rounded-full p-3 disabled:opacity-40"><X className="h-5 w-5" /></button>
    </header>
    <p className="mt-3 text-sm leading-5 text-[#9a9691]">{fileLocation ? "Choose the folder that corresponds to this synced file location. Zerus will use your existing Google Drive sign-in." : "Choose the folder containing your vault. Changes save directly to Google Drive while you’re online."}</p>
    {account ? <>
      <p className="mt-3 truncate text-xs text-[#9a9691]">{account.email}</p>
      <div className="mt-5 flex items-center gap-2 border-b border-white/10 pb-3">
        <button type="button" aria-label="Parent folder" disabled={busy || trail.length === 1} onClick={() => setTrail((value) => value.slice(0, -1))} className="p-2 disabled:opacity-30"><ArrowLeft className="h-5 w-5" /></button>
        <span className="truncate font-semibold">{current.name}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto py-2">
        {folders.map((folder) => <button key={folder.id} type="button" disabled={busy} onClick={() => setTrail((value) => [...value, { id: folder.id, name: folder.name }])} className="flex w-full items-center gap-3 border-b border-white/5 py-4 text-left disabled:opacity-40"><Folder className="h-5 w-5 shrink-0 text-[#ef6b62]" /><span className="break-words">{folder.name}</span></button>)}
        {!busy && !error && folders.length === 0 && <p className="py-6 text-sm text-[#9a9691]">No subfolders. You can use this folder {fileLocation ? "for the file location" : "as your vault"}.</p>}
      </div>
      <button type="button" disabled={busy || (!fileLocation && current.id === "root")} onClick={() => void choose()} className="mt-4 rounded-xl bg-[#df5149] px-4 py-4 font-semibold disabled:opacity-40">{fileLocation ? "Use this folder" : "Open this vault"}</button>
      <button type="button" disabled={busy} onClick={() => void connect(true)} className="mt-3 py-2 text-xs text-[#9a9691]">Reconnect Google account</button>
    </> : <div className="flex flex-1 flex-col justify-center">
      <p className="mb-5 text-sm leading-6 text-[#9a9691]">Google will ask for permission to access your Drive files so Zerus can {fileLocation ? "resolve linked files in the folder you choose" : "open an existing vault"}. Your sign-in stays on this iPhone.</p>
      <button type="button" disabled={busy} onClick={() => void connect()} className="rounded-xl bg-[#df5149] px-4 py-4 font-semibold disabled:opacity-40">Connect Google Drive</button>
    </div>}
    {busy && <p role="status" className="mt-3 flex items-center justify-center gap-2 text-sm text-[#9a9691]"><Loader2 className="h-4 w-4 animate-spin" />Connecting…</p>}
    {error && <div role="alert" className="mt-3 rounded-xl bg-[#df5149]/10 p-3 text-sm text-[#ef847d]">{error}<button type="button" disabled={busy} onClick={() => reconnectRequired ? void connect(true) : setRetry((value) => value + 1)} className="mt-2 block underline">{reconnectRequired ? "Reconnect Google account" : "Retry"}</button></div>}
  </section>;
}
