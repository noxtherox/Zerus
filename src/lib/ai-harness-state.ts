import type { VaultBackend } from "./vault/backend";
import type { AiToolCall } from "./ai-tool-schemas";
import { validateAiToolCall } from "./ai-tool-schemas";
import { z } from "zod";

export type AgentMode = "ask" | "review" | "edit";
export interface AgentSettings {
  mode: AgentMode;
  writeScope: "context" | "current";
  maxSteps: number;
  maxOutputTokens: number;
  maxInputTokens: number;
  maxMinutes: number;
  maxTotalTokens: number;
  textFallback: boolean;
  effort: "low" | "medium" | "high";
  workers: boolean;
  workflow: string;
}
export const DEFAULT_AGENT_SETTINGS: AgentSettings = {
  mode: "review",
  writeScope: "context",
  maxSteps: 30,
  maxOutputTokens: 8_192,
  maxInputTokens: 48_000,
  maxMinutes: 10,
  maxTotalTokens: 160_000,
  textFallback: false,
  effort: "medium",
  workers: false,
  workflow: "",
};
export interface AgentPlanStep {
  text: string;
  status: "pending" | "running" | "complete";
}
export interface AgentSnapshot {
  id: string;
  title: string;
  path: string;
  content: string;
  revision: string;
  pinned?: boolean;
  archived?: boolean;
}
export interface AgentProposal {
  id: string;
  call: AiToolCall;
  before: AgentSnapshot[];
  after: string;
  afterPath?: string;
  relatedAfter?: AgentSnapshot[];
  label: string;
  targetId?: string;
  status:
    | "pending"
    | "approved"
    | "applying"
    | "applied"
    | "rejected"
    | "conflict";
}
export interface AgentReceipt {
  id: string;
  operationKey: string;
  proposalId: string;
  before: AgentSnapshot[];
  after: AgentSnapshot[];
  at: string;
  undoneAt?: string;
}
export interface AgentRunEvent {
  id: string;
  at: string;
  kind:
    | "started"
    | "activity"
    | "tool"
    | "committed"
    | "approval"
    | "question"
    | "steering"
    | "compacted"
    | "finished"
    | "error";
  text: string;
  detail?: unknown;
}
export interface AgentRun {
  version: 1;
  id: string;
  chatId: string;
  ownerId: string;
  objective: string;
  mode: AgentMode;
  readIds: string[];
  writeIds: string[];
  createTypes: string[];
  scopeKey?: string;
  parentRunId?: string;
  status: "running" | "waiting" | "interrupted" | "complete" | "partial";
  plan: AgentPlanStep[];
  proposals: AgentProposal[];
  receipts: AgentReceipt[];
  events: AgentRunEvent[];
  messages: unknown[];
  question?: { question: string; options?: string[] };
  usage: {
    inputTokens: number;
    outputTokens: number;
    steps: number;
    elapsedMs: number;
    budgetTokens?: number;
  };
  updatedAt: string;
}

const SETTINGS_PATH = ".zerus/ai/settings.json";
const MEMORY_PATH = ".zerus/ai/memory.md";
const INSTRUCTIONS_PATH = ".zerus/ai/instructions.md";
const safeId = (id: string) => {
  if (!/^[\w-]{1,100}$/.test(id)) throw new Error("Invalid chat/run identity");
  return id;
};
const runPath = (chatId: string, runId: string) =>
  `.zerus/ai/runs/${safeId(chatId)}/${safeId(runId)}.json`;

export function normalizeAgentSettings(
  value: Partial<AgentSettings> = {},
): AgentSettings {
  const bounded = (
    input: unknown,
    fallback: number,
    min: number,
    max: number,
  ) =>
    typeof input === "number" && Number.isFinite(input)
      ? Math.max(min, Math.min(max, Math.floor(input)))
      : fallback;
  return {
    mode: value.mode === "ask" || value.mode === "edit" ? value.mode : "review",
    writeScope: value.writeScope === "current" ? "current" : "context",
    maxSteps: bounded(value.maxSteps, 30, 2, 100),
    maxOutputTokens: bounded(value.maxOutputTokens, 8192, 1024, 32768),
    maxInputTokens: bounded(value.maxInputTokens, 48000, 4096, 200000),
    maxMinutes: bounded(value.maxMinutes, 10, 1, 30),
    maxTotalTokens: bounded(value.maxTotalTokens, 160000, 8000, 1000000),
    textFallback: value.textFallback === true,
    effort:
      value.effort === "low" || value.effort === "high"
        ? value.effort
        : "medium",
    workers: value.workers === true,
    workflow: typeof value.workflow === "string" ? value.workflow : "",
  };
}

export async function loadAgentSettings(
  backend: VaultBackend | null,
): Promise<AgentSettings> {
  if (!backend) return { ...DEFAULT_AGENT_SETTINGS };
  try {
    return normalizeAgentSettings(
      JSON.parse(await backend.readText(SETTINGS_PATH)),
    );
  } catch {
    return { ...DEFAULT_AGENT_SETTINGS };
  }
}
export async function saveAgentSettings(
  backend: VaultBackend,
  settings: AgentSettings,
) {
  await backend.write(
    SETTINGS_PATH,
    JSON.stringify(normalizeAgentSettings(settings), null, 2),
  );
}
export async function loadAgentGuidance(
  backend: VaultBackend,
): Promise<{ instructions: string; memory: string }> {
  const read = async (path: string, limit: number) => {
    try {
      return (await backend.readText(path)).slice(0, limit);
    } catch {
      return "";
    }
  };
  const [instructions, memory] = await Promise.all([
    read(INSTRUCTIONS_PATH, 12_000),
    read(MEMORY_PATH, 8_000),
  ]);
  return { instructions, memory };
}
export async function saveAgentGuidance(
  backend: VaultBackend,
  kind: "instructions" | "memory",
  text: string,
) {
  const max = kind === "memory" ? 8_000 : 12_000;
  if (text.length > max)
    throw new Error(`Keep ${kind} under ${max.toLocaleString()} characters.`);
  await backend.write(
    kind === "memory" ? MEMORY_PATH : INSTRUCTIONS_PATH,
    text,
  );
}
export async function persistAgentRun(backend: VaultBackend, run: AgentRun) {
  run.updatedAt = new Date().toISOString();
  await backend.write(runPath(run.chatId, run.id), JSON.stringify(run));
}
const notePath = z
  .string()
  .refine(
    (path) =>
      !path.startsWith("/") &&
      !path.includes("\\") &&
      !/^[A-Za-z]:/.test(path) &&
      path.endsWith(".md") &&
      path
        .split("/")
        .every(
          (part, index) =>
            part.length > 0 &&
            (part === ".trash" ? index === 0 : !part.startsWith(".")),
        ),
  );
const identity = z.string().regex(/^[\w-]{1,100}$/);
const snapshot = z.object({
  id: identity,
  title: z.string(),
  path: notePath,
  content: z.string(),
  revision: z.string(),
  pinned: z.boolean().optional(),
  archived: z.boolean().optional(),
});
const savedCall = z
  .object({ name: z.string(), arguments: z.unknown() })
  .refine((call) => {
    try {
      validateAiToolCall(call.name, call.arguments);
      return true;
    } catch {
      return false;
    }
  });
const savedRun = z.object({
  version: z.literal(1),
  id: identity,
  chatId: identity,
  ownerId: identity,
  objective: z.string(),
  mode: z.enum(["ask", "review", "edit"]),
  readIds: z.array(identity),
  writeIds: z.array(identity),
  createTypes: z.array(z.string()),
  scopeKey: z.string().optional(),
  parentRunId: identity.optional(),
  status: z.enum(["running", "waiting", "interrupted", "complete", "partial"]),
  plan: z.array(
    z.object({
      text: z.string(),
      status: z.enum(["pending", "running", "complete"]),
    }),
  ),
  proposals: z.array(
    z
      .object({
        id: identity,
        call: savedCall,
        before: z.array(snapshot),
        after: z.string(),
        afterPath: notePath.optional(),
        relatedAfter: z.array(snapshot).optional(),
        label: z.string(),
        targetId: identity.optional(),
        status: z.enum([
          "pending",
          "approved",
          "applying",
          "applied",
          "rejected",
          "conflict",
        ]),
      })
      .refine((proposal) =>
        proposal.call.name === "note_create"
          ? proposal.before.length === 0 && Boolean(proposal.targetId)
          : proposal.before.length > 0 &&
            proposal.before
              .slice(1)
              .every((note) =>
                proposal.relatedAfter?.some((after) => after.id === note.id),
              ),
      ),
  ),
  receipts: z.array(
    z.object({
      id: identity,
      operationKey: z.string(),
      proposalId: identity,
      before: z.array(snapshot),
      after: z.array(snapshot).min(1),
      at: z.string(),
      undoneAt: z.string().optional(),
    }),
  ),
  events: z.array(
    z.object({
      id: identity,
      at: z.string(),
      kind: z.enum([
        "started",
        "activity",
        "tool",
        "committed",
        "approval",
        "question",
        "steering",
        "compacted",
        "finished",
        "error",
      ]),
      text: z.string(),
      detail: z.unknown().optional(),
    }),
  ),
  messages: z.array(z.unknown()),
  question: z
    .object({ question: z.string(), options: z.array(z.string()).optional() })
    .optional(),
  usage: z.object({
    inputTokens: z.number().nonnegative(),
    outputTokens: z.number().nonnegative(),
    steps: z.number().nonnegative(),
    elapsedMs: z.number().nonnegative(),
    budgetTokens: z.number().nonnegative().optional(),
  }),
  updatedAt: z.string(),
});
export async function loadAgentRuns(
  backend: VaultBackend,
  chatId: string,
): Promise<AgentRun[]> {
  const paths = await backend
    .listFiles(`.zerus/ai/runs/${safeId(chatId)}`)
    .catch(() => []);
  const results = await Promise.all(
    paths
      .filter((path) => path.endsWith(".json"))
      .map(async (path) => {
        try {
          const run = savedRun.parse(
            JSON.parse(await backend.readText(path)),
          ) as AgentRun;
          if (
            run.chatId !== chatId ||
            path !== runPath(chatId, run.id) ||
            run.parentRunId
          )
            return null;
          return run;
        } catch {
          return null;
        }
      }),
  );
  return results
    .filter((run): run is AgentRun => run !== null)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export const BUILTIN_NOTE_WORKFLOWS = [
  {
    id: "meeting",
    title: "Clean up meeting notes",
    instructions:
      "Find the meeting notes in scope. Preserve decisions, names and dates. Organize discussion, decisions, questions and action items into clear sections. Do not invent owners or deadlines. Patch existing notes and verify the result.",
  },
  {
    id: "synthesis",
    title: "Synthesize related notes",
    instructions:
      "Search and read the relevant notes completely using ranged reads. Compare agreements, disagreements and gaps. Create a source-linked synthesis note in the permitted type. Cite actual notes and identify incomplete coverage.",
  },
  {
    id: "duplicates",
    title: "Review duplicate notes",
    instructions:
      "Search for duplicate or overlapping notes. Read each candidate. Prepare a merged note that preserves unique content and stable links. Propose patches to referring notes and archive redundant notes only after a concrete review. Verify every changed reference.",
  },
  {
    id: "weekly",
    title: "Review this week",
    instructions:
      "Review notes and their updated dates in scope. Summarize decisions, progress, outstanding questions and existing action items. Create a dated review with links to sources. Do not invent completion, dates or task owners.",
  },
] as const;

export async function loadNoteWorkflows(backend: VaultBackend) {
  const workflows: Array<{ id: string; title: string; instructions: string }> =
    [...BUILTIN_NOTE_WORKFLOWS];
  const paths = await backend.listFiles(".zerus/ai/workflows").catch(() => []);
  for (const path of paths
    .filter((value) => value.endsWith(".md"))
    .slice(0, 30)) {
    const instructions = (await backend.readText(path)).slice(0, 12_000);
    workflows.push({
      id: path,
      title:
        instructions.match(/^#\s+(.+)$/m)?.[1] ??
        path.split("/").at(-1)!.replace(/\.md$/, ""),
      instructions,
    });
  }
  return workflows;
}
