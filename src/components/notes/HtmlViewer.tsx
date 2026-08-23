import { useEffect, useState } from "react";
import { Loader2, Maximize, Minimize } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  analyzeHtmlPreview,
  htmlPreviewFingerprint,
  prepareFullHtmlPreview,
  prepareHtmlPreview,
  type HtmlPreviewAnalysis,
} from "@/lib/html-preview";
import type { HtmlPreviewMode } from "@/lib/note-preferences";

export function HtmlViewer({
  loadBytes,
  version,
  mode,
  approvedFingerprint,
  onApprovalExpired,
  isFullHeight = false,
  onToggleFullHeight,
}: {
  loadBytes: () => Promise<Uint8Array>;
  version: string;
  mode: Exclude<HtmlPreviewMode, "link">;
  approvedFingerprint?: string | null;
  onApprovalExpired?: (analysis: HtmlPreviewAnalysis, fingerprint: string) => void;
  isFullHeight?: boolean;
  onToggleFullHeight?: () => void;
}) {
  const [html, setHtml] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setHtml(null);
    setError(null);
    void loadBytes()
      .then(async (bytes) => {
        if (!cancelled) {
          const source = new TextDecoder("utf-8").decode(bytes);
          const analysis = analyzeHtmlPreview(source);
          if (mode === "full") {
            const fingerprint = await htmlPreviewFingerprint(bytes);
            if (cancelled) return;
            if (!approvedFingerprint || fingerprint !== approvedFingerprint) {
              setError("Full preview approval expired because this file changed.");
              onApprovalExpired?.(analysis, fingerprint);
              return;
            }
            setHtml(prepareFullHtmlPreview(source, analysis));
          } else {
            setHtml(prepareHtmlPreview(source));
          }
        }
      })
      .catch((cause) => {
        if (!cancelled) setError(cause instanceof Error ? cause.message : String(cause));
      });
    return () => {
      cancelled = true;
    };
  }, [approvedFingerprint, loadBytes, mode, onApprovalExpired, version]);

  if (error) {
    return <div className="flex h-full items-center justify-center p-6 text-center text-sm text-destructive">{error}</div>;
  }
  if (html === null) {
    return <div className="flex h-full items-center justify-center gap-2 text-sm text-muted-foreground"><Loader2 className="animate-spin" size={16} /> Loading HTML…</div>;
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex items-center border-b bg-background/90 px-2 py-1.5">
        <span className="px-1 text-xs text-muted-foreground">
          {mode === "safe" ? "Safe preview · scripts disabled" : "Full preview · isolated"}
        </span>
        {onToggleFullHeight && (
          <Button
            variant="ghost"
            size="icon"
            className="ml-auto h-7 w-7 shrink-0"
            title={isFullHeight ? "Restore HTML and Markdown split" : "Expand HTML to full height"}
            aria-label={isFullHeight ? "Restore HTML and Markdown split" : "Expand HTML to full height"}
            aria-pressed={isFullHeight}
            onClick={onToggleFullHeight}
          >
            {isFullHeight ? <Minimize size={14} /> : <Maximize size={14} />}
          </Button>
        )}
      </div>
      <iframe
        key={`${mode}:${version}`}
        title="HTML file preview"
        sandbox={
          mode === "full"
            ? "allow-scripts allow-downloads"
            : ""
        }
        referrerPolicy="no-referrer"
        allow="camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'"
        srcDoc={html}
        className="min-h-0 flex-1 border-0 bg-white"
      />
    </div>
  );
}
