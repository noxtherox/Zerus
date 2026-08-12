import { lazy, Suspense } from "react";
import { Loader2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

const TablerIconPicker = lazy(() => import("./TablerIconPicker"));

export interface IconPickerDialogProps {
  open: boolean;
  typeName: string;
  value?: string;
  onOpenChange: (open: boolean) => void;
  onPick: (icon: string | null) => void;
}

export function IconPickerDialog(props: IconPickerDialogProps) {
  return (
    <Dialog open={props.open} onOpenChange={props.onOpenChange}>
      <DialogContent className="w-[calc(100vw-2rem)] max-w-xl overflow-hidden p-0">
        <DialogHeader className="px-5 pt-5">
          <DialogTitle>Icon for "{props.typeName}"</DialogTitle>
          <DialogDescription>
            Search the offline Tabler catalog or browse the available icons.
          </DialogDescription>
        </DialogHeader>
        {props.open ? (
          <Suspense
            fallback={
              <div className="flex h-80 items-center justify-center text-muted-foreground">
                <Loader2 className="h-5 w-5 animate-spin" aria-label="Loading icons" />
              </div>
            }
          >
            <TablerIconPicker {...props} />
          </Suspense>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
