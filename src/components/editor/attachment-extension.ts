import {
  Decoration,
  type DecorationSet,
  EditorView,
  MatchDecorator,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import type { Extension } from "@codemirror/state";
import {
  ATTACHMENT_LINK_REGEX,
  type NoteAttachment,
} from "@/lib/note-attachments";

export type AttachmentAction = "open" | "reveal" | "copy" | "external";

interface AttachmentCardOptions {
  getAttachment: (id: string) => NoteAttachment | null;
  onAction: (id: string, action: AttachmentAction) => void;
}

class AttachmentCardWidget extends WidgetType {
  constructor(
    private readonly id: string,
    private readonly fallbackName: string,
    private readonly options: AttachmentCardOptions,
  ) {
    super();
  }

  override eq(other: AttachmentCardWidget): boolean {
    return other.id === this.id && other.fallbackName === this.fallbackName;
  }

  override toDOM(): HTMLElement {
    const attachment = this.options.getAttachment(this.id);
    const card = document.createElement("span");
    card.className = "cm-attachment-card";
    card.setAttribute("contenteditable", "false");

    const menuWrap = document.createElement("span");
    menuWrap.className = "cm-attachment-menu-wrap";
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "cm-attachment-menu-trigger";
    trigger.textContent = "•••";
    trigger.title = `Actions for ${attachment?.name ?? this.fallbackName}`;
    trigger.setAttribute("aria-label", trigger.title);
    menuWrap.appendChild(trigger);

    const menu = document.createElement("span");
    menu.className = "cm-attachment-menu";
    menu.hidden = true;
    const addAction = (label: string, action: AttachmentAction) => {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        menu.hidden = true;
        this.options.onAction(this.id, action);
      });
      menu.appendChild(button);
    };
    const renderMenu = () => {
      menu.replaceChildren();
      const current = this.options.getAttachment(this.id);
      addAction("Open in default app", "open");
      addAction("Reveal in file manager", "reveal");
      addAction(
        current?.kind === "vault" ? "Keep as external link" : "Copy into vault",
        current?.kind === "vault" ? "external" : "copy",
      );
    };
    renderMenu();
    menuWrap.appendChild(menu);
    card.appendChild(menuWrap);

    const icon = document.createElement("span");
    icon.className = "cm-attachment-icon";
    icon.textContent = "↗";
    icon.setAttribute("aria-hidden", "true");
    card.appendChild(icon);

    const label = document.createElement("span");
    label.className = "cm-attachment-name";
    label.textContent = attachment?.name ?? this.fallbackName;
    card.appendChild(label);

    const kind = document.createElement("span");
    kind.className = "cm-attachment-kind";
    kind.textContent = attachment?.kind === "vault" ? "Vault" : "External";
    card.appendChild(kind);

    const stopEditorSelection = (event: MouseEvent) => event.preventDefault();
    card.addEventListener("mousedown", stopEditorSelection);
    trigger.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      const current = this.options.getAttachment(this.id);
      kind.textContent = current?.kind === "vault" ? "Vault" : "External";
      renderMenu();
      menu.hidden = !menu.hidden;
    });
    card.addEventListener("dblclick", (event) => {
      event.preventDefault();
      this.options.onAction(this.id, "open");
    });
    return card;
  }

  override ignoreEvent(): boolean {
    return true;
  }
}

export function attachmentCardExtension(
  options: AttachmentCardOptions,
): Extension {
  const matcher = new MatchDecorator({
    regexp: new RegExp(ATTACHMENT_LINK_REGEX.source, "g"),
    decoration: (match) =>
      Decoration.replace({
        widget: new AttachmentCardWidget(match[2], match[1], options),
      }),
  });

  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;

      constructor(view: EditorView) {
        this.decorations = matcher.createDeco(view);
      }

      update(update: ViewUpdate) {
        this.decorations = matcher.updateDeco(update, this.decorations);
      }
    },
    { decorations: (value) => value.decorations },
  );
}
