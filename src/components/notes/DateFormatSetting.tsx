import { useId } from "react";
import { DATE_FORMATS, formatDate, saveDateFormat, useDateFormat, type DateFormat } from "@/lib/date-format";

export function DateFormatSetting() {
  const format = useDateFormat();
  const id = useId();
  return (
    <div className="mb-5 rounded-lg border border-border p-3">
      <label htmlFor={id} className="block text-sm font-medium">Date format</label>
      <p className="mb-3 mt-0.5 text-xs text-muted-foreground">Used for date and completion date fields on this device.</p>
      <select id={id} value={format} onChange={(event) => saveDateFormat(event.target.value as DateFormat)} className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm">
        {DATE_FORMATS.map((option) => <option key={option} value={option}>{option} · {formatDate("2026-12-31", option)}</option>)}
      </select>
    </div>
  );
}
