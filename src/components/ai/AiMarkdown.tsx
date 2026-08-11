import type { ComponentPropsWithoutRef, MouseEvent } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { openExternalUrl } from "@/lib/external-links";
import { cn } from "@/lib/utils";

interface AiMarkdownProps {
  children: string;
  inverted?: boolean;
}

export function AiMarkdown({ children, inverted = false }: AiMarkdownProps) {
  const handleLinkClick = (
    event: MouseEvent<HTMLAnchorElement>,
    href: string | undefined,
  ) => {
    if (!href || !/^https?:\/\//i.test(href)) return;
    event.preventDefault();
    void openExternalUrl(href);
  };

  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        h1: ({ children: content }) => (
          <h1 className="mb-2 mt-4 text-xl font-semibold first:mt-0">{content}</h1>
        ),
        h2: ({ children: content }) => (
          <h2 className="mb-2 mt-4 text-lg font-semibold first:mt-0">{content}</h2>
        ),
        h3: ({ children: content }) => (
          <h3 className="mb-1.5 mt-3 text-base font-semibold first:mt-0">{content}</h3>
        ),
        h4: ({ children: content }) => (
          <h4 className="mb-1 mt-3 text-sm font-semibold first:mt-0">{content}</h4>
        ),
        p: ({ children: content }) => (
          <p className="my-2 break-words first:mt-0 last:mb-0">{content}</p>
        ),
        ul: ({ children: content }) => (
          <ul className="my-2 list-disc space-y-1 pl-5 marker:text-current/60">{content}</ul>
        ),
        ol: ({ children: content }) => (
          <ol className="my-2 list-decimal space-y-1 pl-5 marker:text-current/60">{content}</ol>
        ),
        li: ({ children: content, className }) => (
          <li className={cn("pl-0.5", className)}>{content}</li>
        ),
        blockquote: ({ children: content }) => (
          <blockquote className="my-2 border-l-2 border-current/25 pl-3 italic opacity-85">
            {content}
          </blockquote>
        ),
        a: ({ children: content, href, title }) => (
          <a
            href={href}
            title={title}
            className={cn(
              "font-medium underline decoration-current/40 underline-offset-2 hover:decoration-current",
              !inverted && "text-grim-link",
            )}
            onClick={(event) => handleLinkClick(event, href)}
            rel="noreferrer"
          >
            {content}
          </a>
        ),
        pre: ({ children: content }) => (
          <pre className="my-2 max-w-full overflow-x-auto rounded-md border border-current/10 bg-black/20 p-3 text-xs leading-relaxed">
            {content}
          </pre>
        ),
        code: ({ children: content, className }) => (
          <code
            className={cn(
              "rounded bg-black/15 px-1 py-0.5 font-mono text-[0.9em]",
              className?.startsWith("language-") && "bg-transparent p-0 text-xs",
              className,
            )}
          >
            {content}
          </code>
        ),
        table: ({ children: content }) => (
          <div className="my-3 max-w-full overflow-x-auto rounded-md border border-current/15">
            <table className="w-full border-collapse text-left text-xs">{content}</table>
          </div>
        ),
        thead: ({ children: content }) => (
          <thead className="bg-black/10 font-semibold">{content}</thead>
        ),
        th: ({ children: content }) => (
          <th className="border-b border-r border-current/15 px-2.5 py-2 last:border-r-0">{content}</th>
        ),
        td: ({ children: content }) => (
          <td className="border-b border-r border-current/10 px-2.5 py-2 align-top last:border-r-0">{content}</td>
        ),
        tr: ({ children: content }) => (
          <tr className="last:[&>td]:border-b-0">{content}</tr>
        ),
        hr: () => <hr className="my-4 border-current/15" />,
        input: ({
          checked,
          className,
          type,
        }: ComponentPropsWithoutRef<"input">) => (
          <input
            type={type}
            checked={checked}
            className={cn("mr-1.5 align-middle accent-current", className)}
            disabled
          />
        ),
      }}
    >
      {children}
    </ReactMarkdown>
  );
}
