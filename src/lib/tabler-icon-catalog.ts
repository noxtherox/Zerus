import { icons, type Icon } from "@tabler/icons-react";

export interface TablerIconEntry {
  name: string;
  label: string;
  searchText: string;
  Icon: Icon;
}

function labelForIcon(name: string): string {
  return name
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2");
}

const FEATURED_NAMES = [
  "Folder", "Home", "Briefcase", "Book", "Notebook", "Note", "FileText",
  "Checklist", "Calendar", "Clock", "Bulb", "Star", "Heart", "User", "Users",
  "MessageCircle", "Mail", "Phone", "Camera", "Photo", "Music", "Movie",
  "Palette", "Code", "Terminal2", "Database", "Rocket", "Target", "ChartLine",
  "Wallet", "ShoppingCart", "Gift", "Plane", "Map", "Beach", "Mountain", "Tent",
  "ChefHat", "Coffee", "ToolsKitchen2", "Stethoscope", "Barbell", "Run", "Moon",
  "Sparkles", "Plant2", "Trees", "Paw", "Dog", "Cat", "Car", "Bike", "Gamepad2",
  "School", "Microscope", "Flask", "Lock", "Key", "Shield", "Tool", "Hammer",
];

const FEATURED_ORDER = new Map(FEATURED_NAMES.map((name, index) => [name, index]));

export const TABLER_ICON_ENTRIES: TablerIconEntry[] = Object.entries(icons)
  .filter(([exportName]) => exportName.startsWith("Icon") && !exportName.endsWith("Filled"))
  .map(([exportName, Icon]) => {
    const name = exportName.slice(4);
    const label = labelForIcon(name);
    return { name, label, searchText: label.toLowerCase(), Icon };
  })
  .sort((left, right) => {
    const leftFeatured = FEATURED_ORDER.get(left.name);
    const rightFeatured = FEATURED_ORDER.get(right.name);
    if (leftFeatured !== undefined || rightFeatured !== undefined) {
      if (leftFeatured === undefined) return 1;
      if (rightFeatured === undefined) return -1;
      return leftFeatured - rightFeatured;
    }
    return left.label.localeCompare(right.label);
  });

export const TABLER_ICONS_BY_NAME = new Map(
  TABLER_ICON_ENTRIES.map((entry) => [entry.name, entry.Icon]),
);

export function searchTablerIcons(query: string): TablerIconEntry[] {
  const words = query.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  if (!words.length) return TABLER_ICON_ENTRIES;
  return TABLER_ICON_ENTRIES.filter((entry) =>
    words.every((word) => entry.searchText.includes(word)),
  );
}
