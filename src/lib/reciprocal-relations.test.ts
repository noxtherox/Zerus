import { describe, expect, it } from "vitest";
import { reciprocalRelation } from "./reciprocal-relations";
import { getBacklinksGroupedByType, hasRelationTo } from "./links";
import { setContentProperty } from "./frontmatter";
import { noteReference, type Note } from "./note-utils";
import type { PropertySchemas } from "./properties";

const note = (id: string, folder: string): Note => ({ id, path: `${folder}/${id}.md`, content: `# ${id}`, pinned: false, updatedAt: "2026-09-11" });
const source = note("Task", "Work/Tasks");
const target = note("Epic", "Work/Epics");

describe("inline reciprocal relations", () => {
  it("creates a typed reverse relation for a newly created note and hides the redundant backlink", () => {
    const schemas: PropertySchemas = { "Work/Tasks": [{ name: "Epic", type: "relation", relationTypeKey: "Work/Epics" }] };
    const reverse = reciprocalRelation(source, target, schemas)!;
    expect(reverse.createDefinition).toBe(true);
    expect(reverse.definition).toEqual({ name: "Tasks", type: "relation", relationTypeKey: "Work/Tasks", relationMultiple: true });
    schemas["Work/Epics"] = [reverse.definition];
    const a = { ...source, content: setContentProperty(source.content, "Epic", noteReference(target)) };
    const b = { ...target, content: setContentProperty(target.content, reverse.definition.name, reverse.value) };
    expect(hasRelationTo(a, b, schemas)).toBe(true);
    expect(hasRelationTo(b, a, schemas)).toBe(true);
    expect(getBacklinksGroupedByType(b, [a, b], schemas).size).toBe(0);
    expect(reciprocalRelation(a, b, schemas)).toBeNull();
  });

  it("reuses the most specific compatible inherited relation and preserves its values", () => {
    const schemas: PropertySchemas = { Work: [
      { name: "General", type: "relation", relationMultiple: true },
      { name: "Tasks", type: "relation", relationTypeKey: "Work/Tasks", relationMultiple: true },
    ] };
    const existing = { ...target, content: setContentProperty(target.content, "Tasks", ["Other task"]) };
    expect(reciprocalRelation(source, existing, schemas)).toMatchObject({ createDefinition: false, definition: { name: "Tasks" }, value: ["Other task", noteReference(source)] });
  });

  it("fills an empty single relation", () => {
    expect(reciprocalRelation(source, target, { "Work/Epics": [{ name: "Task", type: "relation", relationTypeKey: "Work/Tasks" }] })).toMatchObject({ createDefinition: false, value: noteReference(source) });
  });

  it("does not overwrite occupied single relations, unrelated fields, or incompatible relations", () => {
    const existing = { ...target, content: setContentProperty(target.content, "Tasks", "Other task") };
    const schemas: PropertySchemas = { "Work/Epics": [
      { name: "Tasks", type: "relation", relationTypeKey: "Work/Tasks" },
      { name: "Tasks 2", type: "text" },
      { name: "Products", type: "relation", relationTypeKey: "Products", relationMultiple: true },
    ] };
    expect(reciprocalRelation(source, existing, schemas)).toMatchObject({ createDefinition: true, definition: { name: "Tasks 3" }, value: [noteReference(source)] });
  });

  it("does not duplicate existing legacy-title relations or self relations", () => {
    const existing = { ...target, content: setContentProperty(target.content, "Tasks", ["Task"]) };
    expect(reciprocalRelation(source, existing, { "Work/Epics": [{ name: "Tasks", type: "relation", relationMultiple: true }] })).toBeNull();
    expect(reciprocalRelation(source, source, {})).toBeNull();
  });
});
