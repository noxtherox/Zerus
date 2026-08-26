import { useEffect, useState } from "react";
import { Download, Loader2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { saveExportArtifact } from "@/lib/export-file";
import type { NoteExportFormat } from "@/lib/note-export";
import { noteTitle, type Note } from "@/lib/note-utils";
import { showError, showSuccess } from "@/utils/toast";

const FORMAT_DESCRIPTION: Record<NoteExportFormat, string> = {
  html: "A self-contained web page with local images embedded.",
  pdf: "A portable, paginated document suitable for printing and sharing.",
  docx: "An editable Microsoft Word document with native headings, lists, and tables.",
};

export function NoteExportDialog({
  note,
  open,
  onOpenChange,
}: {
  note: Note;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [format, setFormat] = useState<NoteExportFormat>("pdf");
  const [includeProperties, setIncludeProperties] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) setBusy(false);
  }, [open]);

  const exportNote = async () => {
    setBusy(true);
    try {
      const { createNoteExport } = await import("@/lib/note-export");
      const artifact = await createNoteExport(note, format, {
        includeProperties,
      });
      const result = await saveExportArtifact(artifact);
      if (result === "cancelled") return;
      onOpenChange(false);
      const warning = artifact.warnings.length
        ? ` ${artifact.warnings.length} item${artifact.warnings.length === 1 ? "" : "s"} could not be fully included.`
        : "";
      showSuccess(`${result === "shared" ? "Shared" : "Exported"} ${artifact.fileName}.${warning}`);
    } catch (error) {
      showError(`Could not export note: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Export note</DialogTitle>
          <DialogDescription className="truncate">
            {noteTitle(note)}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-5 py-1">
          <div className="space-y-2">
            <Label htmlFor="note-export-format">Format</Label>
            <Select value={format} onValueChange={(value) => setFormat(value as NoteExportFormat)} disabled={busy}>
              <SelectTrigger id="note-export-format">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="pdf">PDF document (.pdf)</SelectItem>
                <SelectItem value="docx">Word document (.docx)</SelectItem>
                <SelectItem value="html">Web page (.html)</SelectItem>
              </SelectContent>
            </Select>
            <p className="text-xs leading-relaxed text-muted-foreground">
              {FORMAT_DESCRIPTION[format]}
            </p>
          </div>
          <div className="flex items-center justify-between gap-4 rounded-lg border p-3">
            <div>
              <Label htmlFor="note-export-properties">Include properties</Label>
              <p className="mt-1 text-xs text-muted-foreground">
                Adds visible note properties as a compact table. Zerus metadata stays hidden.
              </p>
            </div>
            <Switch
              id="note-export-properties"
              checked={includeProperties}
              onCheckedChange={setIncludeProperties}
              disabled={busy}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void exportNote()} disabled={busy}>
            {busy ? <Loader2 className="mr-2 animate-spin" size={16} /> : <Download className="mr-2" size={16} />}
            {busy ? "Preparing…" : "Export"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
