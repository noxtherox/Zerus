import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import { hasRelationTo } from "@/lib/links";
import { noteReference, noteTypePath, type Note } from "@/lib/note-utils";
import { effectiveProperties, sanitizePropertyName, schemaKeyFor, type PropertyDef, type PropertySchemas } from "@/lib/properties";

/** Choose a reverse field without replacing an existing single-note relation. */
export function reciprocalRelation(
  source: Note,
  target: Note,
  schemas: PropertySchemas,
): { definition: PropertyDef; createDefinition: boolean; value: PropertyValue } | null {
  if (source.id === target.id || hasRelationTo(target, source, schemas)) return null;
  const sourcePath = noteTypePath(source);
  const sourceKey = schemaKeyFor(sourcePath);
  const definitions = effectiveProperties(noteTypePath(target), schemas);
  const properties = getNoteProperties(target.content);
  const valueFor = (name: string) => properties[Object.keys(properties).find(key => key.toLowerCase() === name.toLowerCase()) ?? name];
  const valuesFor = (name: string) => {
    const value = valueFor(name);
    return value == null || value === "" ? [] : Array.isArray(value) ? value : [String(value)];
  };
  const candidates = definitions.filter(def =>
    def.type === "relation" &&
    (!def.relationTypeKey || sourceKey === def.relationTypeKey || sourceKey.startsWith(`${def.relationTypeKey}/`)) &&
    (def.relationMultiple || valuesFor(def.name).length === 0),
  ).sort((a, b) => (b.relationTypeKey?.length ?? 0) - (a.relationTypeKey?.length ?? 0));
  let definition = candidates[0];
  const createDefinition = !definition;
  if (!definition) {
    const occupied = new Set([...definitions.map(def => def.name), ...Object.keys(properties)].map(name => name.toLowerCase()));
    const base = sanitizePropertyName(sourcePath.at(-1) ?? "Related notes") || "Related notes";
    let name = base;
    for (let suffix = 2; occupied.has(name.toLowerCase()); suffix++) name = `${base} ${suffix}`;
    definition = { name, type: "relation", relationTypeKey: sourceKey || undefined, relationMultiple: true };
  }
  const reference = noteReference(source);
  return {
    definition,
    createDefinition,
    value: definition.relationMultiple ? [...valuesFor(definition.name), reference] : reference,
  };
}
