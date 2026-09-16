import { useId, useState } from "react";
import {
  addMonths,
  format as formatCalendarDate,
  getDay,
  getDaysInMonth,
  startOfMonth,
} from "date-fns";
import { ChevronLeft, ChevronRight } from "@/lib/icons";
import { formatDate, parseDateInput, useDateFormat } from "@/lib/date-format";
import { cn } from "@/lib/utils";
import { Input } from "./input";
import { Popover, PopoverContent, PopoverTrigger } from "./popover";

function calendarMonth(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return startOfMonth(new Date());
  return new Date(Number(match[1]), Number(match[2]) - 1, 1);
}

function dateKey(year: number, month: number, day: number) {
  return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function CalendarPicker({
  value,
  month,
  label,
  onMonthChange,
  onSelect,
}: {
  value: string;
  month: Date;
  label: string;
  onMonthChange: (month: Date) => void;
  onSelect: (value: string) => void;
}) {
  const year = month.getFullYear();
  const monthIndex = month.getMonth();
  const leadingDays = getDay(month);
  const days = getDaysInMonth(month);
  const today = new Date();
  const todayKey = dateKey(today.getFullYear(), today.getMonth(), today.getDate());

  return (
    <div aria-label={`Choose ${label.toLowerCase()}`} role="dialog">
      <div className="mb-2 flex items-center justify-between">
        <button
          type="button"
          aria-label="Previous month"
          className="flex size-7 items-center justify-center rounded text-muted-foreground hover:bg-muted hover:text-foreground"
          onClick={() => onMonthChange(addMonths(month, -1))}
        >
          <ChevronLeft size={15} />
        </button>
        <span className="text-xs font-semibold">
          {formatCalendarDate(month, "MMMM yyyy")}
        </span>
        <button
          type="button"
          aria-label="Next month"
          className="flex size-7 items-center justify-center rounded text-muted-foreground hover:bg-muted hover:text-foreground"
          onClick={() => onMonthChange(addMonths(month, 1))}
        >
          <ChevronRight size={15} />
        </button>
      </div>
      <div className="grid grid-cols-7 text-center text-[10px] font-medium text-muted-foreground">
        {["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map((day) => (
          <span key={day} className="py-1">{day}</span>
        ))}
      </div>
      <div className="grid grid-cols-7">
        {Array.from({ length: leadingDays }, (_, index) => (
          <span key={`empty-${index}`} className="size-7" />
        ))}
        {Array.from({ length: days }, (_, index) => {
          const day = index + 1;
          const key = dateKey(year, monthIndex, day);
          const selected = key === value;
          return (
            <button
              key={key}
              type="button"
              aria-label={formatCalendarDate(new Date(year, monthIndex, day), "MMMM d, yyyy")}
              aria-pressed={selected}
              className={cn(
                "flex size-7 items-center justify-center rounded text-xs hover:bg-muted",
                key === todayKey && !selected && "ring-1 ring-inset ring-border",
                selected && "bg-primary text-primary-foreground hover:bg-primary/90",
              )}
              onClick={() => onSelect(key)}
            >
              {day}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function DateInput({ value, onValueChange, className, "aria-label": label = "Date" }: {
  value: string;
  onValueChange: (value: string) => void;
  className?: string;
  "aria-label"?: string;
}) {
  const format = useDateFormat();
  const errorId = useId();
  const [open, setOpen] = useState(false);
  const [month, setMonth] = useState(() => calendarMonth(value));
  const [draft, setDraft] = useState<{ value: string; format: string; text: string } | null>(null);
  const [invalid, setInvalid] = useState(false);
  const text = draft?.value === value && draft.format === format ? draft.text : formatDate(value, format);

  const commitDraft = () => {
    const parsed = parseDateInput(text, format);
    setInvalid(parsed === null);
    if (parsed !== null) {
      if (parsed !== value) onValueChange(parsed);
      if (parsed) setMonth(calendarMonth(parsed));
      setDraft(null);
    }
  };

  return (
    <Popover
      open={open}
      onOpenChange={(nextOpen) => {
        setOpen(nextOpen);
        if (nextOpen) setMonth(calendarMonth(value));
      }}
    >
      <PopoverTrigger asChild>
        <div className="min-w-0">
          <Input
            aria-label={label}
            aria-invalid={invalid}
            aria-describedby={invalid ? errorId : undefined}
            className={className}
            placeholder={format}
            value={text}
            onChange={(event) => {
              setDraft({ value, format, text: event.target.value });
              setInvalid(false);
            }}
            onFocus={() => setOpen(true)}
            onKeyDown={(event) => {
              if (event.key === "Enter") event.currentTarget.blur();
              if (event.key === "Escape") {
                setDraft(null);
                setInvalid(false);
                setOpen(false);
              }
            }}
            onBlur={commitDraft}
          />
          {invalid && <p id={errorId} className="mt-1 text-xs text-destructive">Enter a valid date as {format}.</p>}
        </div>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto p-2"
        align="end"
        onOpenAutoFocus={(event) => event.preventDefault()}
        onCloseAutoFocus={(event) => event.preventDefault()}
      >
        <CalendarPicker
          value={value}
          month={month}
          label={label}
          onMonthChange={setMonth}
          onSelect={(next) => {
            onValueChange(next);
            setDraft(null);
            setInvalid(false);
            setOpen(false);
          }}
        />
      </PopoverContent>
    </Popover>
  );
}
