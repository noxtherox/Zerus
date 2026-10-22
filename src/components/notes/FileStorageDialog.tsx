import { Copy, Link2, FilePlus2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { FileStorageMode } from "@/lib/file-storage";

export interface FileStorageDialogProps {
  request: {
    fileName: string;
    canKeepExternal: boolean;
    purpose: "create" | "attach" | "copy";
  } | null;
  onChoose: (mode: FileStorageMode | null) => void;
}

export function FileStorageDialog({ request, onChoose }: FileStorageDialogProps) {
  const copying = request?.purpose === "copy";
  return (
    <Dialog open={request !== null} onOpenChange={(open) => { if (!open) onChoose(null); }}>
      <DialogContent className="text-foreground">
        <DialogHeader>
          <DialogTitle>{copying ? "Copy this file into the vault?" : "How should this file be stored?"}</DialogTitle>
          <DialogDescription>
            {copying
              ? "Zerus will copy the file into the vault and update this note to use the copy. The original file stays in its current location."
              : request?.canKeepExternal
                ? "Choose where the note’s file should live. The original file stays in its current location."
                : "The browser can store a vault copy. Keeping a connection to the original file is available in the native app."}
          </DialogDescription>
        </DialogHeader>
        <p className="break-all rounded-md bg-muted/60 p-3 text-sm">{request?.fileName}</p>
        <div className="space-y-2">
          <Button className="h-auto w-full justify-start gap-3 whitespace-normal py-3 text-left" onClick={() => onChoose("copy")}>
            <Copy className="h-4 w-4 shrink-0" aria-hidden="true" />
            <span><span className="block font-medium">Copy into Vault</span><span className="block text-xs opacity-80">Use a portable copy that travels with the vault.</span></span>
          </Button>
          {request?.canKeepExternal && !copying && (
            <>
              <Button variant="outline" className="h-auto w-full justify-start gap-3 whitespace-normal py-3 text-left" onClick={() => onChoose("external")}>
                <Link2 className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span><span className="block font-medium">Keep External Connection</span><span className="block text-xs text-muted-foreground">Keep using the original file in its current location.</span></span>
              </Button>
              <Button variant="outline" className="h-auto w-full justify-start gap-3 whitespace-normal py-3 text-left" onClick={() => onChoose("external-backup")}>
                <FilePlus2 className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span><span className="block font-medium">Keep External Connection + Backup</span><span className="block text-xs text-muted-foreground">Use the original file and attach a snapshot copy in the vault. The backup won’t update automatically.</span></span>
              </Button>
            </>
          )}
        </div>
        <DialogFooter><Button variant="outline" onClick={() => onChoose(null)}>Cancel</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
