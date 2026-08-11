import { useEffect, useRef, useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Loader2,
  Maximize,
  Minimize,
  ZoomIn,
  ZoomOut,
} from "@/lib/icons";
import {
  GlobalWorkerOptions,
  getDocument,
  type PDFDocumentProxy,
} from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

GlobalWorkerOptions.workerSrc = workerUrl;

function PdfPage({
  pdf,
  pageNumber,
  scale,
}: {
  pdf: PDFDocumentProxy;
  pageNumber: number;
  scale: number;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [visible, setVisible] = useState(pageNumber <= 2);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) setVisible(true);
      },
      { rootMargin: "600px" },
    );
    observer.observe(host);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!visible || !canvasRef.current) return;
    let cancelled = false;
    let renderTask: { cancel: () => void; promise: Promise<unknown> } | null = null;
    void pdf.getPage(pageNumber).then((page) => {
      if (cancelled || !canvasRef.current) return;
      const viewport = page.getViewport({ scale });
      const outputScale = window.devicePixelRatio || 1;
      const canvas = canvasRef.current;
      const context = canvas.getContext("2d");
      if (!context) return;
      canvas.width = Math.floor(viewport.width * outputScale);
      canvas.height = Math.floor(viewport.height * outputScale);
      canvas.style.width = `${Math.floor(viewport.width)}px`;
      canvas.style.height = `${Math.floor(viewport.height)}px`;
      renderTask = page.render({
        canvas,
        canvasContext: context,
        viewport,
        transform: outputScale === 1 ? undefined : [outputScale, 0, 0, outputScale, 0, 0],
      });
      return renderTask.promise;
    }).catch((error) => {
      if (!cancelled && error?.name !== "RenderingCancelledException") {
        console.error("Zerus: failed to render PDF page", error);
      }
    });
    return () => {
      cancelled = true;
      renderTask?.cancel();
    };
  }, [pageNumber, pdf, scale, visible]);

  return (
    <div
      ref={hostRef}
      data-pdf-page={pageNumber}
      className="mx-auto min-h-40 w-fit max-w-full overflow-hidden rounded-sm bg-white shadow"
    >
      <canvas ref={canvasRef} className="block max-w-full" />
    </div>
  );
}

export function PdfViewer({
  loadBytes,
  version,
  isFullHeight = false,
  onToggleFullHeight,
}: {
  loadBytes: () => Promise<Uint8Array>;
  version: string;
  isFullHeight?: boolean;
  onToggleFullHeight?: () => void;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [pdf, setPdf] = useState<PDFDocumentProxy | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [passwordRequest, setPasswordRequest] = useState<((password: string) => void) | null>(null);
  const [password, setPassword] = useState("");
  const [scale, setScale] = useState(1.25);
  const [page, setPage] = useState(1);

  useEffect(() => {
    let cancelled = false;
    let loadingTask: ReturnType<typeof getDocument> | null = null;
    setLoading(true);
    setError(null);
    setPdf(null);
    void loadBytes()
      .then((bytes) => {
        if (cancelled) return null;
        loadingTask = getDocument({ data: bytes });
        loadingTask.onPassword = (updatePassword) => {
          if (!cancelled) setPasswordRequest(() => updatePassword);
        };
        return loadingTask.promise;
      })
      .then((document) => {
        if (!document || cancelled) return;
        setPdf(document);
        setPage(1);
      })
      .catch((cause) => {
        if (!cancelled) setError(cause instanceof Error ? cause.message : String(cause));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
      void loadingTask?.destroy();
    };
  }, [loadBytes, version]);

  const goToPage = (next: number) => {
    if (!pdf) return;
    const clamped = Math.max(1, Math.min(pdf.numPages, next));
    setPage(clamped);
    scrollRef.current
      ?.querySelector(`[data-pdf-page="${clamped}"]`)
      ?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  if (loading) {
    return <div className="flex h-full items-center justify-center gap-2 text-sm text-muted-foreground"><Loader2 className="animate-spin" size={16} /> Loading PDF…</div>;
  }
  if (passwordRequest) {
    return (
      <form
        className="mx-auto flex max-w-sm items-center gap-2 p-6"
        onSubmit={(event) => {
          event.preventDefault();
          passwordRequest(password);
          setPasswordRequest(null);
          setPassword("");
        }}
      >
        <Input type="password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="PDF password" />
        <Button type="submit">Unlock</Button>
      </form>
    );
  }
  if (error || !pdf) {
    return <div className="flex h-full items-center justify-center p-6 text-center text-sm text-destructive">{error ?? "This PDF could not be opened."}</div>;
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex flex-wrap items-center gap-1 border-b bg-background/90 px-2 py-1.5">
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => goToPage(page - 1)} disabled={page <= 1}><ChevronLeft size={14} /></Button>
        <span className="min-w-16 text-center text-xs tabular-nums">{page} / {pdf.numPages}</span>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => goToPage(page + 1)} disabled={page >= pdf.numPages}><ChevronRight size={14} /></Button>
        <div className="mx-1 h-5 w-px bg-border" />
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => setScale((value) => Math.max(0.5, value - 0.2))}><ZoomOut size={14} /></Button>
        <span className="w-12 text-center text-xs tabular-nums">{Math.round(scale * 100)}%</span>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => setScale((value) => Math.min(3, value + 0.2))}><ZoomIn size={14} /></Button>
        <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setScale(1.25)}>Fit width</Button>
        {onToggleFullHeight && (
          <Button
            variant="ghost"
            size="icon"
            className="ml-auto h-7 w-7 shrink-0"
            title={isFullHeight ? "Restore PDF and Markdown split" : "Expand PDF to full height"}
            aria-label={isFullHeight ? "Restore PDF and Markdown split" : "Expand PDF to full height"}
            aria-pressed={isFullHeight}
            onClick={onToggleFullHeight}
          >
            {isFullHeight ? <Minimize size={14} /> : <Maximize size={14} />}
          </Button>
        )}
      </div>
      <div ref={scrollRef} className="min-h-0 flex-1 space-y-4 overflow-auto bg-muted/50 p-4" onScroll={(event) => {
        const pages = [...event.currentTarget.querySelectorAll<HTMLElement>("[data-pdf-page]")];
        const top = event.currentTarget.getBoundingClientRect().top;
        const nearest = pages.reduce((best, item) => Math.abs(item.getBoundingClientRect().top - top) < Math.abs(best.getBoundingClientRect().top - top) ? item : best, pages[0]);
        if (nearest) setPage(Number(nearest.dataset.pdfPage));
      }}>
        {Array.from({ length: pdf.numPages }, (_, index) => (
          <PdfPage key={index + 1} pdf={pdf} pageNumber={index + 1} scale={scale} />
        ))}
      </div>
    </div>
  );
}
