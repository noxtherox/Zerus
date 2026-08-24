import { createRef } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import {
  ImageActionsPopover,
  PasteOptionsPopover,
} from "./EditorPopovers";

describe("editor popovers", () => {
  it("renders the active image actions without edit controls in read-only mode", () => {
    const html = renderToStaticMarkup(
      <ImageActionsPopover
        state={{
          image: {
            path: "assets/chart.png",
            alt: "Chart",
            width: null,
            from: 0,
            to: 26,
          },
          target: {} as HTMLElement,
          left: 12,
          top: 20,
          width: 300,
        }}
        elementRef={createRef<HTMLDivElement>()}
        readOnly
        editAlt={null}
        copied={false}
        onEditAltChange={vi.fn()}
        onSaveAlt={vi.fn()}
        onOpen={vi.fn()}
        onReplace={vi.fn()}
        onCopy={vi.fn()}
        onRemove={vi.fn()}
      />,
    );

    expect(html).toContain("chart.png");
    expect(html).toContain('aria-label="Open image"');
    expect(html).toContain('aria-label="Copy image"');
    expect(html).not.toContain('aria-label="Replace image"');
    expect(html).not.toContain('aria-label="Remove image"');
  });

  it("marks the current paste interpretation as selected", () => {
    const html = renderToStaticMarkup(
      <PasteOptionsPopover
        state={{
          from: 0,
          to: 4,
          choices: [
            {
              mode: "plain",
              label: "Plain text",
              description: "No formatting",
              text: "text",
            },
          ],
          selectedMode: "plain",
          anchor: { left: 0, bottom: 0 },
          left: 12,
          top: 20,
          width: 280,
        }}
        elementRef={createRef<HTMLDivElement>()}
        onKeyDown={vi.fn()}
        onClose={vi.fn()}
        onSelect={vi.fn()}
      />,
    );

    expect(html).toContain('role="menuitemradio"');
    expect(html).toContain('aria-checked="true"');
  });
});
