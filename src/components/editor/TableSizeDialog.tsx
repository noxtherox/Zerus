import { useState } from "react";
import { Minus, Plus, Table2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface TableSizeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onInsert: (columns: number, rows: number) => void;
}

interface SizeControlProps {
  label: string;
  value: number;
  min: number;
  max: number;
  autoFocus?: boolean;
  onChange: (value: number) => void;
}

function SizeControl({
  label,
  value,
  min,
  max,
  autoFocus = false,
  onChange,
}: SizeControlProps) {
  const id = `table-${label.toLowerCase().replace(" ", "-")}`;
  const update = (nextValue: number) => {
    if (!Number.isFinite(nextValue)) return;
    onChange(Math.min(max, Math.max(min, nextValue)));
  };

  return (
    <div className="space-y-2">
      <Label htmlFor={id} className="text-xs font-medium text-muted-foreground">
        {label}
      </Label>
      <div className="flex items-center rounded-lg border border-border bg-background p-1">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-8 w-8 shrink-0"
          aria-label={`Decrease ${label.toLowerCase()}`}
          disabled={value <= min}
          onClick={() => update(value - 1)}
        >
          <Minus className="h-3.5 w-3.5" />
        </Button>
        <Input
          id={id}
          type="number"
          min={min}
          max={max}
          value={value}
          autoFocus={autoFocus}
          className="h-8 border-0 bg-transparent px-1 text-center text-sm font-semibold shadow-none focus-visible:ring-1"
          onChange={(event) => update(Number(event.target.value))}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-8 w-8 shrink-0"
          aria-label={`Increase ${label.toLowerCase()}`}
          disabled={value >= max}
          onClick={() => update(value + 1)}
        >
          <Plus className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  );
}

export function TableSizeDialog({
  open,
  onOpenChange,
  onInsert,
}: TableSizeDialogProps) {
  const [columns, setColumns] = useState(3);
  const [rows, setRows] = useState(2);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm border-border bg-background p-5 shadow-2xl">
        <DialogHeader>
          <div className="mb-1 flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <Table2 className="h-4 w-4" />
          </div>
          <DialogTitle>Insert table</DialogTitle>
          <DialogDescription>
            Choose the number of columns and body rows.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-2 gap-3 py-2">
          <SizeControl
            label="Columns"
            value={columns}
            min={1}
            max={12}
            autoFocus
            onChange={setColumns}
          />
          <SizeControl
            label="Body rows"
            value={rows}
            min={1}
            max={50}
            onChange={setRows}
          />
        </div>

        <div className="rounded-lg border border-border/70 bg-muted/30 p-3">
          <div className="mb-2 flex items-center justify-between text-[11px] text-muted-foreground">
            <span>Preview</span>
            <span>{columns} × {rows}</span>
          </div>
          <div
            className="grid h-16 gap-px overflow-hidden rounded border border-border bg-border"
            style={{
              gridTemplateColumns: `repeat(${Math.min(columns, 8)}, minmax(0, 1fr))`,
              gridTemplateRows: `repeat(${Math.min(rows + 1, 5)}, minmax(0, 1fr))`,
            }}
            aria-hidden="true"
          >
            {Array.from({
              length: Math.min(columns, 8) * Math.min(rows + 1, 5),
            }).map((_, index) => (
              <span
                key={index}
                className={index < Math.min(columns, 8) ? "bg-primary/10" : "bg-background"}
              />
            ))}
          </div>
        </div>

        <DialogFooter>
          <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" onClick={() => onInsert(columns, rows)}>
            Insert table
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
