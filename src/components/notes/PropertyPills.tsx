import { badgeVariants } from "@/components/ui/badge";
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
          title={`${name}: ${propertyLabel(value)}`}
        >
          <span className="text-muted-foreground">{name}</span>
          <span className="max-w-32 truncate">{propertyLabel(value)}</span>
        </span>
      ))}
    </span>
  );
}
