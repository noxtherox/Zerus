import type {
  BlockContent,
  Link,
  PhrasingContent,
  Root,
  RootContent,
  Text,
} from "mdast";
import { unified } from "unified";
import remarkFrontmatter from "remark-frontmatter";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import rehypeSanitize, { defaultSchema } from "rehype-sanitize";
import rehypeStringify from "rehype-stringify";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import {
  isRemoteUrl,
  noteTitle,
  parseImageAlt,
  type Note,
} from "@/lib/note-utils";
import { readVaultImage } from "@/store/notes-store";

export type NoteExportFormat = "html" | "pdf" | "docx";

export interface NoteExportOptions {
  includeProperties: boolean;
}

export interface NoteExportArtifact {
  blob: Blob;
  fileName: string;
  format: NoteExportFormat;
  warnings: string[];
}

export type ExportImageLoader = (path: string) => Promise<Uint8Array | null>;

interface ExportContext {
  tree: Root;
  title: string;
  properties: Array<[string, PropertyValue]>;
  loadImage: ExportImageLoader;
  warnings: string[];
}

interface LoadedImage {
  data: Uint8Array;
  mimeType: string;
  width: number;
  height: number;
}

const INTERNAL_PROPERTY = /^zerus-/i;
const WIKILINK = /\\?\[\\?\[([^\]]+)\]\]/g;

function safeFileStem(value: string): string {
  const withoutControls = Array.from(value, (character) =>
    character.charCodeAt(0) < 32 ? "-" : character,
  ).join("");
  const cleaned = withoutControls
    .replace(/[<>:"/\\|?*]/g, "-")
    .replace(/\s+/g, " ")
    .replace(/[. ]+$/g, "")
    .trim();
  return (cleaned || "Untitled note").slice(0, 120);
}

function displayProperty(value: PropertyValue): string {
  return Array.isArray(value) ? value.join(", ") : String(value);
}

function splitWikilinks(value: string): PhrasingContent[] {
  const children: PhrasingContent[] = [];
  let cursor = 0;
  for (const match of value.matchAll(WIKILINK)) {
    const index = match.index ?? 0;
    if (index > cursor) {
      children.push({ type: "text", value: value.slice(cursor, index) });
    }
    const [target, label] = match[1].split("|", 2).map((part) => part.trim());
    const link: Link = {
      type: "link",
      url: `zerus-note:${encodeURIComponent(target)}`,
      children: [{ type: "text", value: label || target }],
    };
    children.push(link);
    cursor = index + match[0].length;
  }
  if (cursor < value.length) {
    children.push({ type: "text", value: value.slice(cursor) });
  }
  return children.length ? children : [{ type: "text", value }];
}

function rewriteWikilinks(node: { children?: unknown[] }): void {
  if (!node.children) return;
  const next: unknown[] = [];
  for (const child of node.children) {
    if (
      child &&
      typeof child === "object" &&
      (child as Text).type === "text" &&
      (child as Text).value.includes("[[")
    ) {
      next.push(...splitWikilinks((child as Text).value));
      continue;
    }
    if (child && typeof child === "object") {
      rewriteWikilinks(child as { children?: unknown[] });
    }
    next.push(child);
  }
  node.children = next;
}

export function parseNoteForExport(note: Note): Root {
  const processor = unified()
    .use(remarkParse)
    .use(remarkFrontmatter, ["yaml"])
    .use(remarkGfm);
  const tree = processor.parse(note.content) as Root;
  tree.children = tree.children.filter((child) => child.type !== "yaml");
  rewriteWikilinks(tree as { children?: unknown[] });
  return tree;
}

function exportProperties(note: Note, include: boolean) {
  if (!include) return [];
  return Object.entries(getNoteProperties(note.content)).filter(
    ([key]) => !INTERNAL_PROPERTY.test(key),
  );
}

function extensionMime(path: string): string {
  const clean = path.split(/[?#]/, 1)[0].toLowerCase();
  if (/\.jpe?g$/.test(clean)) return "image/jpeg";
  if (/\.gif$/.test(clean)) return "image/gif";
  if (/\.bmp$/.test(clean)) return "image/bmp";
  if (/\.svg$/.test(clean)) return "image/svg+xml";
  if (/\.webp$/.test(clean)) return "image/webp";
  return "image/png";
}

function bytesToDataUrl(bytes: Uint8Array, mimeType: string): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return `data:${mimeType};base64,${btoa(binary)}`;
}

async function imageDimensions(bytes: Uint8Array, mimeType: string) {
  const blob = new Blob([bytes as BlobPart], { type: mimeType });
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(blob);
      const dimensions = { width: bitmap.width, height: bitmap.height };
      bitmap.close();
      return dimensions;
    } catch {
      // Fall through to the DOM image loader.
    }
  }
  if (typeof Image !== "undefined") {
    const url = URL.createObjectURL(blob);
    try {
      const image = new Image();
      const dimensions = await new Promise<{ width: number; height: number }>(
        (resolve, reject) => {
          image.onload = () =>
            resolve({
              width: image.naturalWidth || image.width,
              height: image.naturalHeight || image.height,
            });
          image.onerror = () => reject(new Error("Image dimensions unavailable"));
          image.src = url;
        },
      );
      return dimensions;
    } catch {
      // A readable placeholder size is preferable to failing the whole export.
    } finally {
      URL.revokeObjectURL(url);
    }
  }
  return { width: 800, height: 500 };
}

async function loadLocalImage(
  path: string,
  context: ExportContext,
): Promise<LoadedImage | null> {
  if (isRemoteUrl(path) || path.startsWith("data:")) return null;
  const bytes = await context.loadImage(path).catch(() => null);
  if (!bytes) {
    context.warnings.push(`Could not include image: ${path}`);
    return null;
  }
  const mimeType = extensionMime(path);
  const dimensions = await imageDimensions(bytes, mimeType);
  return { data: bytes, mimeType, ...dimensions };
}

function escapeHtml(value: string): string {
  return value
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;")
    .split('"').join("&quot;");
}

function propertyTableHtml(properties: Array<[string, PropertyValue]>): string {
  if (!properties.length) return "";
  const rows = properties
    .map(
      ([key, value]) =>
        `<tr><th>${escapeHtml(key)}</th><td>${escapeHtml(displayProperty(value))}</td></tr>`,
    )
    .join("");
  return `<table class="properties"><tbody>${rows}</tbody></table>`;
}

async function embedHtmlImages(tree: Root, context: ExportContext): Promise<void> {
  const visit = async (node: {
    type?: string;
    url?: string;
    alt?: string;
    data?: { hProperties?: Record<string, unknown> };
    children?: unknown[];
  }) => {
    if (node.children) {
      node.children = node.children.flatMap((child) => {
        if (
          child &&
          typeof child === "object" &&
          (child as Link).type === "link" &&
          (child as Link).url.startsWith("zerus-note:")
        ) {
          return (child as Link).children;
        }
        return [child];
      });
    }
    if (node.type === "image" && node.url) {
      const parsed = parseImageAlt(node.alt ?? "");
      node.alt = parsed.alt;
      if (parsed.width) {
        node.data = {
          ...node.data,
          hProperties: {
            ...node.data?.hProperties,
            style: `width:${parsed.width}px;max-width:100%`,
          },
        };
      }
      const loaded = await loadLocalImage(node.url, context);
      if (loaded) node.url = bytesToDataUrl(loaded.data, loaded.mimeType);
    }
    for (const child of node.children ?? []) {
      if (child && typeof child === "object") {
        await visit(child as {
          type?: string;
          url?: string;
          alt?: string;
          data?: { hProperties?: Record<string, unknown> };
          children?: unknown[];
        });
      }
    }
  };
  await visit(tree as { type?: string; url?: string; children?: unknown[] });
}

async function renderHtml(context: ExportContext): Promise<Blob> {
  const tree = structuredClone(context.tree);
  await embedHtmlImages(tree, context);
  const schema = {
    ...defaultSchema,
    attributes: {
      ...defaultSchema.attributes,
      img: [...(defaultSchema.attributes?.img ?? []), "style"],
    },
    protocols: {
      ...defaultSchema.protocols,
      href: ["http", "https", "mailto", "zerus-note"],
      src: ["http", "https", "data"],
    },
  };
  const hast = await unified()
    .use(remarkRehype)
    .use(rehypeSanitize, schema)
    .use(rehypeStringify)
    .run(tree);
  const body = unified().use(rehypeStringify).stringify(hast);
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(context.title)}</title><style>
:root{color-scheme:light;font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#252321;background:#fff}
body{max-width:760px;margin:0 auto;padding:56px 32px 80px;font-size:16px;line-height:1.65}h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.5em 0 .55em}h1{font-size:2.15rem}h2{font-size:1.65rem}h3{font-size:1.3rem}a{color:#b64038}img{display:block;max-width:100%;height:auto;margin:1.2rem auto}blockquote{margin:1rem 0;padding:.15rem 1rem;border-left:3px solid #d84b40;color:#5d5752}code{font-family:"SFMono-Regular",Consolas,monospace;background:#f3f1ef;border-radius:4px;padding:.12em .35em}pre{overflow:auto;background:#f3f1ef;border-radius:8px;padding:1rem}pre code{padding:0;background:none}table{width:100%;border-collapse:collapse;margin:1.25rem 0}th,td{border:1px solid #ded9d5;padding:.45rem .65rem;text-align:left;vertical-align:top}.properties{font-size:.88rem;color:#554f4a}.properties th{width:28%;background:#f7f5f3}hr{border:0;border-top:1px solid #ded9d5;margin:2rem 0}@media print{body{max-width:none;padding:0}a{color:inherit}}
</style></head><body>${propertyTableHtml(context.properties)}${body}</body></html>`;
  return new Blob([html], { type: "text/html;charset=utf-8" });
}

function plainText(node: { type?: string; value?: string; alt?: string; children?: unknown[] }): string {
  if (node.type === "text" || node.type === "inlineCode" || node.type === "code") {
    return node.value ?? "";
  }
  if (node.type === "image") return node.alt ?? "Image";
  return (node.children ?? [])
    .map((child) =>
      child && typeof child === "object"
        ? plainText(child as { type?: string; value?: string; alt?: string; children?: unknown[] })
        : "",
    )
    .join("");
}

async function renderDocx(context: ExportContext): Promise<Blob> {
  const docx = await import("docx");
  const {
    AlignmentType,
    BorderStyle,
    Document,
    ExternalHyperlink,
    HeadingLevel,
    ImageRun,
    LevelFormat,
    Packer,
    Paragraph,
    ShadingType,
    Table,
    TableCell,
    TableRow,
    TextRun,
    WidthType,
  } = docx;

  const inline = async (
    nodes: readonly PhrasingContent[],
    styles: { bold?: boolean; italics?: boolean; strike?: boolean } = {},
  ): Promise<import("docx").ParagraphChild[]> => {
    const runs: import("docx").ParagraphChild[] = [];
    for (const node of nodes) {
      if (node.type === "text") {
        runs.push(new TextRun({ text: node.value, ...styles }));
      } else if (node.type === "strong") {
        runs.push(...(await inline(node.children, { ...styles, bold: true })));
      } else if (node.type === "emphasis") {
        runs.push(...(await inline(node.children, { ...styles, italics: true })));
      } else if (node.type === "delete") {
        runs.push(...(await inline(node.children, { ...styles, strike: true })));
      } else if (node.type === "inlineCode") {
        runs.push(new TextRun({ text: node.value, font: "Courier New", shading: { fill: "F3F1EF", type: ShadingType.CLEAR } }));
      } else if (node.type === "break") {
        runs.push(new TextRun({ break: 1 }));
      } else if (node.type === "link") {
        const children = await inline(node.children, styles);
        if (/^(?:https?:|mailto:)/i.test(node.url)) {
          runs.push(new ExternalHyperlink({ link: node.url, children }));
        } else {
          runs.push(new TextRun({ text: plainText(node), color: "B64038", underline: {} }));
        }
      } else if (node.type === "image") {
        const loaded = await loadLocalImage(node.url, context);
        if (!loaded) {
          runs.push(new TextRun({ text: node.alt ? `[${node.alt}]` : "[Image]", italics: true, color: "777777" }));
          continue;
        }
        const parsed = parseImageAlt(node.alt ?? "");
        const width = Math.min(parsed.width ?? loaded.width, 600);
        const height = Math.max(1, Math.round((loaded.height / loaded.width) * width));
        const extension = loaded.mimeType === "image/jpeg" ? "jpg" : loaded.mimeType.slice(6);
        if (!["jpg", "png", "gif", "bmp"].includes(extension)) {
          context.warnings.push(`DOCX could not embed ${node.url}; its image format is unsupported.`);
          runs.push(new TextRun({ text: parsed.alt ? `[${parsed.alt}]` : "[Image]", italics: true, color: "777777" }));
        } else {
          runs.push(new ImageRun({
            type: extension as "jpg" | "png" | "gif" | "bmp",
            data: loaded.data,
            transformation: { width, height },
            altText: { title: parsed.alt || "Image", description: parsed.alt || "Image", name: parsed.alt || "Image" },
          }));
        }
      }
    }
    return runs;
  };

  const block = async (
    node: RootContent | BlockContent,
    listLevel = 0,
    listKind?: "bullet" | "number",
  ): Promise<Array<import("docx").Paragraph | import("docx").Table>> => {
    if (node.type === "paragraph") {
      return [new Paragraph({
        children: await inline(node.children),
        spacing: { after: 160, line: 320 },
        ...(listKind === "bullet" ? { bullet: { level: listLevel } } : {}),
        ...(listKind === "number" ? { numbering: { reference: "zerus-numbering", level: listLevel } } : {}),
      })];
    }
    if (node.type === "heading") {
      const levels = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3, HeadingLevel.HEADING_4, HeadingLevel.HEADING_5, HeadingLevel.HEADING_6];
      return [new Paragraph({ children: await inline(node.children), heading: levels[node.depth - 1], spacing: { before: 260, after: 120 } })];
    }
    if (node.type === "code") {
      return [new Paragraph({
        children: [new TextRun({ text: node.value, font: "Courier New", size: 19 })],
        shading: { fill: "F3F1EF", type: ShadingType.CLEAR },
        spacing: { before: 100, after: 180 },
        indent: { left: 180, right: 180 },
      })];
    }
    if (node.type === "thematicBreak") {
      return [new Paragraph({ border: { bottom: { color: "DED9D5", style: BorderStyle.SINGLE, size: 6 } }, spacing: { before: 160, after: 160 } })];
    }
    if (node.type === "blockquote") {
      return [new Paragraph({
        children: [new TextRun({ text: plainText(node), italics: true, color: "5D5752" })],
        indent: { left: 360 },
        border: { left: { color: "D84B40", style: BorderStyle.SINGLE, size: 12, space: 8 } },
      })];
    }
    if (node.type === "list") {
      const kind = node.ordered ? "number" : "bullet";
      const childLevel = listKind ? Math.min(listLevel + 1, 8) : listLevel;
      const output: Array<import("docx").Paragraph | import("docx").Table> = [];
      for (const item of node.children) {
        for (const child of item.children) {
          if (child.type === "paragraph" && item.checked !== null && item.checked !== undefined) {
            output.push(new Paragraph({
              children: [
                new TextRun({ text: item.checked ? "☒ " : "☐ " }),
                ...(await inline(child.children)),
              ],
              spacing: { after: 120, line: 320 },
              bullet: { level: childLevel },
            }));
          } else {
            output.push(...(await block(child, childLevel, kind)));
          }
        }
      }
      return output;
    }
    if (node.type === "table") {
      const rows = await Promise.all(node.children.map(async (row) =>
        new TableRow({
          children: await Promise.all(row.children.map(async (cell) =>
            new TableCell({ children: [new Paragraph({ children: await inline(cell.children) })] }),
          )),
          tableHeader: row === node.children[0],
        }),
      ));
      return [new Table({ rows, width: { size: 100, type: WidthType.PERCENTAGE } })];
    }
    return [];
  };

  const children: Array<import("docx").Paragraph | import("docx").Table> = [];
  if (context.properties.length) {
    children.push(new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      rows: context.properties.map(([key, value]) => new TableRow({ children: [
        new TableCell({ width: { size: 28, type: WidthType.PERCENTAGE }, shading: { fill: "F7F5F3", type: ShadingType.CLEAR }, children: [new Paragraph({ children: [new TextRun({ text: key, bold: true })] })] }),
        new TableCell({ children: [new Paragraph(displayProperty(value))] }),
      ] })),
    }));
    children.push(new Paragraph({ spacing: { after: 100 } }));
  }
  for (const node of context.tree.children) children.push(...(await block(node)));
  const document = new Document({
    creator: "Zerus",
    title: context.title,
    description: "Exported from Zerus",
    numbering: { config: [{ reference: "zerus-numbering", levels: Array.from({ length: 9 }, (_, level) => ({ level, format: LevelFormat.DECIMAL, text: `%${level + 1}.`, alignment: AlignmentType.START, style: { paragraph: { indent: { left: 720 + level * 360, hanging: 260 } } } })) }] },
    sections: [{ properties: {}, children }],
  });
  return Packer.toBlob(document);
}

async function renderPdf(context: ExportContext): Promise<Blob> {
  const [{ default: pdfMake }, { default: vfsFonts }] = await Promise.all([
    import("pdfmake/build/pdfmake"),
    import("pdfmake/build/vfs_fonts"),
  ]);
  pdfMake.addVirtualFileSystem(vfsFonts);
  type Content = import("pdfmake/interfaces").Content;

  const inline = (nodes: readonly PhrasingContent[]): Content[] =>
    nodes.flatMap((node): Content[] => {
      if (node.type === "text") return [node.value];
      if (node.type === "strong") return [{ text: inline(node.children), bold: true }];
      if (node.type === "emphasis") return [{ text: inline(node.children), italics: true }];
      if (node.type === "delete") return [{ text: inline(node.children), decoration: "lineThrough" }];
      if (node.type === "inlineCode") return [{ text: node.value, font: "Roboto", background: "#f3f1ef", color: "#393532" }];
      if (node.type === "break") return ["\n"];
      if (node.type === "link") return [{ text: inline(node.children), color: "#b64038", decoration: "underline", ...(/^(?:https?:|mailto:)/i.test(node.url) ? { link: node.url } : {}) }];
      if (node.type === "image") return [{ text: node.alt ? `[${parseImageAlt(node.alt).alt}]` : "[Image]", italics: true, color: "#777777" }];
      return [];
    });

  const block = async (node: RootContent | BlockContent): Promise<Content> => {
    if (node.type === "paragraph") {
      if (node.children.length === 1 && node.children[0].type === "image") {
        const image = node.children[0];
        const loaded = await loadLocalImage(image.url, context);
        if (loaded && ["image/png", "image/jpeg"].includes(loaded.mimeType)) {
          const parsed = parseImageAlt(image.alt ?? "");
          return { image: bytesToDataUrl(loaded.data, loaded.mimeType), fit: [Math.min(parsed.width ?? 480, 480), 620], alignment: "center", margin: [0, 8, 0, 12] };
        }
        if (loaded) context.warnings.push(`PDF could not embed ${image.url}; use PNG or JPEG for full compatibility.`);
      }
      return { text: inline(node.children), margin: [0, 0, 0, 9], lineHeight: 1.35 };
    }
    if (node.type === "heading") return {
      text: inline(node.children),
      style: `h${node.depth}`,
      margin: [0, node.depth === 1 ? 0 : 13, 0, 7],
      outline: true,
      // pdfmake cannot derive a bookmark title from a rich-text array. Some
      // viewers (notably Firefox) display that fallback as "[object Object]".
      outlineText: plainText(node),
    };
    if (node.type === "code") return { text: node.value, font: "Roboto", fontSize: 9, background: "#f3f1ef", margin: [8, 7, 8, 10], preserveLeadingSpaces: true };
    if (node.type === "thematicBreak") return { canvas: [{ type: "line", x1: 0, y1: 0, x2: 475, y2: 0, lineWidth: 1, lineColor: "#ded9d5" }], margin: [0, 12, 0, 12] };
    if (node.type === "blockquote") return { stack: await Promise.all(node.children.map(block)), margin: [15, 4, 0, 8], color: "#5d5752", italics: true };
    if (node.type === "list") {
      const items = await Promise.all(node.children.map(async (item) => {
        const stack = await Promise.all(item.children.map(block));
        if (item.checked !== null && item.checked !== undefined && stack.length) {
          stack.unshift({ text: item.checked ? "☒" : "☐", margin: [0, 0, 0, 2] });
        }
        return { stack };
      }));
      return node.ordered ? { ol: items, margin: [0, 0, 0, 8] } : { ul: items, margin: [0, 0, 0, 8] };
    }
    if (node.type === "table") {
      const body: import("pdfmake/interfaces").TableCell[][] = node.children.map(
        (row) => row.children.map((cell) => ({
          text: inline(cell.children),
          bold: row === node.children[0],
          fillColor: row === node.children[0] ? "#f7f5f3" : undefined,
          margin: [3, 3, 3, 3] as [number, number, number, number],
        })),
      );
      return { table: { headerRows: 1, widths: Array.from({ length: body[0]?.length ?? 0 }, () => "*"), body }, layout: "lightHorizontalLines", margin: [0, 8, 0, 12], fontSize: 9 };
    }
    return { text: "" };
  };

  const content: Content[] = [];
  if (context.properties.length) {
    content.push({
      table: {
        widths: ["28%", "72%"],
        body: context.properties.map(([key, value]) => [
          { text: key, bold: true, fillColor: "#f7f5f3" },
          displayProperty(value),
        ]),
      },
      layout: "lightHorizontalLines",
      margin: [0, 0, 0, 14],
      fontSize: 9,
    });
  }
  for (const node of context.tree.children) content.push(await block(node));
  const definition: import("pdfmake/interfaces").TDocumentDefinitions = {
    info: { title: context.title, creator: "Zerus", producer: "Zerus" },
    pageSize: "A4",
    pageMargins: [56, 52, 56, 56],
    defaultStyle: { font: "Roboto", fontSize: 11, color: "#252321" },
    styles: {
      h1: { fontSize: 25, bold: true, lineHeight: 1.15 },
      h2: { fontSize: 19, bold: true, lineHeight: 1.18 },
      h3: { fontSize: 15, bold: true },
      h4: { fontSize: 12, bold: true },
      h5: { fontSize: 11, bold: true },
      h6: { fontSize: 10, bold: true },
    },
    content,
  };
  return pdfMake.createPdf(definition).getBlob();
}

export async function createNoteExport(
  note: Note,
  format: NoteExportFormat,
  options: NoteExportOptions,
  loadImage: ExportImageLoader = readVaultImage,
): Promise<NoteExportArtifact> {
  const context: ExportContext = {
    tree: parseNoteForExport(note),
    title: noteTitle(note),
    properties: exportProperties(note, options.includeProperties),
    loadImage,
    warnings: [],
  };
  const blob =
    format === "html"
      ? await renderHtml(context)
      : format === "docx"
        ? await renderDocx(context)
        : await renderPdf(context);
  return {
    blob,
    format,
    fileName: `${safeFileStem(context.title)}.${format}`,
    warnings: [...new Set(context.warnings)],
  };
}
