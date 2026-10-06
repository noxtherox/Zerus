import type { VaultBackend } from "@/lib/vault/backend";

export const PROPERTIES_PANE_PATH = ".zerus/properties-pane.json";
export const PROPERTIES_PANE_SECTIONS = ["properties", "revisions", "relations", "outline", "attachments"] as const;
export type PropertiesPaneSection = (typeof PROPERTIES_PANE_SECTIONS)[number];
export const PROPERTIES_PANE_LABELS: Record<PropertiesPaneSection, string> = {
  properties: "Properties", revisions: "Revisions", relations: "Relations", outline: "Outline", attachments: "Attachments",
};
export interface PropertiesPaneLayout {
  order: PropertiesPaneSection[];
  collapsed: PropertiesPaneSection[];
}
export const DEFAULT_PROPERTIES_PANE_LAYOUT: PropertiesPaneLayout = {
  order: [...PROPERTIES_PANE_SECTIONS], collapsed: [],
};

export function normalizePropertiesPaneLayout(value: unknown): PropertiesPaneLayout {
  const record = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const sections = (input: unknown): PropertiesPaneSection[] => Array.isArray(input)
    ? [...new Set(input.filter((id): id is PropertiesPaneSection => PROPERTIES_PANE_SECTIONS.includes(id)))] : [];
  return {
    order: [...new Set([...sections(record.order), ...PROPERTIES_PANE_SECTIONS])],
    collapsed: sections(record.collapsed),
  };
}

export async function loadPropertiesPaneLayout(backend: VaultBackend): Promise<PropertiesPaneLayout> {
  try {
    return normalizePropertiesPaneLayout(JSON.parse(await backend.readText(PROPERTIES_PANE_PATH)));
  } catch {
    return normalizePropertiesPaneLayout(null);
  }
}
