import { useState } from "react";
import { Check, ChevronDown, Plus } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import { parseTypePath, typeKey } from "@/lib/note-utils";
import type { TypeIcons } from "@/lib/type-icons";
import { TypeIcon } from "./TypeIcon";

interface TypePickerProps {
  value: string[];
  existingTypePaths: string[][];
  /** Custom icon per type key — types without one get the folder glyph. */
  typeIcons: TypeIcons;
  onChange: (typePath: string[]) => void;
  label?: string;
  title?: string;
  disabled?: boolean;
}

export function TypePicker({
  value,
  existingTypePaths,
  typeIcons,
  onChange,
  label,
  title,
  disabled = false,
}: TypePickerProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  const parsed = parseTypePath(query);
  const parsedKey = typeKey(parsed);
  const canCreate =
    parsed.length > 0 &&
    !existingTypePaths.some((path) => typeKey(path) === parsedKey);

  const pick = (typePath: string[]) => {
    onChange(typePath);
    setQuery("");
    setOpen(false);
  };

  return (
    <Popover
      open={!disabled && open}
      onOpenChange={(next) => !disabled && setOpen(next)}
    >
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          disabled={disabled}
          className="h-7 gap-1 rounded-full border-zerus-accent/35 bg-zerus-accent/5 px-2.5 text-xs font-medium text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
          title={
            title ??
            "Type — the nested folder this note lives in"
          }
        >
          <TypeIcon icon={typeIcons[typeKey(value)]} size={12} />
          {label ?? (value.length ? value.join(" / ") : "unfiled")}
          <ChevronDown size={12} className="opacity-60" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-72 p-0" align="start">
        <Command>
          <CommandInput
            placeholder="Set type… (e.g. work/projects/polaris)"
            value={query}
            onValueChange={setQuery}
          />
          <CommandList>
            <CommandEmpty>No matching types.</CommandEmpty>
            <CommandGroup>
              {existingTypePaths.map((path) => {
                const key = typeKey(path);
                return (
                  <CommandItem
                    key={key}
                    value={key}
                    onSelect={() => pick(path)}
                  >
                    <TypeIcon
                      icon={typeIcons[key]}
                      size={13}
                      className="mr-2 shrink-0 opacity-60"
                      style={{ marginLeft: `${(path.length - 1) * 12}px` }}
                    />
                    {path[path.length - 1]}
                    <span className="ml-2 truncate text-xs text-muted-foreground">
                      {path.length > 1 ? key : ""}
                    </span>
                    <Check
                      size={14}
                      className={cn(
                        "ml-auto shrink-0",
                        key === typeKey(value) ? "opacity-100" : "opacity-0",
                      )}
                    />
                  </CommandItem>
                );
              })}
              {canCreate && (
                <CommandItem
                  value={`create-${parsedKey}`}
                  onSelect={() => pick(parsed)}
                >
                  <Plus size={13} className="mr-2 shrink-0" />
                  Create “{parsed.join(" / ")}”
                </CommandItem>
              )}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
