import { useState } from "react";

export interface PdfMatch { page: number; start: number; end: number }
export function findPdfMatches(pages: string[], query: string): PdfMatch[] {
  const normalize = (text: string) => text.normalize("NFKD").toLowerCase();
  const needle = normalize(query).replace(/\s+/g, " ");
  if (!needle.trim()) return [];
  return pages.flatMap((text, page) => {
    let normalized = "";
    const offsets: number[] = [];
    let offset = 0;
    for (const char of text) {
      for (const part of normalize(char)) {
        const value = /\s/.test(part) ? " " : part;
        if (value !== " " || !normalized.endsWith(" ")) {
          normalized += value;
          for (let i = 0; i < value.length; i++) offsets.push(offset);
        }
      }
      offset += char.length;
    }
    const matches: PdfMatch[] = [];
    for (let start = normalized.indexOf(needle); start >= 0; start = normalized.indexOf(needle, start + needle.length)) {
      const last = offsets[start + needle.length - 1];
      matches.push({ page: page + 1, start: offsets[start], end: last + (text.codePointAt(last)! > 0xffff ? 2 : 1) });
    }
    return matches;
  });
}

export function usePdfSearch() {
  const [scope, setScope] = useState<"note" | "pdf">("pdf");
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<PdfMatch[]>([]);
  const [active, setActive] = useState(0);
  const [status, setStatus] = useState("Loading PDF…");
  return { scope, setScope, query, setQuery, matches, setMatches, active, setActive, status, setStatus };
}
export type PdfSearch = ReturnType<typeof usePdfSearch>;
