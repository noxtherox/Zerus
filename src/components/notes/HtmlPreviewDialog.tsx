import { AlertTriangle, Check } from "@/lib/icons";
import {
  htmlPreviewNeedsPermission,
  type HtmlPreviewAnalysis,
} from "@/lib/html-preview";
import type { HtmlPreviewMode } from "@/lib/note-preferences";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

const choices: Array<{
  mode: HtmlPreviewMode;
  title: string;
  description: string;
}> = [
  {
    mode: "link",
    title: "Only link the file",
    description: "Do not render the HTML. It behaves like a PowerPoint file hub.",
  },
  {
    mode: "safe",
    title: "Safe preview",
    description: "Render the document with scripts and external resources disabled.",
  },
  {
    mode: "full",
    title: "Full preview",
    description: "Run its scripts and load external dependencies inside an isolated preview.",
  },
];

function warningText(analysis: HtmlPreviewAnalysis | null): string {
  if (analysis && !htmlPreviewNeedsPermission(analysis)) {
    return "No scripts or external dependencies were detected in this file.";
  }
  if (analysis?.externalScriptUrls.length) {
    return "This file calls external scripts, which could be malicious.";
  }
  if (analysis?.hasScripts && analysis.externalUrls.length) {
    return "This file contains scripts and loads content from external URLs, which could be malicious.";
  }
  if (analysis?.hasScripts) {
    return "This file contains scripts, which could be malicious.";
  }
  return "This file loads content from external URLs, which could track you or be malicious.";
}

export function HtmlPreviewDialog({
  open,
  onOpenChange,
  fileName,
  analysis,
  currentMode,
  onChoose,
  unavailableReason,
  fullPreviewReady = true,
  approvalExpired = false,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  fileName: string;
  analysis: HtmlPreviewAnalysis | null;
  currentMode: HtmlPreviewMode | null;
  onChoose: (mode: HtmlPreviewMode) => void;
  unavailableReason?: string | null;
  fullPreviewReady?: boolean;
  approvalExpired?: boolean;
}) {
  const risky = !analysis || htmlPreviewNeedsPermission(analysis);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Choose file preview</DialogTitle>
          <DialogDescription className="break-all">{fileName}</DialogDescription>
        </DialogHeader>
        <div
          className={cn(
            "flex gap-3 rounded-lg border p-3 text-sm",
            risky
              ? "border-amber-500/30 bg-amber-500/10"
              : "border-emerald-500/30 bg-emerald-500/10",
          )}
        >
          {risky ? (
            <AlertTriangle className="mt-0.5 shrink-0 text-amber-600" size={18} />
          ) : (
            <Check className="mt-0.5 shrink-0 text-emerald-600" size={18} />
          )}
          <div className="min-w-0">
            <p className="font-medium text-foreground">
              {unavailableReason ?? (approvalExpired
                ? "This file changed since Full preview was approved. Review it and choose again."
                : warningText(analysis))}
            </p>
            {analysis?.domains.length ? (
              <p className="mt-1 break-words text-xs text-muted-foreground">
                External domains: {analysis.domains.join(", ")}
              </p>
            ) : null}
          </div>
        </div>
        <div className="grid gap-2">
          {choices.map((choice) => {
            const disabled = Boolean(
              (unavailableReason && choice.mode !== "link") ||
              (choice.mode === "full" && !fullPreviewReady),
            );
            return (
            <button
              key={choice.mode}
              type="button"
              className={cn(
                "flex w-full items-start gap-3 rounded-lg border p-3 text-left transition-colors hover:bg-muted/60",
                currentMode === choice.mode && "border-zerus-accent bg-zerus-accent/5",
                choice.mode === "full" && "border-amber-500/40",
                disabled && "cursor-not-allowed opacity-50 hover:bg-transparent",
              )}
              disabled={disabled}
              onClick={() => onChoose(choice.mode)}
            >
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-semibold">{choice.title}</span>
                <span className="mt-0.5 block text-xs leading-relaxed text-muted-foreground">
                  {choice.description}
                </span>
              </span>
              {currentMode === choice.mode ? (
                <Check className="mt-0.5 shrink-0 text-zerus-accent" size={17} />
              ) : null}
            </button>
            );
          })}
        </div>
        <p className="text-xs text-muted-foreground">
          Full preview permits scripts and downloads. Direct resource and API requests are limited to the external origins detected when you approve the current file contents.
        </p>
      </DialogContent>
    </Dialog>
  );
}
