import { getNoteProperties } from "@/lib/frontmatter";
import {
  effectiveProperties,
  schemaKeyFor,
  type PropertyDef,
  type PropertySchemas,
} from "@/lib/properties";
import {
  isExternalNote,
  isSavedLinkNote,
  isTrashed,
  noteTitle,
  noteTypePath,
  notesOfTypeKey,
  type Note,
} from "@/lib/note-utils";

function propertyValueExists(note: Note, name: string): boolean {
  const normalized = name.toLowerCase();
  return Object.keys(getNoteProperties(note.content)).some(
    (key) => key.toLowerCase() === normalized,
  );
}

function addDefinitions(
  schemas: PropertySchemas,
  ownerKey: string,
  definitions: PropertyDef[],
): PropertySchemas {
  if (!definitions.length) return schemas;
  return {
    ...schemas,
    [ownerKey]: [...(schemas[ownerKey] ?? []), ...definitions],
  };
}

/**
 * Carries populated relation definitions with a note when its folder-backed
 * type changes. Values already live in the note's frontmatter; copying the
 * definitions prevents them from degrading into untyped, ad-hoc properties.
 */
export function preserveRelationsForTypeMove(
  note: Note,
  targetTypePath: string[],
  schemas: PropertySchemas,
): PropertySchemas {
  const targetDefinitions = effectiveProperties(targetTypePath, schemas);
  const additions = effectiveProperties(noteTypePath(note), schemas).filter(
    (definition) =>
      definition.type === "relation" &&
      propertyValueExists(note, definition.name) &&
      !targetDefinitions.some(
        (target) => target.name.toLowerCase() === definition.name.toLowerCase(),
      ),
  );
  return addDefinitions(schemas, schemaKeyFor(targetTypePath), additions);
}

function sameRelationShape(left: PropertyDef, right: PropertyDef): boolean {
  return (
    left.type === "relation" &&
    right.type === "relation" &&
    (left.relationTypeKey ?? "") === (right.relationTypeKey ?? "") &&
    Boolean(left.relationMultiple) === Boolean(right.relationMultiple)
  );
}

function relationValuesResolve(
  value: ReturnType<typeof getNoteProperties>[string],
  definition: PropertyDef,
  notes: Note[],
): boolean {
  const titles = (Array.isArray(value) ? value : [value])
    .map(String)
    .map((title) => title.trim())
    .filter(Boolean);
  if (!titles.length) return false;
  const candidates = definition.relationTypeKey
    ? notesOfTypeKey(notes, definition.relationTypeKey)
    : notes;
  return titles.every((title) =>
    candidates.some((candidate) => noteTitle(candidate) === title),
  );
}

/**
 * Repairs notes moved by older versions. An uncovered frontmatter field is
 * recovered only when its name has one unambiguous relation shape everywhere
 * in the vault and every stored value resolves to an eligible note title.
 */
export function recoverLegacyMovedRelations(
  notes: Note[],
  schemas: PropertySchemas,
): PropertySchemas {
  const definitionsByName = new Map<string, PropertyDef[]>();
  for (const definitions of Object.values(schemas)) {
    for (const definition of definitions) {
      const name = definition.name.toLowerCase();
      definitionsByName.set(name, [
        ...(definitionsByName.get(name) ?? []),
        definition,
      ]);
    }
  }

  let next = schemas;
  for (const note of notes) {
    if (isExternalNote(note) || isSavedLinkNote(note) || isTrashed(note)) continue;
    const typePath = noteTypePath(note);
    const covered = new Set(
      effectiveProperties(typePath, next).map((definition) =>
        definition.name.toLowerCase(),
      ),
    );
    const additions: PropertyDef[] = [];
    for (const [name, value] of Object.entries(getNoteProperties(note.content))) {
      const normalized = name.toLowerCase();
      if (covered.has(normalized)) continue;
      const candidates = definitionsByName.get(normalized) ?? [];
      const relation = candidates[0];
      if (
        !relation ||
        relation.type !== "relation" ||
        !candidates.every((candidate) => sameRelationShape(relation, candidate)) ||
        !relationValuesResolve(value, relation, notes)
      ) {
        continue;
      }
      additions.push({ ...relation, name });
      covered.add(normalized);
    }
    next = addDefinitions(next, schemaKeyFor(typePath), additions);
  }
  return next;
}
