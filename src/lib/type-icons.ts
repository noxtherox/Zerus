/** Custom type icons, keyed by full type key ("work/projects"). Tabler icon
 * values use a namespaced identifier ("tabler:Briefcase"); existing native
 * emoji values remain valid for backwards compatibility. */
export type TypeIcons = Record<string, string>;

export const TABLER_ICON_PREFIX = "tabler:";

export function tablerIconValue(name: string): string {
  return `${TABLER_ICON_PREFIX}${name}`;
}

export function tablerIconName(value: unknown): string | null {
  if (typeof value !== "string" || !value.startsWith(TABLER_ICON_PREFIX)) {
    return null;
  }
  const name = value.slice(TABLER_ICON_PREFIX.length);
  return /^[A-Za-z][A-Za-z0-9]*$/.test(name) ? name : null;
}

/** True for legacy values that render as native emoji. */
export function isEmojiValue(value: unknown): value is string {
  return (
    typeof value === "string" &&
    !value.startsWith(TABLER_ICON_PREFIX) &&
    /\P{ASCII}/u.test(value)
  );
}

export function isTypeIconValue(value: unknown): value is string {
  return isEmojiValue(value) || tablerIconName(value) !== null;
}

// Concept matching makes newly created types useful immediately without
// loading the full picker catalog. Values are verified against Tabler in tests.
const KEYWORD_ICONS: Record<string, string> = {
  work: "Briefcase", job: "Briefcase", career: "Briefcase", business: "Briefcase",
  office: "Building", company: "Building", project: "FolderCode", task: "Checklist",
  todo: "Checklist", checklist: "Checklist", goal: "Target", habit: "Repeat",
  journal: "Notebook", diary: "Notebook", daily: "Calendar", weekly: "CalendarWeek",
  event: "CalendarEvent", calendar: "Calendar", note: "Note", draft: "FileText",
  idea: "Bulb", brainstorm: "Bulb", inbox: "Inbox", archive: "Archive",
  template: "Template", meeting: "Users", people: "Users", team: "Users",
  friend: "Friends", person: "User", personal: "User", contact: "AddressBook",
  family: "UsersGroup", kid: "BabyCarriage", child: "BabyCarriage", baby: "BabyCarriage",
  book: "Book", library: "Library", reading: "Book2", story: "Book2",
  study: "School", writing: "Writing", contract: "Signature", blog: "Article",
  article: "Article", news: "News", quote: "Quote", chat: "MessageCircle",
  interview: "Messages", poem: "Feather", poetry: "Feather", recipe: "ChefHat",
  cooking: "ToolsKitchen2", baking: "Cake", food: "ToolsKitchen2", meal: "ToolsKitchen2",
  restaurant: "ToolsKitchen2", coffee: "Coffee", wine: "Glass", beer: "Beer",
  travel: "Plane", trip: "Plane", flight: "Plane", vacation: "Beach",
  holiday: "Beach", hiking: "Mountain", camping: "Tent", finance: "Wallet",
  money: "Cash", budget: "Calculator", bank: "BuildingBank", invest: "ChartLine",
  investment: "ChartLine", stock: "ChartLine", sales: "ChartLine", crypto: "CurrencyBitcoin",
  tax: "ReceiptTax", invoice: "FileInvoice", receipt: "Receipt", subscription: "CreditCard",
  shopping: "ShoppingCart", grocery: "ShoppingBag", wishlist: "Gift", gift: "Gift",
  christmas: "ChristmasTree", health: "HeartRateMonitor", medical: "Stethoscope",
  doctor: "Stethoscope", medicine: "Pill", fitness: "Barbell", workout: "Barbell",
  gym: "Barbell", running: "Run", yoga: "Yoga", meditation: "Sparkles",
  sleep: "Moon", dream: "MoonStars", code: "Code", coding: "Code",
  programming: "Code", dev: "Code", software: "Code", snippet: "Braces",
  bug: "Bug", server: "Server", terminal: "Terminal2", database: "Database",
  api: "Api", design: "Palette", art: "Palette", drawing: "Pencil",
  photo: "Photo", photography: "Camera", video: "Video", music: "Music",
  song: "Music", podcast: "Microphone", movie: "Movie", film: "Movie",
  tv: "DeviceTv", show: "DeviceTv", anime: "DeviceTv", game: "DeviceGamepad2",
  gaming: "DeviceGamepad2", chess: "Chess", hobby: "Puzzle", school: "School",
  course: "School", class: "School", learning: "School", education: "School",
  research: "Microscope", science: "Flask", math: "Math", language: "Language",
  history: "History", philosophy: "BuildingPavilion", religion: "BuildingChurch",
  garden: "Plant", plant: "Plant2", nature: "Trees", weather: "SunHigh",
  pet: "Paw", dog: "Dog", cat: "Cat", bird: "Feather", fish: "Fish",
  car: "Car", auto: "Car", bike: "Bike", motorcycle: "Motorbike", boat: "Sailboat",
  home: "Home", house: "Home", apartment: "BuildingCommunity", renovation: "Hammer",
  diy: "Hammer", repair: "Tool", tool: "Tool", cleaning: "Spray",
  birthday: "Cake", wedding: "Diamond", party: "Confetti", email: "Mail",
  letter: "Mail", phone: "Phone", call: "PhoneCall", password: "Key",
  secret: "Key", security: "ShieldLock", insurance: "ShieldCheck", legal: "Scale",
  law: "Scale", favorite: "Star", important: "Star", urgent: "AlertTriangle",
  random: "Dice", misc: "Category", private: "Lock", client: "HeartHandshake",
  customer: "HeartHandshake", marketing: "Speakerphone", product: "Package", startup: "Rocket",
  weld: "Flame", welding: "Flame",
};

function singulars(word: string): string[] {
  if (word.length > 3 && word.endsWith("ies")) {
    return [`${word.slice(0, -3)}y`, word.slice(0, -1)];
  }
  if (word.length > 3 && word.endsWith("es")) {
    return [word.slice(0, -1), word.slice(0, -2)];
  }
  if (word.length > 2 && word.endsWith("s")) return [word.slice(0, -1)];
  return [];
}

/** Picks a fitting Tabler icon for a new type, or null when no concept matches. */
export async function suggestIconForType(typeName: string): Promise<string | null> {
  const raw = typeName.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  const words = [...new Set(raw.flatMap((word) => [word, ...singulars(word)]))];
  for (const word of words) {
    const icon = KEYWORD_ICONS[word];
    if (icon) return tablerIconValue(icon);
  }
  return null;
}
