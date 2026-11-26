import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { saveCodeBlocksEnabled, useCodeBlocksEnabled, saveNoteLinkShortcutsEnabled, useNoteLinkShortcutsEnabled } from "@/lib/editor-preferences";

export function EditorSettings({ desktopTransfer = false, vaultLocation }: { desktopTransfer?: boolean; vaultLocation?: string | null }) {
  const [exporting, setExporting] = useState(false);
  const [message, setMessage] = useState("");
  const enabled = useCodeBlocksEnabled();
  const noteShortcutsEnabled = useNoteLinkShortcutsEnabled();
  return <section className="mb-5">
    <h3 className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Editor</h3>
    <div className="mb-3 flex items-center justify-between gap-4 rounded-lg border border-border p-3">
      <div>
        <label htmlFor="note-link-shortcuts" className="text-sm font-medium">Note link shortcuts</label>
        <p id="note-link-shortcuts-description" className="mt-0.5 text-xs text-muted-foreground">
          Type @ or [[ to find and link a note while writing.
        </p>
      </div>
      <Switch id="note-link-shortcuts" aria-describedby="note-link-shortcuts-description" checked={noteShortcutsEnabled} onCheckedChange={saveNoteLinkShortcutsEnabled} />
    </div>
    <div className="flex items-center justify-between gap-4 rounded-lg border border-border p-3">
      <div>
        <label htmlFor="code-blocks" className="text-sm font-medium">Code blocks</label>
        <p id="code-blocks-description" className="mt-0.5 text-xs text-muted-foreground">
          Add code blocks with the toolbar, triple backticks, or paste. Existing blocks stay editable when this is off.
        </p>
      </div>
      <Switch id="code-blocks" aria-describedby="code-blocks-description" checked={enabled} onCheckedChange={saveCodeBlocksEnabled} />
    </div>
    {desktopTransfer ? <div className="mt-3">
      <Button variant="outline" size="sm" disabled={exporting} onClick={async () => {
        setExporting(true); setMessage("");
        try { const { exportDesktopSettings } = await import("@/lib/desktop-settings-transfer"); if (await exportDesktopSettings(vaultLocation) === "saved") setMessage("Settings exported. In the native Zerus app, choose File → Import Desktop Settings…"); }
        catch { setMessage("Settings could not be exported. Try another destination."); }
        finally { setExporting(false); }
      }}>Export desktop settings…</Button>
      <p className="mt-2 text-xs text-muted-foreground">Transfer appearance, colours, saved themes, dates, zoom and editor preferences to the native Zerus app. {vaultLocation ? "Includes this vault’s default folder, folder order, keep-open choices and subtype visibility." : ""}</p>
      {message && <p role="status" className="mt-2 text-xs text-muted-foreground">{message}</p>}
    </div> : null}
  </section>;
}
