import { useState } from "react";
import type { NotesAgentUI } from "./useNotesAgent";
import type { AgentRun } from "@/lib/ai-harness-state";
import type { NotesAgentPort } from "@/lib/ai-harness";
import { noteUnifiedDiff } from "@/lib/ai-diff";
import { Button } from "@/components/ui/button";
const toolTitles: Record<string, string> = {
  note_get: "Read note",
  note_list: "List notes",
  search: "Search notes",
  note_append: "Append text",
  note_set_body: "Rewrite note",
  note_patch: "Edit passage",
  note_create: "Create note",
  note_properties: "Update properties",
  note_organize: "Organize note",
  note_links: "Inspect links",
  note_schema: "Inspect properties",
  update_plan: "Update plan",
  ask_user: "Ask a question",
  preview_changes: "Review changes",
  apply_changes: "Save approved changes",
  memory: "Read writing preferences",
  analyze_notes: "Compare notes independently",
  zerus_cli: "Read scoped notes",
};

export function NotesAgentControls({
  agent,
  busy,
}: {
  agent: NotesAgentUI;
  busy: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [memory, setMemory] = useState<string | null>(null);
  const [instructions, setInstructions] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  return (
    <div className="shrink-0 border-b border-border/60 px-3 py-2 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        <label className="flex items-center gap-1.5">
          Mode{" "}
          <select
            aria-label="Agent mode"
            value={agent.settings.mode}
            disabled={busy}
            onChange={(event) =>
              void agent.changeSettings({
                mode: event.target.value as typeof agent.settings.mode,
              })
            }
            className="rounded bg-muted px-2 py-1"
          >
            <option value="ask">Ask · read only</option>
            <option value="review">Review · approve changes</option>
            <option value="edit">Edit · save changes</option>
          </select>
        </label>
        <select
          aria-label="Agent edit scope"
          value={agent.settings.writeScope}
          disabled={busy || agent.settings.mode === "ask"}
          onChange={(event) =>
            void agent.changeSettings({
              writeScope: event.target
                .value as typeof agent.settings.writeScope,
            })
          }
          className="rounded bg-muted px-2 py-1"
        >
          <option value="context">Edit selected context</option>
          <option value="current">Edit current note only</option>
        </select>
        <select
          aria-label="Notes workflow"
          value={agent.settings.workflow}
          disabled={busy}
          onChange={(event) =>
            void agent.changeSettings({ workflow: event.target.value })
          }
          className="min-w-0 max-w-44 rounded bg-muted px-2 py-1"
        >
          <option value="">General notes task</option>
          {agent.workflows.map((workflow) => (
            <option key={workflow.id} value={workflow.id}>
              {workflow.title}
            </option>
          ))}
        </select>
        <button
          type="button"
          aria-expanded={open}
          onClick={() => {
            setOpen(!open);
            setSaved(false);
          }}
          className="ml-auto underline underline-offset-2"
        >
          Agent settings
        </button>
      </div>
      {open && (
        <div className="mt-3 max-h-72 space-y-3 overflow-y-auto pr-1">
          <p className="text-muted-foreground">
            The selected context controls reading. Limit edits to the current
            note while using other context as evidence, or allow changes
            throughout the context. With no current note, current-note editing
            allows no changes. Review is the default.
          </p>
          <div className="grid grid-cols-2 gap-2">
            {(
              [
                ["maxSteps", "Step limit", 2, 100],
                ["maxOutputTokens", "Output tokens / step", 1024, 32768],
                ["maxInputTokens", "Context token budget", 4096, 200000],
                ["maxMinutes", "Time limit (minutes)", 1, 30],
                ["maxTotalTokens", "Total token limit", 8000, 1000000],
              ] as const
            ).map(([key, label, min, max]) => (
              <label key={key} className="space-y-1">
                {label}
                <input
                  type="number"
                  min={min}
                  max={max}
                  disabled={busy}
                  aria-label={label}
                  value={agent.settings[key]}
                  onChange={(event) =>
                    void agent.changeSettings({
                      [key]: Number(event.target.value),
                    })
                  }
                  className="block w-full rounded border border-border bg-background px-2 py-1"
                />
              </label>
            ))}
          </div>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={agent.settings.textFallback}
              disabled={busy}
              onChange={(event) =>
                void agent.changeSettings({
                  textFallback: event.target.checked,
                })
              }
            />
            Text tool fallback for models without native tools
          </label>
          <label className="flex items-center gap-2">
            Reasoning effort{" "}
            <select
              aria-label="Reasoning effort"
              value={agent.settings.effort}
              disabled={busy}
              onChange={(event) =>
                void agent.changeSettings({
                  effort: event.target.value as typeof agent.settings.effort,
                })
              }
              className="rounded bg-muted px-2 py-1"
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </label>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={agent.settings.workers}
              disabled={busy}
              onChange={(event) =>
                void agent.changeSettings({ workers: event.target.checked })
              }
            />
            Allow independent read-only analysis (extra model calls)
          </label>
          <label className="block">
            Vault instructions
            <textarea
              aria-label="Vault instructions"
              rows={3}
              value={instructions ?? agent.guidance.instructions}
              onChange={(event) => {
                setInstructions(event.target.value);
                setSaved(false);
              }}
              className="mt-1 block w-full rounded border border-border bg-background p-2"
            />
          </label>
          <label className="block">
            Editable memory
            <textarea
              aria-label="Agent memory"
              rows={3}
              value={memory ?? agent.guidance.memory}
              onChange={(event) => {
                setMemory(event.target.value);
                setSaved(false);
              }}
              className="mt-1 block w-full rounded border border-border bg-background p-2"
            />
          </label>
          <Button
            size="sm"
            disabled={busy}
            onClick={() =>
              void Promise.all([
                agent.saveGuidance("memory", memory ?? agent.guidance.memory),
                agent.saveGuidance(
                  "instructions",
                  instructions ?? agent.guidance.instructions,
                ),
              ])
                .then(() => setSaved(true))
                .catch((error) => agent.setError(String(error)))
            }
          >
            {saved ? "Saved" : "Save instructions and memory"}
          </Button>
          <p className="text-muted-foreground">
            Custom workflows: add Markdown files to .zerus/ai/workflows. Memory
            and note content cannot grant edit permissions.
          </p>
        </div>
      )}
      {agent.error && (
        <p role="alert" className="mt-2 text-destructive">
          {agent.error}
        </p>
      )}
    </div>
  );
}
export function NotesAgentRunView({
  agent,
  busy,
  port,
  onResume,
  compact = false,
}: {
  agent: NotesAgentUI;
  busy: boolean;
  port: (run: AgentRun) => NotesAgentPort;
  onResume: (run: AgentRun, answer?: string) => void;
  compact?: boolean;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const [acting, setActing] = useState(false);
  const [answer, setAnswer] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const run = busy
    ? agent.runs[0]
    : (agent.runs.find((run) => run.id === selected) ?? agent.runs[0]);
  if (!run) return compact && agent.error ? <p role="alert" className="text-xs text-destructive">{agent.error}</p> : null;
  const pending = run.proposals.filter((item) => item.status === "pending");
  const proposals = compact
    ? run.proposals.filter((item) => item.status === "pending" || item.status === "conflict")
    : run.proposals;
  if (compact && !run.question && !proposals.length && !run.receipts.length &&
      (busy || run.status === "complete") && !agent.error) return null;
  const action = (work: () => Promise<unknown>) => {
    setActing(true);
    void Promise.resolve()
      .then(work)
      .catch((error) => agent.setError(String(error)))
      .finally(() => setActing(false));
  };
  return (
    <div
      className="mt-3 space-y-2 rounded-lg border border-border/70 bg-muted/20 p-3 text-xs"
      aria-label="Notes agent run"
    >
      <div className="flex items-center gap-2">
        <span className="font-semibold">
          {busy
            ? "Working"
            : run.question
              ? "Waiting for your answer"
              : run.status === "waiting"
                ? "Ready for review"
                : run.status === "complete"
                  ? "Finished"
                  : "Work remaining"}
        </span>
        {!compact && <span className="ml-auto text-muted-foreground">
          {run.usage.steps} steps ·{" "}
          {run.receipts.filter((item) => !item.undoneAt).length} saved
        </span>}
      </div>
      {!compact && agent.runs.length > 1 && (
        <select
          aria-label="Saved agent runs"
          value={run.id}
          onChange={(event) => setSelected(event.target.value)}
          className="w-full rounded bg-muted p-1"
        >
          {agent.runs.map((item) => (
            <option key={item.id} value={item.id}>
              {item.objective.slice(0, 70)}
            </option>
          ))}
        </select>
      )}
      {!compact && run.plan.length > 0 && (
        <ol className="space-y-1">
          {run.plan.map((step, index) => (
            <li
              key={index}
              className={
                step.status === "complete" ? "text-muted-foreground" : ""
              }
            >
              {step.status === "complete"
                ? "✓"
                : step.status === "running"
                  ? "◌"
                  : "○"}{" "}
              {step.text}
            </li>
          ))}
        </ol>
      )}
      {pending.length > 1 && (
        <Button
          size="sm"
          disabled={busy || acting}
          onClick={() =>
            action(() =>
              agent.interact(run, port(run), (runtime) =>
                runtime.approve(pending.map((item) => item.id)),
              ),
            )
          }
        >
          Approve {pending.length} changes
        </Button>
      )}
      {proposals.map((proposal) => (
        <div key={proposal.id} className="rounded border border-border/60 p-2">
          <div className="flex items-start gap-2">
            <button
              type="button"
              className="min-w-0 flex-1 text-left font-medium"
              aria-expanded={expanded === proposal.id}
              onClick={() =>
                setExpanded(expanded === proposal.id ? null : proposal.id)
              }
            >
              {proposal.call.name === "note_create"
                ? proposal.label
                : `${toolTitles[proposal.call.name] ?? "Update note"}: ${proposal.before[0]?.title ?? "Note"}`}
              <span className="ml-2 text-muted-foreground">
                {proposal.status}
              </span>
            </button>
          </div>
          {expanded === proposal.id && (
            <>
              <p className="mt-1 break-all text-muted-foreground">
                {proposal.before[0]?.path ?? "New note"}
                {proposal.afterPath &&
                proposal.afterPath !== proposal.before[0]?.path
                  ? ` → ${proposal.afterPath}`
                  : ""}
              </p>
              <pre className="my-2 max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-background p-2 text-[11px]">
                {noteUnifiedDiff(
                  proposal.before[0]?.content ?? "",
                  proposal.after,
                  proposal.before[0]?.path ?? proposal.label,
                )}
              </pre>
              {proposal.relatedAfter?.map((after) => (
                <pre
                  key={after.id}
                  className="my-2 max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-background p-2 text-[11px]"
                >
                  {noteUnifiedDiff(
                    proposal.before.find((note) => note.id === after.id)
                      ?.content ?? "",
                    after.content,
                    after.path,
                  )}
                </pre>
              ))}
              {!compact && <details>
                <summary className="cursor-pointer text-muted-foreground">
                  Operation details
                </summary>
                <pre className="max-h-32 overflow-auto whitespace-pre-wrap break-words text-[10px] text-muted-foreground">
                  {JSON.stringify(proposal.call.arguments, null, 2)}
                </pre>
              </details>}
            </>
          )}
          {proposal.status === "pending" && (
            <div className="mt-2 flex gap-2">
              <Button
                size="sm"
                disabled={busy || acting}
                onClick={() =>
                  action(() =>
                    agent.interact(run, port(run), (runtime) =>
                      runtime.approve([proposal.id]),
                    ),
                  )
                }
              >
                Approve & save
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={busy || acting}
                onClick={() =>
                  action(() =>
                    agent.interact(run, port(run), (runtime) =>
                      runtime.reject(proposal.id),
                    ),
                  )
                }
              >
                Reject
              </Button>
            </div>
          )}
          {proposal.status === "conflict" && (
            <p className="mt-1 text-destructive">
              The note changed. Prepare a new proposal before approving.
            </p>
          )}
        </div>
      ))}
      {run.receipts.map((receipt) => (
        <div key={receipt.id} className="flex items-center gap-2">
          <span className="min-w-0 flex-1">
            {receipt.undoneAt ? "Undone" : "Saved and verified"}:{" "}
            {receipt.after.map((note) => note.title).join(", ")}
          </span>
          <button
            type="button"
            disabled={busy || acting || Boolean(receipt.undoneAt)}
            className="underline disabled:opacity-40"
            onClick={() =>
              action(() =>
                agent.interact(run, port(run), (runtime) =>
                  runtime.undoChanges(receipt.proposalId),
                ),
              )
            }
          >
            Undo
            {run.receipts.filter(
              (item) => item.proposalId === receipt.proposalId,
            ).length > 1
              ? " change set"
              : ""}
          </button>
        </div>
      ))}
      {run.receipts.filter((receipt) => !receipt.undoneAt).length > 1 && (
        <Button
          variant="outline"
          size="sm"
          disabled={busy || acting}
          onClick={() =>
            action(() =>
              agent.interact(run, port(run), (runtime) =>
                runtime.undoChanges(),
              ),
            )
          }
        >
          Undo all run changes
        </Button>
      )}
      {run.question && (
        <div className="space-y-2">
          <p className="font-medium">{run.question.question}</p>
          <div className="flex flex-wrap gap-2">
            {run.question.options?.map((option) => (
              <Button
                key={option}
                variant="outline"
                size="sm"
                disabled={busy}
                onClick={() => onResume(run, option)}
              >
                {option}
              </Button>
            ))}
          </div>
          <input
            aria-label="Answer agent question"
            value={answer}
            onChange={(event) => setAnswer(event.target.value)}
            className="w-full rounded border border-border bg-background p-2"
          />
          <Button
            size="sm"
            disabled={busy || !answer.trim()}
            onClick={() => {
              onResume(run, answer);
              setAnswer("");
            }}
          >
            Answer & continue
          </Button>
        </div>
      )}
      {!busy &&
        !run.question &&
        ["interrupted", "partial", "waiting", "running"].includes(
          run.status,
        ) && (
          <Button
            variant="outline"
            size="sm"
            disabled={acting}
            onClick={() => onResume(run)}
          >
            Resume saved run
          </Button>
        )}
      {!compact && <details>
        <summary className="cursor-pointer text-muted-foreground">
          Activity & usage
        </summary>
        <div className="mt-2 max-h-64 space-y-1 overflow-y-auto">
          {run.events.map((event) => (
            <div key={event.id}>
              <span className="text-muted-foreground">
                {new Date(event.at).toLocaleTimeString()}{" "}
              </span>
              {event.kind === "tool"
                ? (toolTitles[event.text] ?? event.text)
                : event.text}
              {event.detail && (
                <details>
                  <summary className="cursor-pointer">Details</summary>
                  <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words text-[10px]">
                    {JSON.stringify(event.detail, null, 2)}
                  </pre>
                </details>
              )}
            </div>
          ))}
        </div>
        <p className="mt-2">
          Provider-reported tokens:{" "}
          {run.usage.inputTokens
            ? run.usage.inputTokens.toLocaleString()
            : "unavailable"}{" "}
          input ·{" "}
          {run.usage.outputTokens
            ? run.usage.outputTokens.toLocaleString()
            : "unavailable"}{" "}
          output · {Math.round(run.usage.elapsedMs / 1000)}s. Budget usage:{" "}
          {(run.usage.budgetTokens ?? 0).toLocaleString()} tokens, estimated
          where usage is unreported; includes compaction and workers.
        </p>
      </details>}
      {compact && agent.error && <p role="alert" className="text-destructive">{agent.error}</p>}
    </div>
  );
}
export function NotesAgentPending({ agent }: { agent: NotesAgentUI }) {
  return (
    <>
      {agent.pendingSteering.map((text, index) => (
        <p
          key={`s${index}`}
          className="mt-1 truncate text-xs text-muted-foreground"
        >
          Steering next step: {text}
        </p>
      ))}
      {agent.queued.map((text, index) => (
        <div
          key={`q${index}`}
          className="mt-1 flex gap-2 text-xs text-muted-foreground"
        >
          <span className="min-w-0 flex-1 truncate">Queued: {text}</span>
          <button
            type="button"
            onClick={() => agent.removeQueued(index)}
            aria-label="Remove queued message"
          >
            ×
          </button>
        </div>
      ))}
    </>
  );
}
