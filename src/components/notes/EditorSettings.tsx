import { Switch } from "@/components/ui/switch";
import { saveCodeBlocksEnabled, useCodeBlocksEnabled, saveNoteLinkShortcutsEnabled, useNoteLinkShortcutsEnabled } from "@/lib/editor-preferences";

export function EditorSettings() {
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
  </section>;
}
