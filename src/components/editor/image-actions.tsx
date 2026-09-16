import { useRef, useState } from "react";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { $getNodeByKey } from "lexical";
import { $isImageNode, editImageToolbarComponent$, openEditImageDialog$, realmPlugin } from "@mdxeditor/editor";
import { usePublisher } from "@mdxeditor/gurx";
import { Maximize2, Pencil, Trash2 } from "@/lib/icons";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";

interface ImageActionsProps {
  nodeKey: string;
  imageSource: string;
  initialImagePath: string | null;
  title: string;
  alt: string;
  width?: number | "inherit";
  height?: number | "inherit";
}

// eslint-disable-next-line react-refresh/only-export-components
function ImageActions({ nodeKey, imageSource, initialImagePath, title, alt, width, height }: ImageActionsProps) {
  const [editor] = useLexicalComposerContext();
  const editImage = usePublisher(openEditImageDialog$);
  const [expanded, setExpanded] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const expandButton = useRef<HTMLButtonElement>(null);
  const deleteButton = useRef<HTMLButtonElement>(null);
  const deleted = useRef(false);

  return <div className="zerus-image-actions" contentEditable={false} onClick={event => event.stopPropagation()}>
    <button ref={expandButton} type="button" title="Expand image" aria-label="Expand image" onClick={() => setExpanded(true)}><Maximize2 size={16} /><span>Expand</span></button>
    <button type="button" title="Edit image" aria-label="Edit image" onClick={() => editImage({ nodeKey, initialValues: {
      src: initialImagePath ?? imageSource, title, altText: alt,
      width: typeof width === "number" ? width : undefined,
      height: typeof height === "number" ? height : undefined,
    } })}><Pencil size={16} /></button>
    <button ref={deleteButton} type="button" title="Delete image" aria-label="Delete image" onClick={() => { deleted.current = false; setConfirmDelete(true); }}><Trash2 size={16} /></button>
    <Dialog open={expanded} onOpenChange={setExpanded}>
      <DialogContent className="zerus-image-viewer" aria-describedby={undefined} onCloseAutoFocus={event => { event.preventDefault(); expandButton.current?.focus(); }}>
        <DialogTitle className="sr-only">{title || alt || "Image preview"}</DialogTitle>
        <img src={imageSource} alt={alt} className="zerus-image-viewer-image" />
      </DialogContent>
    </Dialog>
    <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
      <AlertDialogContent onCloseAutoFocus={event => { event.preventDefault(); if (deleted.current) editor.focus(); else deleteButton.current?.focus(); }}>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete image?</AlertDialogTitle>
          <AlertDialogDescription>This will remove the image from this note. You can undo this change in the editor.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction className="bg-destructive text-destructive-foreground hover:bg-destructive/90" onClick={() => {
            deleted.current = true;
            editor.update(() => {
              const node = $getNodeByKey(nodeKey);
              if ($isImageNode(node)) node.remove();
            });
          }}>Delete image</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>;
}

export const imageActionsPlugin = realmPlugin({
  init(realm) { realm.pub(editImageToolbarComponent$, ImageActions); },
  update(realm) { realm.pub(editImageToolbarComponent$, ImageActions); },
});
