import { chatContentRevision } from "@/lib/mobile-chat-history";
import { getNoteProperties, noteBody, type PropertyValue } from "@/lib/frontmatter";
import { noteTitle, noteTypePath, type Note } from "@/lib/note-utils";

const STOP_WORDS = new Set([
  "a", "about", "an", "and", "are", "as", "at", "be", "by", "content",
  "contents", "did", "do", "does", "entry", "explain", "extract", "for",
  "from", "how", "i", "in", "is", "it", "me", "my", "note", "notes",
  "of", "on", "or", "please", "say", "says", "summarize", "summary", "tell",
  "that", "the", "this", "to", "translate", "was", "were", "what", "when",
  "where", "which", "who", "why", "with", "write", "wrote", "you",
]);

const MAX_RESULTS = 5;
const MAX_SUGGESTIONS = 3;
const MAX_EXCERPT_CHARS = 1_600;
const MAX_CONTEXT_CHARS = 8_000;
const MAX_METADATA_PROPERTIES = 5;
const MAX_PROPERTY_VALUES = 5;

export type NoteRetrievalKind = "exact" | "content" | "similar" | "ambiguous" | "recent";
export type NoteContextKind = "matches" | "recent" | "similar" | "choices";

export interface RetrievedNote {
  id: string;
  revision: string;
  title: string;
  type: string;
  excerpt: string;
  score: number;
}

export interface NoteRetrievalResult {
  notes: RetrievedNote[];
  matched: boolean;
  totalNotes: number;
  kind: NoteRetrievalKind;
  contextKind: NoteContextKind;
  directAnswer?: string;
}

function normalize(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function normalizedPhrase(value: string): string {
  return normalize(value)
    .replace(/[’']s\b/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isLatestNoteLookup(question: string): boolean {
  const plain = normalizedPhrase(question);
  return /^(?:what|which)(?: is|s)? (?:my |the )?(?:latest|newest|most recent) (?:note|entry)$/.test(plain);
}

function updatedTime(note: Note): number {
  const time = Date.parse(note.updatedAt);
  return Number.isFinite(time) ? time : 0;
}

function queryTerms(question: string): string[] {
  return [...new Set(
    normalize(question)
      .match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu)
      ?.filter((term) => term.length > 1 && !STOP_WORDS.has(term)) ?? [],
  )];
}

function propertyEntries(note: Note): Array<[string, PropertyValue]> {
  return Object.entries(getNoteProperties(note.content))
    .filter(([key]) => !key.toLowerCase().startsWith("zerus-"));
}

function propertyText(note: Note): string {
  return propertyEntries(note)
    .map(([key, value]) => `${key}: ${Array.isArray(value) ? value.join(", ") : value}`)
    .join("\n");
}

function isEmptyProperty(value: PropertyValue): boolean {
  return typeof value === "string" ? value.trim() === ""
    : Array.isArray(value) ? value.every((item) => item.trim() === "")
    : false;
}

function humanizePropertyValue(value: string): string {
  return value
    .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2")
    .replace(/\[\[([^\]]+)\]\]/g, "$1")
    .trim();
}

function answerProperties(note: Note): { entries: Array<[string, string]>; omitted: number } {
  const eligible = propertyEntries(note)
    .map(([key, value], index) => ({ key, value, index }))
    .filter(({ key, value }) => {
      const normalizedKey = key.toLowerCase();
      return normalizedKey !== "title" && normalizedKey !== "type" && !isEmptyProperty(value);
    })
    .sort((a, b) => Number(Array.isArray(a.value)) - Number(Array.isArray(b.value)) || a.index - b.index);
  const entries: Array<[string, string]> = eligible
    .slice(0, MAX_METADATA_PROPERTIES)
    .map(({ key, value }) => {
      const rawValues = Array.isArray(value) ? value : [String(value)];
      const values = rawValues.map(humanizePropertyValue).filter(Boolean);
      const shown = values.slice(0, MAX_PROPERTY_VALUES);
      const remainder = values.length - shown.length;
      return [key, `${shown.join(", ")}${remainder > 0 ? `, and ${remainder} more` : ""}`];
    });
  return { entries, omitted: eligible.length - entries.length };
}

function typeLabel(note: Note): string {
  return noteTypePath(note).join(" / ") || "Inbox";
}

function substantiveBody(note: Note): string {
  const body = noteBody(note.content).trim();
  if (!body) return "";
  const lines = body.split("\n");
  const first = lines[0].trim();
  if (/^#{1,6}\s+/.test(first) && normalizedPhrase(first.replace(/^#{1,6}\s+/, "")) === normalizedPhrase(noteTitle(note))) {
    return lines.slice(1).join("\n").trim();
  }
  return body;
}

function requestedEmptyOperation(question: string): string | null {
  const plain = normalizedPhrase(question);
  if (/\bsummari[sz]e?\b|\bsummary\b/.test(plain)) return "summarize";
  if (/\btranslat(?:e|ion)\b/.test(plain)) return "translate";
  if (/\baction items?\b/.test(plain)) return "extract action items from";
  if (/\bquot(?:e|es)\b/.test(plain)) return "quote from";
  if (/\brewrite\b/.test(plain)) return "rewrite";
  if (/\boutline\b/.test(plain)) return "outline";
  if (/\banaly[sz]e\b/.test(plain)) return "analyze";
  if (/\bexplain\b.*\b(?:content|contents|note)\b/.test(plain)) return "explain the contents of";
  return null;
}

function metadataSentences(note: Note): string {
  const { entries, omitted } = answerProperties(note);
  const properties = entries
    .map(([key, value]) => `${key}: ${value}.`)
    .join(" ");
  return `${properties}${omitted > 0 ? `${properties ? " " : ""}And ${omitted} more ${omitted === 1 ? "property" : "properties"}.` : ""}`;
}

function emptyNoteAnswer(note: Note, question: string): string {
  const title = noteTitle(note);
  const type = typeLabel(note);
  const properties = metadataSentences(note);
  const operation = requestedEmptyOperation(question);
  if (operation) {
    return `I found “${title}”, but the note has no body content to ${operation}. It is a ${type} note.${properties ? ` ${properties}` : ""}`;
  }
  if (!properties) return `I found “${title}”, a ${type} note, but it has no content or properties.`;
  return `${title} is a ${type} note. ${properties}`;
}

function countOccurrences(haystack: string, needle: string): number {
  if (!needle) return 0;
  let count = 0;
  let from = 0;
  while (count < 8) {
    const index = haystack.indexOf(needle, from);
    if (index < 0) break;
    count += 1;
    from = index + needle.length;
  }
  return count;
}

function scoreNote(note: Note, phrase: string, terms: string[]): number {
  const title = normalize(noteTitle(note));
  const type = normalize(typeLabel(note));
  const properties = normalize(propertyText(note));
  const body = normalize(noteBody(note.content));
  let score = 0;

  if (phrase) {
    if (title === phrase) score += 180;
    else if (title.includes(phrase)) score += 110;
    if (properties.includes(phrase)) score += 75;
    if (body.includes(phrase)) score += 65;
  }

  for (const term of terms) {
    if (title === term) score += 45;
    else if (title.includes(term)) score += 28;
    if (type.includes(term)) score += 8;
    score += Math.min(countOccurrences(properties, term) * 14, 42);
    score += Math.min(countOccurrences(body, term) * 6, 30);
  }

  if (terms.length > 1 && terms.every((term) => title.includes(term))) score += 55;
  if (terms.length > 1 && terms.every((term) => `${properties}\n${body}`.includes(term))) score += 25;
  return score;
}

function modelProperties(note: Note, includeAll: boolean, phrase: string, terms: string[]): string {
  const candidates = [phrase, ...terms].filter(Boolean);
  const entries = propertyEntries(note)
    .filter(([key, value]) => {
      const normalizedKey = key.toLowerCase();
      if (normalizedKey === "title" || normalizedKey === "type" || isEmptyProperty(value)) return false;
      if (includeAll) return true;
      return candidates.some((candidate) => normalize(`${key} ${Array.isArray(value) ? value.join(" ") : value}`).includes(candidate));
    })
    .map(([key, value]) => {
      const rendered = Array.isArray(value)
        ? value.map(humanizePropertyValue).filter(Boolean).join(", ")
        : humanizePropertyValue(String(value));
      return `${key}: ${rendered}`;
    });
  return entries.join("\n");
}

function excerptFor(note: Note, phrase: string, terms: string[], includeAllProperties = false): string {
  const body = noteBody(note.content).trim();
  const searchable = normalize(body);
  const candidates = [phrase, ...terms].filter(Boolean);
  const matchIndex = candidates.reduce((best, candidate) => {
    const index = searchable.indexOf(candidate);
    return index >= 0 && (best < 0 || index < best) ? index : best;
  }, -1);

  let excerpt = body;
  if (body.length > MAX_EXCERPT_CHARS) {
    const start = matchIndex < 0 ? 0 : Math.max(0, matchIndex - 450);
    const end = Math.min(body.length, start + MAX_EXCERPT_CHARS);
    excerpt = `${start > 0 ? "…" : ""}${body.slice(start, end)}${end < body.length ? "…" : ""}`;
  }

  const relevantProperties = modelProperties(note, includeAllProperties, phrase, terms);
  return relevantProperties
    ? `${excerpt}\n\nRelevant properties:\n${relevantProperties}`
    : excerpt;
}

function retrievedNote(note: Note, score: number, excerpt: string): RetrievedNote {
  return {
    id: note.id,
    revision: chatContentRevision(note.content),
    title: noteTitle(note),
    type: typeLabel(note),
    excerpt,
    score,
  };
}

function exactTitleMatches(notes: Note[], question: string): Note[] {
  const haystack = ` ${normalizedPhrase(question)} `;
  const matches = notes.filter((note) => {
    const title = normalizedPhrase(noteTitle(note));
    return Boolean(title) && haystack.includes(` ${title} `);
  });
  const longest = Math.max(0, ...matches.map((note) => normalizedPhrase(noteTitle(note)).length));
  return matches.filter((note) => normalizedPhrase(noteTitle(note)).length === longest);
}

function levenshtein(a: string, b: string): number {
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i++) {
    const current = [i];
    for (let j = 1; j <= b.length; j++) {
      current[j] = Math.min(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + Number(a[i - 1] !== b[j - 1]),
      );
    }
    previous = current;
  }
  return previous[b.length];
}

function fuzzyTitleScore(title: string, question: string): number {
  const titleWords = normalizedPhrase(title).split(" ").filter(Boolean);
  const terms = queryTerms(question).map(normalizedPhrase).filter(Boolean);
  if (!titleWords.length || !terms.length) return 0;
  const windowSize = titleWords.length;
  const titleText = titleWords.join(" ");
  let best = 0;
  const sizes = [...new Set([windowSize - 1, windowSize, windowSize + 1].filter((size) => size > 0))];
  for (const size of sizes) {
    for (let index = 0; index + size <= terms.length; index++) {
      const candidate = terms.slice(index, index + size).join(" ");
      const distance = levenshtein(titleText, candidate);
      const similarity = 1 - distance / Math.max(titleText.length, candidate.length);
      if (similarity > best) best = similarity;
    }
  }
  return best;
}

function similarTitleMatches(notes: Note[], question: string): Array<{ note: Note; score: number }> {
  const scored = notes
    .map((note) => ({ note, score: fuzzyTitleScore(noteTitle(note), question) }))
    .filter(({ score }) => score >= 0.72)
    .sort((a, b) => b.score - a.score || noteTitle(a.note).localeCompare(noteTitle(b.note)));
  const best = scored[0]?.score ?? 0;
  return scored.filter(({ score }) => score >= Math.max(0.72, best - 0.08)).slice(0, MAX_SUGGESTIONS);
}

/**
 * Finds exact or similar note titles before falling back to lexical passage
 * retrieval. Exact empty notes and fuzzy suggestions are answered without the
 * model so that metadata is not lost and a near name is never assumed.
 */
export function retrieveNotes(notes: Note[], question: string): NoteRetrievalResult {
  if (isLatestNoteLookup(question)) {
    const latest = [...notes].sort((a, b) => updatedTime(b) - updatedTime(a))[0];
    if (!latest) {
      return { notes: [], matched: true, totalNotes: 0, kind: "exact", contextKind: "matches", directAnswer: "You don't have any active notes yet." };
    }
    return {
      notes: [retrievedNote(latest, 0, excerptFor(latest, "", [], true))],
      matched: true,
      totalNotes: notes.length,
      kind: "exact",
      contextKind: "matches",
      directAnswer: `Your latest note is “${noteTitle(latest)}”.`,
    };
  }

  const exact = exactTitleMatches(notes, question);
  if (exact.length > 1) {
    const selected = exact.slice(0, MAX_SUGGESTIONS);
    const remainder = exact.length - selected.length;
    return {
      notes: selected.map((note) => retrievedNote(note, 1, excerptFor(note, "", [], true))),
      matched: true,
      totalNotes: notes.length,
      kind: "ambiguous",
      contextKind: "choices",
      directAnswer: `I found multiple notes titled “${noteTitle(exact[0])}”. Choose the one you meant.${remainder > 0 ? ` There ${remainder === 1 ? "is" : "are"} ${remainder} more.` : ""}`,
    };
  }
  if (exact.length === 1) {
    const note = exact[0];
    const excerpt = excerptFor(note, "", [], true);
    return {
      notes: [retrievedNote(note, 1, excerpt)],
      matched: true,
      totalNotes: notes.length,
      kind: "exact",
      contextKind: "matches",
      directAnswer: substantiveBody(note) ? undefined : emptyNoteAnswer(note, question),
    };
  }

  const similar = similarTitleMatches(notes, question);
  if (similar.length > 0) {
    return {
      notes: similar.map(({ note, score }) => retrievedNote(note, score, excerptFor(note, "", [], true))),
      matched: false,
      totalNotes: notes.length,
      kind: "similar",
      contextKind: "similar",
      directAnswer: "I couldn’t find an exact note with that title. I found some similarly named notes.",
    };
  }

  const terms = queryTerms(question);
  const phrase = terms.join(" ");
  const ranked = notes
    .map((note) => ({ note, score: scoreNote(note, phrase, terms) }))
    .sort((a, b) => b.score - a.score || updatedTime(b.note) - updatedTime(a.note));
  const matched = ranked.some((item) => item.score > 0);
  const candidates = matched
    ? ranked.filter((item) => item.score > 0)
    : ranked.sort((a, b) => updatedTime(b.note) - updatedTime(a.note));

  const selected: RetrievedNote[] = [];
  let usedChars = 0;
  for (const { note, score } of candidates.slice(0, MAX_RESULTS)) {
    const excerpt = excerptFor(note, phrase, terms);
    const remaining = MAX_CONTEXT_CHARS - usedChars;
    if (remaining <= 0) break;
    const boundedExcerpt = excerpt.slice(0, remaining);
    selected.push(retrievedNote(note, score, boundedExcerpt));
    usedChars += boundedExcerpt.length;
  }

  return {
    notes: selected,
    matched,
    totalNotes: notes.length,
    kind: matched ? "content" : "recent",
    contextKind: matched ? "matches" : "recent",
  };
}
