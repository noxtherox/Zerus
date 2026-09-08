import { findPdfMatches, type PdfSearch, type PdfMatch } from "@/lib/pdf-search";
import "./pdf-viewer.css";
import { useEffect, useRef, useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Loader2,
  Maximize,
  Minimize,
  Search,
  ZoomIn,
  ZoomOut,
} from "@/lib/icons";
import {
  TextLayer,
  GlobalWorkerOptions,
  getDocument,
  type PDFDocumentProxy,
} from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

GlobalWorkerOptions.workerSrc = workerUrl;
const EMPTY_MATCHES: PdfMatch[] = [];

function scrollToPdfTarget(target: Element | null, center = false) {
  const container = target?.closest<HTMLElement>("[data-pdf-scroll]");
  if (!target || !container) return;
  const bounds = target.getBoundingClientRect();
  const viewport = container.getBoundingClientRect();
  container.scrollTo({
    top: container.scrollTop + bounds.top - viewport.top - (center ? (container.clientHeight - bounds.height) / 2 : 0),
    left: center ? container.scrollLeft + bounds.left - viewport.left - (container.clientWidth - bounds.width) / 2 : container.scrollLeft,
  });
}

function PdfPage({
  pdf,
  pageNumber,
  scale,
  matches,
  activeMatch,
}: {
  pdf: PDFDocumentProxy;
  pageNumber: number;
  scale: number;
  matches: PdfMatch[];
  activeMatch?: PdfMatch;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const textRef = useRef<HTMLDivElement>(null);
  const [textLayer, setTextLayer] = useState<{ layer: TextLayer; offsets: number[] } | null>(null);
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

  const shouldRender = visible || !!activeMatch;
  useEffect(() => {
    if ((!shouldRender) || !canvasRef.current) return;
    let cancelled = false;
    let layer: TextLayer | null = null;
    setTextLayer(null);
    let renderTask: { cancel: () => void; promise: Promise<unknown> } | null = null;
    void pdf.getPage(pageNumber).then(async (page) => {
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
      await renderTask.promise;
      const content = await page.getTextContent();
      if (cancelled || !textRef.current) return;
      textRef.current.replaceChildren();
      textRef.current.style.setProperty("--total-scale-factor", String(scale));
      layer = new TextLayer({ textContentSource: content, container: textRef.current, viewport });
      await layer.render();
      if (!cancelled) {
        let offset = 0;
        const offsets = content.items.flatMap((item) => {
          if (!("str" in item)) return [];
          const start = offset;
          offset += item.str.length + (item.hasEOL ? 1 : 0);
          return [start];
        });
        setTextLayer({ layer, offsets });
      }
    }).catch((error) => {
      if (!cancelled && error?.name !== "RenderingCancelledException") {
        console.error("Zerus: failed to render PDF page", error);
      }
    });
    return () => {
      cancelled = true;
      renderTask?.cancel();
      layer?.cancel();
    };
  }, [pageNumber, pdf, scale, shouldRender]);

  useEffect(() => {
    if (!textLayer) return;
    textLayer.layer.textDivs.forEach((div, index) => {
      const text = textLayer.layer.textContentItemsStr[index];
      const offset = textLayer.offsets[index];
      div.replaceChildren();
      let cursor = 0;
      for (const match of matches) {
        if (match.page !== pageNumber) continue;
        const start = Math.max(0, match.start - offset);
        const end = Math.min(text.length, match.end - offset);
        if (start >= end) continue;
        div.append(document.createTextNode(text.slice(cursor, start)));
        const mark = document.createElement("mark");
        mark.textContent = text.slice(start, end);
        mark.className = match === activeMatch ? "pdf-match active" : "pdf-match";
        div.append(mark);
        cursor = end;
      }
      div.append(document.createTextNode(text.slice(cursor)));
    });
    scrollToPdfTarget(textRef.current?.querySelector(".pdf-match.active") ?? null, true);
  }, [textLayer, matches, activeMatch, pageNumber]);

  return (
    <div
      ref={hostRef}
      data-pdf-page={pageNumber}
      className="relative mx-auto min-h-40 w-fit shrink-0 overflow-hidden rounded-sm bg-white shadow"
    >
      <canvas ref={canvasRef} className="block" />
      <div ref={textRef} className="zerus-pdf-text" />
    </div>
  );
}

export function PdfViewer({
  loadBytes,
  search,
  onFind,
  version,
  isFullHeight = false,
  onToggleFullHeight,
}: {
  loadBytes: () => Promise<Uint8Array>;
  search?: PdfSearch;
  onFind?: () => void;
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
  const [fitWidth, setFitWidth] = useState(true);
  const [page, setPage] = useState(1);

  useEffect(() => {
    let cancelled = false;
    let loadingTask: ReturnType<typeof getDocument> | null = null;
    setLoading(true);
    setError(null);
    setPasswordRequest(null);
    setPassword("");
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

  useEffect(() => {
    const container = scrollRef.current;
    if (!pdf || loading || !container || !fitWidth) return;
    let cancelled = false;
    let observer: ResizeObserver | undefined;
    void pdf.getPage(1).then((firstPage) => {
      if (cancelled) return;
      const width = firstPage.getViewport({ scale: 1 }).width;
      const fit = () => setScale(Math.max(0.25, Math.min(3, (container.clientWidth - 32) / width)));
      fit();
      observer = new ResizeObserver(fit);
      observer.observe(container);
    }).catch(() => undefined);
    return () => { cancelled = true; observer?.disconnect(); };
  }, [pdf, loading, fitWidth]);

  const [pages, setPages] = useState<string[] | null>(null);
  const setStatus = search?.setStatus;
  const setMatches = search?.setMatches;
  const setActive = search?.setActive;
  const query = search?.query ?? "";
  useEffect(() => {
    let cancelled = false;
    setPages(null);
    setStatus?.(error ? "PDF unavailable" : "Loading PDF…");
    if (pdf) {
      setStatus?.("Reading PDF text…");
      void (async () => {
        const texts: string[] = [];
        for (let number = 1; number <= pdf.numPages; number++) {
          const page = await pdf.getPage(number);
          const content = await page.getTextContent();
          if (cancelled) return;
          texts.push(content.items.map((item) => "str" in item ? item.str + (item.hasEOL ? "\n" : "") : "").join(""));
        }
        if (!cancelled) {
          setPages(texts);
          setStatus?.(texts.some((text) => text.trim()) ? "" : "No text layer");
        }
      })().catch(() => { if (!cancelled) setStatus?.("Could not read PDF text"); });
    }
    return () => { cancelled = true; };
  }, [pdf, error, setStatus]);

  useEffect(() => {
    setMatches?.(pages ? findPdfMatches(pages, query) : []);
    setActive?.(0);
  }, [pages, query, setMatches, setActive]);
  const activeMatch = search?.matches[search.active];
  useEffect(() => {
    if (!activeMatch) return;
    setPage(activeMatch.page);
    scrollToPdfTarget(scrollRef.current?.querySelector(`[data-pdf-page="${activeMatch.page}"]`) ?? null);
  }, [activeMatch]);

  const goToPage = (next: number) => {
    if (!pdf) return;
    const clamped = Math.max(1, Math.min(pdf.numPages, next));
    setPage(clamped);
    scrollToPdfTarget(scrollRef.current?.querySelector(`[data-pdf-page="${clamped}"]`) ?? null);
  };

  if (loading && !passwordRequest) {
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
    <div data-pdf-viewer tabIndex={-1} className="flex h-full min-h-0 flex-col">
      <div className="flex flex-wrap items-center gap-1 border-b bg-background/90 px-2 py-1.5">
        <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Previous PDF page" onClick={() => goToPage(page - 1)} disabled={page <= 1}><ChevronLeft size={14} /></Button>
        <span className="min-w-16 text-center text-xs tabular-nums">{page} / {pdf.numPages}</span>
        <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Next PDF page" onClick={() => goToPage(page + 1)} disabled={page >= pdf.numPages}><ChevronRight size={14} /></Button>
        <div className="mx-1 h-5 w-px bg-border" />
        <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Zoom out" onClick={() => { setFitWidth(false); setScale((value) => Math.max(0.25, value - 0.2)); }}><ZoomOut size={14} /></Button>
        <span className="w-12 text-center text-xs tabular-nums">{Math.round(scale * 100)}%</span>
        <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Zoom in" onClick={() => { setFitWidth(false); setScale((value) => Math.min(3, value + 0.2)); }}><ZoomIn size={14} /></Button>
        <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setFitWidth(true)}>Fit width</Button>
        {onFind && <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Find in PDF" title="Find in PDF (⌘F / Ctrl+F)" onClick={onFind}><Search size={14} /></Button>}
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
      <div ref={scrollRef} data-pdf-scroll className="min-h-0 flex-1 space-y-4 overflow-auto bg-muted/50 p-4" onScroll={(event) => {
        const pages = [...event.currentTarget.querySelectorAll<HTMLElement>("[data-pdf-page]")];
        const top = event.currentTarget.getBoundingClientRect().top;
        const nearest = pages.reduce((best, item) => Math.abs(item.getBoundingClientRect().top - top) < Math.abs(best.getBoundingClientRect().top - top) ? item : best, pages[0]);
        if (nearest) setPage(Number(nearest.dataset.pdfPage));
      }}>
        {Array.from({ length: pdf.numPages }, (_, index) => (
          <PdfPage key={index + 1} pdf={pdf} pageNumber={index + 1} scale={scale} matches={search?.matches ?? EMPTY_MATCHES} activeMatch={activeMatch?.page === index + 1 ? activeMatch : undefined} />
        ))}
      </div>
    </div>
  );
}
