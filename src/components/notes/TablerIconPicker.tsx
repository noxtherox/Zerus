import { useDeferredValue, useEffect, useMemo, useState } from "react";
import { Folder, Search } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { searchTablerIcons } from "@/lib/tabler-icon-catalog";
import { tablerIconName, tablerIconValue } from "@/lib/type-icons";
import type { IconPickerDialogProps } from "./IconPickerDialog";

const PAGE_SIZE = 160;

export default function TablerIconPicker({
  open,
  value,
  onOpenChange,
  onPick,
}: IconPickerDialogProps) {
  const [query, setQuery] = useState("");
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);
  const deferredQuery = useDeferredValue(query);
  const selectedName = tablerIconName(value);
  const matches = useMemo(() => searchTablerIcons(deferredQuery), [deferredQuery]);
  const visible = matches.slice(0, visibleCount);

  useEffect(() => setVisibleCount(PAGE_SIZE), [deferredQuery]);
  useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  const pick = (icon: string | null) => {
    onPick(icon);
    onOpenChange(false);
  };

  return (
    <div className="min-w-0 px-4 pb-4">
      <div className="relative mb-3">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          autoFocus
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search 5,000+ icons…"
          aria-label="Search Tabler icons"
          className="pl-9"
        />
      </div>

      <div className="max-h-[min(55vh,28rem)] overflow-y-auto rounded-lg border p-2">
        <div className="grid grid-cols-7 gap-1 sm:grid-cols-10">
          {visible.map(({ name, label, Icon }) => (
            <button
              key={name}
              type="button"
              title={label}
              aria-label={label}
              aria-pressed={name === selectedName}
              onClick={() => pick(tablerIconValue(name))}
              className={cn(
                "flex aspect-square min-h-10 items-center justify-center rounded-md text-foreground/70 transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                name === selectedName &&
                  "bg-grim-accent/15 text-grim-accent hover:bg-grim-accent/20 hover:text-grim-accent",
              )}
            >
              <Icon size={19} stroke={1.8} aria-hidden="true" />
            </button>
          ))}
        </div>

        {matches.length === 0 ? (
          <p className="py-12 text-center text-sm text-muted-foreground">
            No icons match "{deferredQuery}".
          </p>
        ) : null}

        {visible.length < matches.length ? (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="mt-2 w-full text-muted-foreground"
            onClick={() => setVisibleCount((count) => count + PAGE_SIZE)}
          >
            Show more ({matches.length - visible.length} remaining)
          </Button>
        ) : null}
      </div>

      <div className="mt-3 flex items-center justify-between gap-3">
        <span className="text-xs text-muted-foreground">
          {matches.length.toLocaleString()} icon{matches.length === 1 ? "" : "s"}
        </span>
        <Button variant="outline" size="sm" className="gap-1.5" onClick={() => pick(null)}>
          <Folder size={13} /> Reset to folder
        </Button>
      </div>
    </div>
  );
}
