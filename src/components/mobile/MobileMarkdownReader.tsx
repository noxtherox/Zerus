import { useEffect, useState, type ComponentPropsWithoutRef, type MouseEvent } from "react";
import ReactMarkdown, { defaultUrlTransform } from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Link, Parent, Root, Text } from "mdast";
import { openExternalUrl } from "@/lib/external-links";
import { parseImageAlt } from "@/lib/note-utils";
import { getImageUrl } from "@/store/notes-store";
import { cn } from "@/lib/utils";

const NOTE_LINK_PREFIX = "zerus-note:";
const WIKILINK = /\\?\[\\?\[([^\]]+)\]\]/g;

function rewriteWikilinks(node: Parent): void {
  const children = [];
  for (const child of node.children) {
    if (child.type === "text" && (child as Text).value.includes("[[")) {
      const value = (child as Text).value;
      let cursor = 0;
      for (const match of value.matchAll(WIKILINK)) {
        const index = match.index ?? 0;
        if (index > cursor) children.push({ type: "text", value: value.slice(cursor, index) });
        const [target, label] = match[1].split("|", 2).map((part) => part.trim());
        children.push({
          type: "link",
          url: `${NOTE_LINK_PREFIX}${encodeURIComponent(target)}`,
          children: [{ type: "text", value: label || target }],
        } satisfies Link);
        cursor = index + match[0].length;
      }
      if (cursor < value.length) children.push({ type: "text", value: value.slice(cursor) });
      continue;
    }
    if ("children" in child && Array.isArray(child.children)) rewriteWikilinks(child as Parent);
    children.push(child);
  }
  node.children = children;
}

function remarkWikilinks() {
  return (tree: Root) => rewriteWikilinks(tree);
}

function readerUrlTransform(url: string): string {
  return url.toLowerCase().startsWith(NOTE_LINK_PREFIX)
    ? url
    : defaultUrlTransform(url);
}

function noteLinkTarget(href: string | undefined): string | null {
  if (!href?.toLowerCase().startsWith(NOTE_LINK_PREFIX)) return null;
  try {
    return decodeURIComponent(href.slice(NOTE_LINK_PREFIX.length)).trim() || null;
  } catch {
    return null;
  }
}

function ReaderImage({ alt = "", src }: ComponentPropsWithoutRef<"img">) {
  const [url, setUrl] = useState<string | null>(null);
  const parsedAlt = parseImageAlt(alt);

  useEffect(() => {
    let cancelled = false;
    setUrl(null);
    if (!src) return () => { cancelled = true; };
    void getImageUrl(src).then((resolved) => {
      if (!cancelled) setUrl(resolved);
    });
    return () => { cancelled = true; };
  }, [src]);

  if (!url) return <span className="text-sm text-[#77736f]">{parsedAlt.alt || "Loading image…"}</span>;
  return (
    <img
      src={url}
      alt={parsedAlt.alt}
      width={parsedAlt.width ?? undefined}
      className="my-4 h-auto max-w-full rounded-[12px]"
    />
  );
}

interface MobileMarkdownReaderProps {
  markdown: string;
  onFollowLink: (title: string) => void;
}

export function MobileMarkdownReader({ markdown, onFollowLink }: MobileMarkdownReaderProps) {
  const handleLinkClick = (
    event: MouseEvent<HTMLAnchorElement>,
    href: string | undefined,
  ) => {
    const noteTitle = noteLinkTarget(href);
    if (noteTitle) {
      event.preventDefault();
      onFollowLink(noteTitle);
      return;
    }
    if (!href || !/^https?:\/\//i.test(href)) return;
    event.preventDefault();
    void openExternalUrl(href);
  };

  if (!markdown.trim()) {
    return <p className="py-3 text-[16px] text-[#77736f]">This note is empty.</p>;
  }

  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm, remarkWikilinks]}
      urlTransform={readerUrlTransform}
      components={{
        h1: ({ children }) => <h1 className="mb-3 mt-7 text-[28px] font-bold leading-tight first:mt-0">{children}</h1>,
        h2: ({ children }) => <h2 className="mb-2 mt-7 text-[23px] font-bold leading-tight first:mt-0">{children}</h2>,
        h3: ({ children }) => <h3 className="mb-2 mt-6 text-[19px] font-semibold leading-snug first:mt-0">{children}</h3>,
        h4: ({ children }) => <h4 className="mb-2 mt-5 text-[16px] font-semibold first:mt-0">{children}</h4>,
        p: ({ children }) => <p className="my-3 break-words text-[16px] leading-7 first:mt-0 last:mb-0">{children}</p>,
        ul: ({ children }) => <ul className="my-3 list-disc space-y-1.5 pl-6 text-[16px] leading-7 marker:text-[#77736f]">{children}</ul>,
        ol: ({ children }) => <ol className="my-3 list-decimal space-y-1.5 pl-6 text-[16px] leading-7 marker:text-[#77736f]">{children}</ol>,
        li: ({ children, className }) => <li className={cn("pl-0.5", className)}>{children}</li>,
        blockquote: ({ children }) => <blockquote className="my-4 border-l-2 border-[#df5149]/45 pl-4 italic text-[#aaa6a0]">{children}</blockquote>,
        a: ({ children, href, title }) => (
          <a
            href={href}
            title={title}
            className="font-medium text-[#ef6b62] underline decoration-[#ef6b62]/40 underline-offset-2"
            onClick={(event) => handleLinkClick(event, href)}
            rel="noreferrer"
          >
            {children}
          </a>
        ),
        pre: ({ children }) => <pre className="my-4 max-w-full overflow-x-auto rounded-[12px] border border-white/[0.08] bg-black/20 p-4 text-[13px] leading-6">{children}</pre>,
        code: ({ children, className }) => <code className={cn("rounded bg-black/20 px-1.5 py-0.5 font-mono text-[0.88em]", className?.startsWith("language-") && "bg-transparent p-0 text-[13px]", className)}>{children}</code>,
        table: ({ children }) => <div className="my-5 max-w-full overflow-x-auto rounded-[12px] border border-white/[0.1]"><table className="min-w-full border-collapse text-left text-[13px] leading-5">{children}</table></div>,
        thead: ({ children }) => <thead className="bg-white/[0.06] font-semibold">{children}</thead>,
        th: ({ children }) => <th className="min-w-[120px] border-b border-r border-white/[0.1] px-3 py-2.5 align-top last:border-r-0">{children}</th>,
        td: ({ children }) => <td className="min-w-[120px] border-b border-r border-white/[0.07] px-3 py-2.5 align-top last:border-r-0">{children}</td>,
        tr: ({ children }) => <tr className="last:[&>td]:border-b-0">{children}</tr>,
        hr: () => <hr className="my-7 border-white/[0.1]" />,
        img: ReaderImage,
        input: ({ checked, className, type }: ComponentPropsWithoutRef<"input">) => <input type={type} checked={checked} className={cn("mr-2 align-middle accent-[#df5149]", className)} disabled />,
      }}
    >
      {markdown}
    </ReactMarkdown>
  );
}
