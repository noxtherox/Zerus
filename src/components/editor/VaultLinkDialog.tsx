import { useContext, useEffect, useId, useMemo, useState } from "react";
import * as Popover from "@radix-ui/react-popover";
import { useCellValues, usePublisher, useRealm } from "@mdxeditor/gurx";
import { activeEditor$, editorRootElementRef$, linkDialogState$, updateLink$, cancelLinkEdit$, switchFromPreviewToLinkEdit$, removeLink$, readOnly$, getNodeRectangle } from "@mdxeditor/editor";
import { $getNearestNodeFromDOMNode, $getSelection } from "lexical";
import { FileText, ExternalLink, Pencil, Link2Off, Copy } from "@/lib/icons";
import { useVault, prioritizeNoteLoad } from "@/store/notes-store";
import { findNoteByTitle, noteTitle, noteReference, type Note } from "@/lib/note-utils";
import { parseNoteReference } from "@/lib/wikilinks";
import { normalizeExternalUrl, openExternalUrl } from "@/lib/external-links";
import { noteReferenceFromHref } from "./note-link-markdown";
import { linkedNoteExcerpt, loadLinkOption, saveLinkOption, searchLinkNotes, type LinkOption } from "./vault-link-options";

import { NoteLinkContext } from "./note-link-context";

function LinkForm({ url, text, title, withAnchorText, notes, selectionText, onSave, onCancel }: {
  url: string; text: string; title: string; withAnchorText: boolean; notes: Note[]; selectionText: string;
  onSave: (value: { url: string; text: string; title: string }) => void; onCancel: () => void;
}) {
  const reference = noteReferenceFromHref(url);
  const [option, setOption] = useState<LinkOption>(() => url ? reference !== null ? "note" : "web" : loadLinkOption());
  const [selectedId, setSelectedId] = useState(() => reference !== null ? findNoteByTitle(reference, notes)?.id : undefined);
  const [query, setQuery] = useState("");
  const [webUrl, setWebUrl] = useState(reference === null ? url : "");
  const [label, setLabel] = useState(text || selectionText);
  const [error, setError] = useState("");
  const id = useId();
  const matches = useMemo(() => searchLinkNotes(notes, query), [notes, query]);
  const selected = notes.find((note) => note.id === selectedId);
  return <form className="zerus-link-form" onSubmit={(event) => {
    event.preventDefault(); event.stopPropagation();
    const nextUrl = option === "note" ? selected ? `#zerus-note:${encodeURIComponent(noteReference(selected))}` : null : normalizeExternalUrl(webUrl);
    if (!nextUrl) { setError(option === "note" ? "Choose a note from the vault." : "Enter a valid web URL."); return; }
    saveLinkOption(option);
    onSave({ url: nextUrl, text: withAnchorText ? label.trim() || (selected && option === "note" ? noteTitle(selected) : nextUrl) : "", title });
  }}>
    <div className="zerus-link-options" role="tablist" aria-label="Link destination">
      {(["note", "web"] as const).map((value) => <button key={value} id={`${id}-${value}`} type="button" role="tab" aria-selected={option === value} aria-controls={`${id}-panel`} onClick={() => { setOption(value); saveLinkOption(value); setError(""); }} onKeyDown={(event) => {
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
          event.preventDefault(); const next = value === "note" ? "web" : "note";
          setOption(next); saveLinkOption(next); document.getElementById(`${id}-${next}`)?.focus();
        }
      }}>{value === "note" ? "Vault note" : "Web URL"}</button>)}
    </div>
    <div id={`${id}-panel`} role="tabpanel" aria-labelledby={`${id}-${option}`}>
      {option === "note" ? <>
        <label htmlFor={`${id}-search`}>Find a note</label>
        <input autoFocus id={`${id}-search`} placeholder="Search by title or folder…" value={query} onChange={(event) => setQuery(event.target.value)} />
        <div className="zerus-link-results" aria-label="Matching notes">
          {matches.slice(0, 50).map((note) => <button type="button" key={note.id} aria-pressed={selectedId === note.id} onClick={() => { setSelectedId(note.id); setError(""); }}>
            <FileText size={16} aria-hidden="true" /><span><strong>{noteTitle(note)}</strong><small>{note.path.includes("/") ? note.path.slice(0, note.path.lastIndexOf("/")) : "Vault root"}</small></span>
          </button>)}
          {!matches.length && <p>No matching notes.</p>}
          {matches.length > 50 && <p>Keep typing to narrow the results.</p>}
        </div>
        {selected && <p className="zerus-link-selected">Selected: {noteTitle(selected)}</p>}
      </> : <><label htmlFor={`${id}-url`}>Web URL</label><input autoFocus id={`${id}-url`} inputMode="url" placeholder="https://example.com" value={webUrl} onChange={(event) => { setWebUrl(event.target.value); setError(""); }} /></>}
    </div>
    <label htmlFor={`${id}-text`}>Display text</label>
    <input id={`${id}-text`} value={label} readOnly={!withAnchorText} placeholder={option === "note" && selected ? noteTitle(selected) : "Link text"} onChange={(event) => setLabel(event.target.value)} />
    {!withAnchorText && <small>Your selected text and formatting will be kept.</small>}
    {error && <p role="alert">{error}</p>}
    <div className="zerus-link-footer"><button type="button" onClick={onCancel}>Cancel</button><button type="submit" className="zerus-link-save" disabled={option === "note" ? !selected : !webUrl.trim()}>Save link</button></div>
  </form>;
}

export function VaultLinkDialog() {
  const realm = useRealm();
  const [editor, rootRef, state, readOnly] = useCellValues(activeEditor$, editorRootElementRef$, linkDialogState$, readOnly$);
  const publish = usePublisher(linkDialogState$);
  const update = usePublisher(updateLink$);
  const cancel = usePublisher(cancelLinkEdit$);
  const edit = usePublisher(switchFromPreviewToLinkEdit$);
  const remove = usePublisher(removeLink$);
  const follow = useContext(NoteLinkContext);
  const { notes } = useVault();
  const reference = state.type !== "inactive" ? noteReferenceFromHref(state.url) : null;
  const note = reference !== null ? findNoteByTitle(reference, notes) : undefined;

  const targetId = note?.id;
  useEffect(() => { if (targetId) void prioritizeNoteLoad(targetId); }, [targetId]);

  useEffect(() => {
    const root = editor?.getRootElement();
    if (!root || !editor) return;
    const click = (event: MouseEvent) => {
      const anchor = event.target instanceof Element ? event.target.closest("a") : null;
      const url = anchor?.getAttribute("href") ?? "";
      if (!anchor || noteReferenceFromHref(url) === null) return;
      event.preventDefault(); event.stopPropagation();
      editor.getEditorState().read(() => {
        const node = $getNearestNodeFromDOMNode(anchor);
        if (!node) return;
        const rectangle = getNodeRectangle(editor, node.getKey());
        if (rectangle) publish({ type: "preview", url, href: url, title: "", linkNodeKey: node.getKey(), rectangle });
      }, { editor });
    };
    root.addEventListener("click", click, true);
    return () => root.removeEventListener("click", click, true);
  }, [editor, publish]);

  useEffect(() => {
    if (state.type === "inactive") return;
    const dismiss = () => publish({ type: "inactive" });
    // Close on editor scrolling so the preview never stays behind its link.
    const root = editor?.getRootElement()?.closest(".mdxeditor-root-contenteditable");
    root?.addEventListener("scroll", dismiss);
    window.addEventListener("resize", dismiss);
    return () => { root?.removeEventListener("scroll", dismiss); window.removeEventListener("resize", dismiss); };
  }, [editor, state.type, publish]);

  if (state.type === "inactive") return null;
  const close = () => realm.getValue(linkDialogState$).type === "edit" ? cancel() : publish({ type: "inactive" });
  const rect = state.rectangle;
  return <Popover.Root open onOpenChange={(open) => { if (!open) close(); }}>
    <Popover.Anchor style={{ position: "fixed", pointerEvents: "none", top: rect.top, left: rect.left, width: rect.width, height: rect.height }} />
    <Popover.Portal container={rootRef?.current}>
      <Popover.Content className={`zerus-link-popover ${state.type === "preview" ? "zerus-link-preview" : ""}`} align="center" side="bottom" sideOffset={6} collisionPadding={12} onOpenAutoFocus={(event) => event.preventDefault()} onCloseAutoFocus={(event) => event.preventDefault()}>
        {state.type === "edit" ? <LinkForm key={`${state.linkNodeKey}-${state.initialUrl}`} {...state} notes={notes} selectionText={editor?.getEditorState().read(() => $getSelection()?.getTextContent() ?? "") ?? ""} onSave={update} onCancel={close} /> : <>
          <div className="zerus-link-preview-row"><FileText size={16} aria-label={reference !== null ? "Linked note" : "Link"} /><strong>{reference !== null ? note ? noteTitle(note) : parseNoteReference(reference).label : state.url}</strong>
            <button type="button" className="zerus-link-open" disabled={reference !== null && !note} onClick={() => { if (reference !== null) { close(); follow(reference); } else void openExternalUrl(state.url); }}>{reference !== null ? "Open note" : "Open"}<ExternalLink size={14} /></button>
          </div>
          {reference !== null && <p className="zerus-link-excerpt">{note ? linkedNoteExcerpt(note) || "This note has no preview text." : "This note could not be found in the vault."}</p>}
          {!readOnly && <div className="zerus-link-tools"><button type="button" onClick={() => edit()} aria-label="Edit link" title="Edit link"><Pencil size={13} /></button><button type="button" onClick={() => { void navigator.clipboard.writeText(reference !== null ? `[[${reference}]]` : state.url); }} aria-label="Copy link" title="Copy link"><Copy size={13} /></button><button type="button" onClick={() => { remove(); close(); }} aria-label="Remove link" title="Remove link"><Link2Off size={13} /></button></div>}
        </>}
      </Popover.Content>
    </Popover.Portal>
  </Popover.Root>;
}
