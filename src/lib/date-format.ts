import { useSyncExternalStore } from "react";

export const DATE_FORMATS = ["DD/MM/YYYY", "MM/DD/YYYY", "YYYY-MM-DD", "DD.MM.YYYY"] as const;
export type DateFormat = (typeof DATE_FORMATS)[number];
const STORAGE_KEY = "zerus-date-format";
const CHANGE_EVENT = "zerus-date-format-change";

export function loadDateFormat(): DateFormat {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (DATE_FORMATS.includes(stored as DateFormat)) return stored as DateFormat;
  } catch { /* Storage may be unavailable. */ }
  return "DD/MM/YYYY";
}

export function saveDateFormat(format: DateFormat) {
  localStorage.setItem(STORAGE_KEY, format);
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

function subscribe(listener: () => void) {
  window.addEventListener(CHANGE_EVENT, listener);
  window.addEventListener("storage", listener);
  return () => {
    window.removeEventListener(CHANGE_EVENT, listener);
    window.removeEventListener("storage", listener);
  };
}

export function useDateFormat() {
  return useSyncExternalStore(subscribe, loadDateFormat, () => "DD/MM/YYYY" as DateFormat);
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function formatDate(value: string, format: DateFormat): string {
  let calendarDate = value;
  if (!isCalendarDate(calendarDate)) {
    // Timestamps represent instants; calendar-only dates must never shift timezone.
    if (!/^\d{4}-\d{2}-\d{2}T/.test(value)) return value;
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return value;
    calendarDate = `${String(date.getFullYear()).padStart(4, "0")}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  }
  const [year, month, day] = calendarDate.split("-");
  return format.replace("YYYY", year).replace("MM", month).replace("DD", day);
}

// Empty clears a field; null means invalid and must not overwrite its saved value.
export function parseDateInput(value: string, format: DateFormat): string | null {
  if (!value.trim()) return "";
  const separator = format.includes("/") ? "/" : format.includes(".") ? "." : "-";
  const parts = value.trim().split(separator);
  const tokens = format.split(separator);
  if (parts.length !== 3 || parts.some((part, index) => !(tokens[index] === "YYYY" ? /^\d{4}$/ : /^\d{1,2}$/).test(part))) return null;
  const year = parts[tokens.indexOf("YYYY")];
  const month = parts[tokens.indexOf("MM")].padStart(2, "0");
  const day = parts[tokens.indexOf("DD")].padStart(2, "0");
  const result = `${year}-${month}-${day}`;
  return isCalendarDate(result) ? result : null;
}
