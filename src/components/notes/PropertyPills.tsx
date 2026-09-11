import { formatDate, useDateFormat } from "@/lib/date-format";
import { effectivePropertyDefinitions, inferPropertyType } from "@/lib/properties";
import { noteReferenceLabel, noteTypePath } from "@/lib/note-utils";
import { useVault } from "@/store/notes-store";
import { badgeVariants } from "@/components/ui/badge-variants";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import type { Note } from "@/lib/note-utils";
import { cn } from "@/lib/utils";

function propertyLabel(value: PropertyValue): string {
  if (Array.isArray(value)) return value.length ? value.join(", ") : "No value";
  if (typeof value === "boolean") return value ? "Checked" : "Unchecked";
  return String(value) || "No value";
}

export function PropertyPills({
  note,
  visibleProperties,
  className,
}: {
  note: Note;
  visibleProperties: string[];
  className?: string;
}) {
  const dateFormat = useDateFormat();
  const { notes, schemas } = useVault();
  const definitions = effectivePropertyDefinitions(noteTypePath(note), schemas);
  const label = (name: string, value: PropertyValue) => {
    const type = definitions.find(({ def }) => def.name.toLowerCase() === name.toLowerCase())?.def.type ?? inferPropertyType(value);
    if (type === "date" && typeof value === "string") return formatDate(value, dateFormat);
    if (type === "relation") {
      const references = Array.isArray(value) ? value : [String(value)];
      return references.length
        ? references.map((reference) => noteReferenceLabel(reference, notes)).join(", ")
        : "No value";
    }
    return propertyLabel(value);
  };
  if (!visibleProperties.length) return null;
  const properties = getNoteProperties(note.content);
  const entries = visibleProperties.flatMap((visibleName) => {
    const match = Object.entries(properties).find(
      ([name]) => name.toLowerCase() === visibleName.toLowerCase(),
    );
    return match ? [match] : [];
  });
  if (!entries.length) return null;

  return (
    <span className={cn("flex flex-wrap gap-1.5", className)}>
      {entries.map(([name, value]) => (
        <span
          key={name.toLowerCase()}
          className={cn(
            badgeVariants({ variant: "secondary" }),
            "h-5 max-w-full gap-1 rounded-full px-2 text-[10px] font-normal",
          )}
          title={`${name}: ${label(name, value)}`}
        >
          <span className="text-muted-foreground">{name}</span>
          <span className="max-w-32 truncate">{label(name, value)}</span>
        </span>
      ))}
    </span>
  );
}
