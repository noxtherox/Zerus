import { useId, useRef, useState } from "react";
import { Calendar } from "@/lib/icons";
import { formatDate, parseDateInput, useDateFormat } from "@/lib/date-format";
import { Input } from "./input";
import { cn } from "@/lib/utils";

export function DateInput({ value, onValueChange, className, "aria-label": label = "Date" }: {
  value: string;
  onValueChange: (value: string) => void;
  className?: string;
  "aria-label"?: string;
}) {
  const format = useDateFormat();
  const picker = useRef<HTMLInputElement>(null);
  const errorId = useId();
  const [draft, setDraft] = useState<{ value: string; format: string; text: string } | null>(null);
  const [invalid, setInvalid] = useState(false);
  const text = draft?.value === value && draft.format === format ? draft.text : formatDate(value, format);
  return (
    <div className="relative min-w-0">
      <Input
        aria-label={label}
        aria-invalid={invalid}
        aria-describedby={invalid ? errorId : undefined}
        className={cn(className, "pr-9")}
        placeholder={format}
        value={text}
        onChange={(event) => { setDraft({ value, format, text: event.target.value }); setInvalid(false); }}
        onKeyDown={(event) => {
          if (event.key === "Enter") event.currentTarget.blur();
          if (event.key === "Escape") { setDraft(null); setInvalid(false); }
        }}
        onBlur={() => {
          const parsed = parseDateInput(text, format);
          setInvalid(parsed === null);
          if (parsed !== null) { if (parsed !== value) onValueChange(parsed); setDraft(null); }
        }}
      />
      <button type="button" aria-label={`Choose ${label.toLowerCase()}`} className="absolute right-1 top-1 flex h-6 w-7 items-center justify-center rounded text-muted-foreground hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring" onClick={() => picker.current?.showPicker()}>
        <Calendar size={14} />
      </button>
      <input ref={picker} type="date" tabIndex={-1} aria-hidden="true" className="pointer-events-none absolute bottom-0 left-0 h-0 w-0 opacity-0" value={value} onChange={(event) => { onValueChange(event.target.value); setDraft(null); setInvalid(false); }} />
      {invalid && <p id={errorId} className="mt-1 text-xs text-destructive">Enter a valid date as {format}.</p>}
    </div>
  );
}
