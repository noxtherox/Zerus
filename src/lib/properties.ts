import type { PropertyValue } from "@/lib/frontmatter";

/**
 * Property definitions can live on any note type and cascade to sub-types.
 * Values are stored per note as YAML frontmatter; definitions are stored per
 * vault in `.zerus/properties.json`.
 */

export type PropertyType =
  | "text"
  | "url"
  | "number"
  | "date"
  | "checkbox"
  | "list"
  | "relation";

export interface PropertyDef {
  name: string;
  type: PropertyType;
  /** list only: the choices available when editing a note. */
  listOptions?: string[];
  /** list only: allow selecting more than one choice. */
  listMultiple?: boolean;
  /** relation only: restrict linkable notes to this type (and its sub-types). Unset = any type. */
  relationTypeKey?: string;
  /** relation only: allow linking more than one note. */
  relationMultiple?: boolean;
}

/** Type path key ("work/projects") -> definitions owned by that type tree. */
export type PropertySchemas = Record<string, PropertyDef[]>;

export interface EffectivePropertyDef {
  def: PropertyDef;
  ownerKey: string;
}

export const PROPERTY_TYPES: { value: PropertyType; label: string }[] = [
  { value: "text", label: "Text" },
  { value: "url", label: "URL" },
  { value: "number", label: "Number" },
  { value: "date", label: "Date" },
  { value: "checkbox", label: "Checkbox" },
  { value: "list", label: "List" },
  { value: "relation", label: "Relation" },
];

/** The schema key for a type path ("" for unfiled notes). */
export function schemaKeyFor(typePath: string[]): string {
  return typePath.join("/");
}

/**
 * Properties that apply to a note of the given type. Parent definitions are
 * inherited; a same-named definition on a deeper type overrides its parent.
 */
export function effectivePropertyDefinitions(
  typePath: string[],
  schemas: PropertySchemas,
): EffectivePropertyDef[] {
  const effective: EffectivePropertyDef[] = [];
  const positions = new Map<string, number>();
  const ownerKeys = typePath.length
    ? typePath.map((_, index) => typePath.slice(0, index + 1).join("/"))
    : [""];

  for (const ownerKey of ownerKeys) {
    for (const def of schemas[ownerKey] ?? []) {
      const name = def.name.toLowerCase();
      const existing = positions.get(name);
      const entry = { def, ownerKey };
      if (existing === undefined) {
        positions.set(name, effective.length);
        effective.push(entry);
      } else {
        effective[existing] = entry;
      }
    }
  }
  return effective;
}

export function effectiveProperties(
  typePath: string[],
  schemas: PropertySchemas,
): PropertyDef[] {
  return effectivePropertyDefinitions(typePath, schemas).map(({ def }) => def);
}

/** The type path that owns the effective definition, if one applies. */
export function propertyDefinitionOwner(
  typePath: string[],
  schemas: PropertySchemas,
  name: string,
): string | null {
  const normalized = name.toLowerCase();
  return (
    effectivePropertyDefinitions(typePath, schemas).find(
      ({ def }) => def.name.toLowerCase() === normalized,
    )?.ownerKey ?? null
  );
}

/** A frontmatter-safe property name (must survive `name: value` parsing). */
export function sanitizePropertyName(input: string): string {
  const name = input
    .replace(/[^A-Za-z0-9_ .-]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^[ .-]+/, "")
    .slice(0, 60)
    .trim();
  return name;
}

/** Trims list choices and removes blank or case-insensitive duplicates. */
export function normalizeListOptions(options: string[]): string[] {
  const normalized: string[] = [];
  const seen = new Set<string>();
  for (const option of options) {
    const trimmed = option.trim();
    const key = trimmed.toLowerCase();
    if (!trimmed || seen.has(key)) continue;
    seen.add(key);
    normalized.push(trimmed);
  }
  return normalized;
}

/** Reads either legacy scalar values or YAML arrays as list selections. */
export function listSelections(
  value: PropertyValue | undefined,
): string[] {
  if (Array.isArray(value)) return normalizeListOptions(value);
  if (value === undefined || value === null || value === "") return [];
  return [String(value)];
}

/** Serializes selected list choices according to the definition's mode. */
export function listPropertyValue(
  selections: string[],
  multiple: boolean,
): PropertyValue | null {
  const normalized = normalizeListOptions(selections);
  if (!normalized.length) return null;
  return multiple ? normalized : normalized[0];
}

/** Best-guess property type for an existing frontmatter value. */
export function inferPropertyType(value: PropertyValue): PropertyType {
  if (typeof value === "boolean") return "checkbox";
  if (typeof value === "number") return "number";
  if (Array.isArray(value)) return "list";
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return "date";
  return "text";
}
