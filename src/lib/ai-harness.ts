import {
  getNoteProperties,
  noteBody,
  setContentProperty,
  withBody,
} from "./frontmatter";
import {
  createNoteResolver,
  isExternalNote,
  isManagedSavedLinkNote,
  isTrashed,
  noteTitle,
  noteReference,
  noteTypePath,
  typeKey,
  type Note,
} from "./note-utils";
import { chatContentRevision } from "./mobile-chat-history";
import {
  AI_MUTATION_TOOLS,
  validateAiToolCall,
  type AiToolCall,
} from "./ai-tool-schemas";
import {
  loadAgentGuidance,
  persistAgentRun,
  type AgentProposal,
  type AgentReceipt,
  type AgentRun,
  type AgentSettings,
  type AgentSnapshot,
} from "./ai-harness-state";
import { isReservedZerusProperty, setZerusState } from "./zerus-metadata";
import type { VaultBackend } from "./vault/backend";
import type { AiToolResult } from "./ai-tools";
import type { PropertySchemas } from "./properties";
import { effectivePropertyDefinitions } from "./properties";
import { stabilizeNoteLinks } from "./stable-note-links";
import { getFileHubReference } from "./file-hubs";
import { getOutgoingTitles } from "./links";

/** Production adapter shared by desktop and mobile; all mutations return durable evidence. */
export interface NotesAgentPort {
  backend: VaultBackend;
  scopeKey?: string;
  permitsRead?: (note: Note) => boolean;
  permitsWrite?: (note: Note) => boolean;
  permitsCreate?: (typePath: string[]) => boolean;
  notes(): Note[];
  hydrate(): Promise<void>;
  writable(): Promise<boolean>;
  schemas(): PropertySchemas;
  write(note: Note, content: string): Promise<Note>;
  create(id: string, typePath: string[], content: string): Promise<Note>;
  organize(
    note: Note,
    args: Extract<AiToolCall, { name: "note_organize" }>["arguments"],
    path: string,
  ): Promise<Note>;
  restore(snapshot: AgentSnapshot | null, current: Note): Promise<Note>;
  analyze?: (question: string, notes: AgentSnapshot[]) => Promise<string[]>;
}
export const snapshotNote = (note: Note): AgentSnapshot => ({
  id: note.id,
  title: noteTitle(note),
  path: note.path,
  content: note.content,
  revision: chatContentRevision(note.content),
  pinned: note.pinned,
  archived: Boolean(note.archived),
});
const summary = (note: Note) => ({
  id: note.id,
  title: noteTitle(note),
  path: note.path,
  revision: chatContentRevision(note.content),
  properties: getNoteProperties(note.content),
  updatedAt: note.updatedAt,
  archived: Boolean(note.archived),
});
const failure = (error: unknown): AiToolResult => ({
  ok: false,
  result: { error: error instanceof Error ? error.message : String(error) },
});
const now = () => new Date().toISOString();

export function createAgentRun(
  chatId: string,
  ownerId: string,
  objective: string,
  settings: AgentSettings,
  notes: Note[],
  createTypes: string[],
  writeTargetId?: string,
): AgentRun {
  const ids = notes.filter((note) => !isTrashed(note)).map((note) => note.id);
  return {
    version: 1,
    id: crypto.randomUUID(),
    chatId,
    ownerId,
    objective,
    mode: settings.mode,
    readIds: ids,
    writeIds:
      settings.mode === "ask"
        ? []
        : settings.writeScope === "current"
          ? ids.filter((id) => id === writeTargetId)
          : ids,
    createTypes: settings.writeScope === "current" ? [] : createTypes,
    status: "running",
    plan: [],
    proposals: [],
    receipts: [],
    events: [],
    messages: [],
    usage: { inputTokens: 0, outputTokens: 0, steps: 0, elapsedMs: 0 },
    updatedAt: now(),
  };
}

export class NotesAgentRuntime {
  private coverage = new Map<
    string,
    { revision: string; ranges: Array<[number, number]> }
  >();
  private serial: Promise<unknown> = Promise.resolve();
  constructor(
    readonly run: AgentRun,
    readonly port: NotesAgentPort,
    private changed?: (run: AgentRun) => void,
    private signal?: AbortSignal,
  ) {}
  async save() {
    await persistAgentRun(this.port.backend, this.run);
    this.changed?.({
      ...this.run,
      events: [...this.run.events],
      proposals: [...this.run.proposals],
      receipts: [...this.run.receipts],
    });
  }
  async event(
    kind: AgentRun["events"][number]["kind"],
    text: string,
    detail?: unknown,
  ) {
    this.run.events.push({
      id: crypto.randomUUID(),
      at: now(),
      kind,
      text,
      detail,
    });
    await this.save();
  }
  async initialize() {
    await this.port.hydrate();
    await this.event("started", this.run.objective);
  }
  private available() {
    const notes = new Map(this.port.notes().map((note) => [note.id, note]));
    return this.run.readIds.flatMap((id) => {
      const note = notes.get(id);
      return note &&
        !isTrashed(note) &&
        (!this.port.permitsRead || this.port.permitsRead(note))
        ? [note]
        : [];
    });
  }
  private resolve(selector?: string): Note {
    const value = selector?.trim() || "current";
    const candidate = value === "current" ? this.available()[0] : null;
    const matches = candidate
      ? [candidate]
      : this.available().filter(
          (note) =>
            note.id === value ||
            note.path.toLowerCase() === value.toLowerCase() ||
            noteTitle(note).toLowerCase() === value.toLowerCase(),
        );
    if (matches.length !== 1)
      throw new Error(
        matches.length
          ? "Ambiguous note. Use an exact ID from note_list."
          : "Note is outside the permitted context or unavailable. Use note_list or ask the user to expand context.",
      );
    return matches[0];
  }
  private async checkWrite(note?: Note) {
    this.signal?.throwIfAborted();
    if (this.run.mode === "ask")
      throw new Error(
        "Ask mode is read-only. Offer a draft or ask the user to choose Review/Edit.",
      );
    if (!(await this.port.writable()))
      throw new Error(
        "Chat ownership or vault changed. The operation was refused.",
      );
    if (
      note &&
      (!this.run.writeIds.includes(note.id) ||
        (this.port.permitsWrite && !this.port.permitsWrite(note)) ||
        isExternalNote(note) ||
        isManagedSavedLinkNote(note) ||
        isTrashed(note))
    )
      throw new Error("This note is outside the permitted edit context.");
  }
  private async verify(note: Note) {
    const disk = await this.port.backend.readText(note.path);
    if (disk !== note.content)
      throw new Error(
        "Saved content does not match the note. Resolve the conflict before continuing.",
      );
  }
  private read(call: Extract<AiToolCall, { name: "note_get" }>): AiToolResult {
    const note = this.resolve(call.arguments.selector);
    const body = noteBody(note.content);
    let start = Math.min(call.arguments.start ?? 0, body.length);
    let end = Math.min(body.length, start + (call.arguments.length ?? 16000));
    if (call.arguments.heading) {
      const headings = [...body.matchAll(/^#{1,6}\s+(.+)$/gm)];
      const index = headings.findIndex(
        (match) =>
          match[1].trim().toLowerCase() ===
          call.arguments.heading!.toLowerCase(),
      );
      if (index < 0)
        throw new Error(
          "Heading not found. Read the note to see its headings.",
        );
      start = headings[index].index!;
      end = Math.min(
        headings[index + 1]?.index ?? body.length,
        start + (call.arguments.length ?? 16000),
      );
    }
    const revision = chatContentRevision(note.content);
    const existing = this.coverage.get(note.id);
    const ranges =
      existing?.revision === revision
        ? [...existing.ranges, [start, end] as [number, number]]
        : [[start, end] as [number, number]];
    ranges.sort((a, b) => a[0] - b[0]);
    const merged: Array<[number, number]> = [];
    for (const range of ranges) {
      const last = merged.at(-1);
      if (last && range[0] <= last[1]) last[1] = Math.max(last[1], range[1]);
      else merged.push([...range]);
    }
    this.coverage.set(note.id, { revision, ranges: merged });
    return {
      ok: true,
      result: {
        ...summary(note),
        body: body.slice(start, end),
        totalLength: body.length,
        start,
        end,
        complete:
          merged.length === 1 &&
          merged[0][0] === 0 &&
          merged[0][1] === body.length,
        nextStart: end < body.length ? end : null,
        headings: [...body.matchAll(/^#{1,6}\s+(.+)$/gm)].map((match) => ({
          title: match[1],
          start: match.index,
        })),
      },
    };
  }
  private async propose(call: AiToolCall): Promise<AiToolResult> {
    const prior = this.run.proposals.find(
      (proposal) =>
        proposal.status !== "rejected" &&
        JSON.stringify(proposal.call) === JSON.stringify(call),
    );
    if (prior)
      return {
        ok: true,
        result: {
          proposalId: prior.id,
          status: prior.status,
          receipt: this.run.receipts.find(
            (receipt) => receipt.proposalId === prior.id,
          ),
        },
      };
    if (call.name === "note_create") {
      await this.checkWrite();
      const typePath =
        call.arguments.typePath ??
        (this.run.createTypes[0] === "*"
          ? ["inbox"]
          : this.run.createTypes[0]?.split("/"));
      if (
        !typePath?.length ||
        (this.port.permitsCreate && !this.port.permitsCreate(typePath)) ||
        !this.run.createTypes.some(
          (type) =>
            type === "*" ||
            typeKey(typePath) === type ||
            typeKey(typePath).startsWith(`${type}/`),
        )
      )
        throw new Error(
          "Choose a destination inside the permitted context. Note-only context cannot create notes; expand context first.",
        );
      const body = `# ${call.arguments.title.replace(/[\r\n]/g, " ")}\n\n${call.arguments.body}`;
      const id = crypto.randomUUID();
      const after = setZerusState(body, { id });
      return this.stage({
        id: crypto.randomUUID(),
        targetId: id,
        call: { ...call, arguments: { ...call.arguments, typePath } },
        before: [],
        after,
        label: `Create ${call.arguments.title} in ${typeKey(typePath)}`,
        status: "pending",
      });
    }
    const note = this.resolve(
      "selector" in call.arguments ? call.arguments.selector : undefined,
    );
    await this.checkWrite(note);
    const revision =
      "revision" in call.arguments ? call.arguments.revision : undefined;
    const read = this.coverage.get(note.id);
    if ((revision ?? read?.revision) !== chatContentRevision(note.content))
      throw new Error(
        "Revision conflict or note not read. Read the current note and retry using its revision.",
      );
    await this.verify(note);
    let after = note.content;
    let afterPath = note.path;
    const relatedAfter = new Map<string, AgentSnapshot>();
    const relatedBefore = new Map<string, AgentSnapshot>();
    if (call.name === "note_append")
      after = withBody(
        note.content,
        `${noteBody(note.content).trimEnd()}\n\n${call.arguments.text}`,
      );
    if (call.name === "note_set_body") {
      const body = noteBody(note.content);
      if (
        !read ||
        read.revision !== chatContentRevision(note.content) ||
        read.ranges.length !== 1 ||
        read.ranges[0][0] !== 0 ||
        read.ranges[0][1] !== body.length
      )
        throw new Error(
          "Whole-body replacement requires a complete read at the current revision. Read remaining ranges or use note_patch.",
        );
      after = withBody(note.content, call.arguments.body);
    }
    if (call.name === "note_patch") {
      const body = noteBody(note.content);
      const at = body.indexOf(call.arguments.oldText);
      if (at < 0 || body.indexOf(call.arguments.oldText, at + 1) >= 0)
        throw new Error(
          "The patch passage must match exactly once. Read the relevant range and include more context.",
        );
      after = withBody(
        note.content,
        body.slice(0, at) +
          call.arguments.newText +
          body.slice(at + call.arguments.oldText.length),
      );
    }
    if (call.name === "note_properties") {
      const defs = effectivePropertyDefinitions(
        noteTypePath(note),
        this.port.schemas(),
      ).map(({ def }) => def);
      for (const [name, value] of Object.entries(call.arguments.values)) {
        if (isReservedZerusProperty(name))
          throw new Error(
            "Reserved Zerus properties cannot be edited by the agent.",
          );
        const def = defs.find(
          (def) => def.name.toLowerCase() === name.toLowerCase(),
        );
        if (def?.type === "relation") {
          const resolve = createNoteResolver(this.port.notes());
          const properties = getNoteProperties(after);
          const key =
            Object.keys(properties).find(
              (key) => key.toLowerCase() === name.toLowerCase(),
            ) ?? name;
          const references = (value: unknown) =>
            value == null || value === ""
              ? []
              : Array.isArray(value)
                ? value
                : [value];
          const beforeTargets = references(properties[key]).map((reference) =>
            resolve(String(reference)),
          );
          const targets = references(value).map((reference) =>
            resolve(String(reference)),
          );
          if (targets.some((target) => !target))
            throw new Error(
              "A relation target is unresolved. Use stable note IDs.",
            );
          if (!def.relationMultiple && targets.length > 1)
            throw new Error("This relation allows one target.");
          if (!def.relationPairId)
            throw new Error(
              "Configure the reciprocal relation in the property editor before agent editing.",
            );
          for (const target of [...beforeTargets, ...targets]) {
            if (!target) continue;
            await this.checkWrite(target);
            await this.verify(target);
            const reverseDefinitions = effectivePropertyDefinitions(
              noteTypePath(target),
              this.port.schemas(),
            )
              .filter(
                ({ def: reverse }) =>
                  reverse.type === "relation" &&
                  reverse.relationPairId === def.relationPairId,
              )
              .map(({ def }) => def);
            const reverse =
              reverseDefinitions.find((reverse) => reverse.name !== def.name) ??
              reverseDefinitions[0];
            if (!reverse)
              throw new Error(
                "A reciprocal property definition is missing. Configure it in the property editor first.",
              );
            if (
              def.relationTypeKey &&
              typeKey(noteTypePath(target)) !== def.relationTypeKey &&
              !typeKey(noteTypePath(target)).startsWith(
                `${def.relationTypeKey}/`,
              )
            )
              throw new Error("Relation target has the wrong type.");
            if (target.id !== note.id && !relatedBefore.has(target.id))
              relatedBefore.set(target.id, snapshotNote(target));
            const existing =
              target.id === note.id
                ? after
                : (relatedAfter.get(target.id)?.content ?? target.content);
            const oldValues = references(
              getNoteProperties(existing)[reverse.name],
            )
              .map(String)
              .filter((reference) => resolve(reference)?.id !== note.id);
            const adding = targets.some((item) => item?.id === target.id);
            if (adding && !reverse.relationMultiple && oldValues.length)
              throw new Error(
                "The reciprocal single relation is already occupied.",
              );
            const nextValues = adding
              ? [...oldValues, noteReference(note)]
              : oldValues;
            const content = setContentProperty(
              existing,
              reverse.name,
              nextValues.length
                ? reverse.relationMultiple
                  ? nextValues
                  : nextValues[0]
                : null,
            );
            if (target.id === note.id) after = content;
            else
              relatedAfter.set(target.id, {
                ...snapshotNote(target),
                content,
                revision: chatContentRevision(content),
              });
          }
          const stable = targets.map((target) => noteReference(target!));
          after = setContentProperty(
            after,
            name,
            stable.length ? (def.relationMultiple ? stable : stable[0]) : null,
          );
          continue;
        }
        if (
          value !== null &&
          def &&
          ((def.type === "number" && typeof value !== "number") ||
            (def.type === "checkbox" && typeof value !== "boolean") ||
            (["text", "date", "url"].includes(def.type) &&
              typeof value !== "string"))
        )
          throw new Error(`Invalid value for ${name} (${def.type}).`);
        after = setContentProperty(after, name, value);
      }
    }
    if (call.name === "note_organize") {
      if (
        (call.arguments.typePath || call.arguments.trash) &&
        getFileHubReference(note)?.managed
      )
        throw new Error(
          "Move managed file notes through the file editor so their attached assets can be reviewed together.",
        );
      if (
        call.arguments.typePath &&
        ((this.port.permitsCreate &&
          !this.port.permitsCreate(call.arguments.typePath)) ||
          !this.run.createTypes.some(
            (type) =>
              type === "*" ||
              typeKey(call.arguments.typePath!) === type ||
              typeKey(call.arguments.typePath!).startsWith(`${type}/`),
          ))
      )
        throw new Error("Destination outside the permitted edit context.");
      if (call.arguments.typePath) {
        const destination = effectivePropertyDefinitions(
          call.arguments.typePath,
          this.port.schemas(),
        ).map(({ def }) => def);
        const relations = effectivePropertyDefinitions(
          noteTypePath(note),
          this.port.schemas(),
        )
          .map(({ def }) => def)
          .filter(
            (def) =>
              def.type === "relation" &&
              getNoteProperties(note.content)[def.name] != null,
          );
        if (
          relations.some(
            (def) =>
              !destination.some(
                (other) =>
                  other.type === "relation" &&
                  other.name === def.name &&
                  other.relationPairId === def.relationPairId &&
                  other.relationTypeKey === def.relationTypeKey &&
                  other.relationMultiple === def.relationMultiple,
              ),
          )
        )
          throw new Error(
            "The destination lacks a compatible relation schema. Configure its properties before moving this note.",
          );
      }
      if (call.arguments.typePath || call.arguments.trash) {
        const dir = call.arguments.typePath
          ? typeKey(call.arguments.typePath)
          : typeKey(noteTypePath(note));
        const stem = note.path.split("/").at(-1)!;
        afterPath = `${call.arguments.trash ? ".trash/" : ""}${dir}/${stem}`;
        if (
          afterPath !== note.path &&
          (await this.port.backend.exists(afterPath))
        )
          throw new Error(
            "A note already exists at the destination. Choose another folder.",
          );
      }
      after = setZerusState(after, {
        ...(call.arguments.pinned === undefined
          ? {}
          : { pinned: call.arguments.pinned }),
        ...(call.arguments.archived === undefined
          ? {}
          : { archived: call.arguments.archived }),
      });
    }
    if (noteTitle({ ...note, content: after }) !== noteTitle(note)) {
      const resolve = createNoteResolver(this.port.notes());
      for (const candidate of this.port
        .notes()
        .filter((item) => !isTrashed(item))) {
        const source =
          candidate.id === note.id
            ? { ...note, content: after }
            : {
                ...candidate,
                content:
                  relatedAfter.get(candidate.id)?.content ?? candidate.content,
              };
        const content = stabilizeNoteLinks(
          source,
          this.port.notes(),
          this.port.schemas(),
          (reference) =>
            resolve(reference)?.id === note.id ? note : undefined,
        );
        if (content === source.content) continue;
        await this.checkWrite(candidate);
        await this.verify(candidate);
        if (candidate.id === note.id) after = content;
        else {
          relatedBefore.set(candidate.id, snapshotNote(candidate));
          relatedAfter.set(candidate.id, {
            ...snapshotNote(candidate),
            content,
            revision: chatContentRevision(content),
          });
        }
      }
    }
    const duplicate = this.run.proposals.find(
      (proposal) =>
        proposal.status !== "rejected" &&
        proposal.before[0]?.content === note.content &&
        JSON.stringify(proposal.call) === JSON.stringify(call),
    );
    if (duplicate)
      return {
        ok: true,
        result: {
          proposalId: duplicate.id,
          status: duplicate.status,
          receipt: this.run.receipts.find(
            (receipt) => receipt.proposalId === duplicate.id,
          ),
        },
      };
    return this.stage({
      id: crypto.randomUUID(),
      call,
      before: [snapshotNote(note), ...relatedBefore.values()],
      after,
      afterPath,
      relatedAfter: [...relatedAfter.values()],
      label: `${call.name}: ${noteTitle(note)}`,
      status: "pending",
    });
  }
  private async stage(proposal: AgentProposal): Promise<AiToolResult> {
    this.run.proposals.push(proposal);
    await this.event("approval", proposal.label, { proposalId: proposal.id });
    // Destructive and multi-note changes always remain concrete proposals.
    const destructive =
      proposal.call.name === "note_organize" && proposal.call.arguments.trash;
    if (
      this.run.mode === "edit" &&
      !destructive &&
      proposal.before.length <= 1
    ) {
      proposal.status = "approved";
      return this.commit(proposal);
    }
    this.run.status = "waiting";
    await this.save();
    return {
      ok: true,
      result: {
        status: "pending_review",
        proposalId: proposal.id,
        label: proposal.label,
        before: proposal.before,
        after: proposal.after,
        instruction:
          "The change is staged, not saved. Tell the user to review the proposal. You may stage additional changes.",
      },
    };
  }
  private async commit(proposal: AgentProposal): Promise<AiToolResult> {
    const prior = this.run.receipts.filter(
      (item) => item.proposalId === proposal.id,
    );
    if (prior.some((receipt) => receipt.undoneAt))
      throw new Error(
        "An operation from this change set was undone. Prepare a new proposal before applying it again.",
      );
    if (proposal.status === "applied")
      return { ok: true, result: { status: "saved", receipts: prior } };
    if (!["approved", "applying"].includes(proposal.status))
      throw new Error("This exact proposal has not been approved.");
    await this.checkWrite();
    if (proposal.call.name === "note_create") {
      const typePath = proposal.call.arguments.typePath;
      if (
        !typePath ||
        (this.port.permitsCreate && !this.port.permitsCreate(typePath)) ||
        !this.run.createTypes.some(
          (type) =>
            type === "*" ||
            type === typeKey(typePath) ||
            typeKey(typePath).startsWith(`${type}/`),
        )
      )
        throw new Error(
          "Creation destination outside the current edit context.",
        );
      let note = this.port
        .notes()
        .find((item) => item.id === proposal.targetId);
      if (!note) {
        proposal.status = "applying";
        await this.save();
        note = await this.port.create(
          proposal.targetId!,
          proposal.call.arguments.typePath!,
          proposal.after,
        );
      }
      if (
        typeKey(noteTypePath(note)) !== typeKey(typePath) ||
        isTrashed(note) ||
        (this.port.permitsWrite && !this.port.permitsWrite(note))
      )
        throw new Error("Created note moved outside its approved destination.");
      if (note.content !== proposal.after)
        throw new Error("Created note differs from approved content.");
      await this.verify(note);
      if (!this.run.readIds.includes(note.id)) this.run.readIds.push(note.id);
      if (!this.run.writeIds.includes(note.id)) this.run.writeIds.push(note.id);
      if (!prior.length) {
        this.run.receipts.push({
          id: crypto.randomUUID(),
          operationKey: proposal.id,
          proposalId: proposal.id,
          before: [],
          after: [snapshotNote(note)],
          at: now(),
        });
      }
    } else {
      const planned = proposal.before.map((before, index) =>
        index === 0
          ? {
              ...before,
              content: proposal.after,
              path: proposal.afterPath ?? before.path,
            }
          : proposal.relatedAfter!.find((item) => item.id === before.id)!,
      );
      // Validate the entire reviewed set before the first write, including recovered partial commits.
      for (const [index, before] of proposal.before.entries()) {
        const note = this.port.notes().find((item) => item.id === before.id);
        const after = planned[index];
        if (
          !note ||
          !this.run.writeIds.includes(note.id) ||
          (this.port.permitsWrite &&
            (!this.port.permitsWrite(note) ||
              !this.port.permitsWrite({ ...note, path: after.path })))
        )
          throw new Error("Target outside edit context.");
        const unchanged =
          note.content === before.content && note.path === before.path;
        const recovered =
          proposal.status === "applying" &&
          note.content === after.content &&
          note.path === after.path;
        if (!unchanged && !recovered) {
          proposal.status = "conflict";
          await this.save();
          throw new Error(
            "A reviewed note changed. Prepare a new proposal. Any earlier saved changes remain in the journal.",
          );
        }
        if (unchanged) await this.checkWrite(note);
        await this.verify(note);
      }
      proposal.status = "applying";
      await this.save();
      for (const [index, before] of proposal.before.entries()) {
        await this.checkWrite();
        const after = planned[index];
        let note = this.port.notes().find((item) => item.id === before.id)!;
        const key = `${proposal.id}:${before.id}`;
        if (this.run.receipts.some((item) => item.operationKey === key))
          continue;
        if (note.content !== after.content || note.path !== after.path) {
          note =
            index === 0 && proposal.call.name === "note_organize"
              ? await this.port.organize(
                  note,
                  proposal.call.arguments,
                  after.path,
                )
              : await this.port.write(note, after.content);
        }
        if (note.content !== after.content || note.path !== after.path)
          throw new Error("Note was not saved exactly as approved.");
        await this.verify(note);
        const receipt: AgentReceipt = {
          id: crypto.randomUUID(),
          operationKey: key,
          proposalId: proposal.id,
          before: [before],
          after: [snapshotNote(note)],
          at: now(),
        };
        this.run.receipts.push(receipt);
        await this.event("committed", `Saved ${noteTitle(note)}`, receipt);
      }
    }
    proposal.status = "applied";
    await this.save();
    return {
      ok: true,
      result: {
        status: "saved",
        receipts: this.run.receipts.filter(
          (item) => item.proposalId === proposal.id,
        ),
      },
    };
  }
  execute(raw: AiToolCall): Promise<AiToolResult> {
    const work = this.serial.then(async () => {
      try {
        this.signal?.throwIfAborted();
        const call = validateAiToolCall(raw.name, raw.arguments);
        if (this.run.question)
          throw new Error(
            "Waiting for the human answer. Resume after answering the question.",
          );
        const result = await this.dispatch(call);
        await this.event("tool", call.name, { call, result });
        return result;
      } catch (error) {
        const result = failure(error);
        await this.event(
          "error",
          `${raw.name}: ${(result.result as { error: string }).error}`,
          { call: raw, result },
        );
        return result;
      }
    });
    this.serial = work.catch(() => {});
    return work;
  }
  private async dispatch(call: AiToolCall): Promise<AiToolResult> {
    if (call.name === "note_get") return this.read(call);
    if (call.name === "note_list" || call.name === "search") {
      const args = call.arguments;
      const query =
        call.name === "search"
          ? call.arguments.query
              .toLocaleLowerCase()
              .split(/\s+/)
              .filter(Boolean)
          : [];
      const results = this.available()
        .filter(
          (note) =>
            (!args.typePath ||
              typeKey(noteTypePath(note)) === args.typePath ||
              typeKey(noteTypePath(note)).startsWith(`${args.typePath}/`)) &&
            (call.name !== "note_list" ||
              call.arguments.includeArchived !== false ||
              !note.archived),
        )
        .map((note) => {
          const body = noteBody(note.content);
          const title = noteTitle(note).toLowerCase();
          const haystack =
            `${title}\n${note.path}\n${note.content}`.toLowerCase();
          const score = query.reduce(
            (sum, term) =>
              sum +
              (title.includes(term) ? 10 : 0) +
              (haystack.includes(term) ? 1 : 0),
            0,
          );
          const match =
            query
              .map((term) => body.toLowerCase().indexOf(term))
              .find((index) => index >= 0) ?? 0;
          return {
            ...summary(note),
            score,
            excerpt: body.slice(
              Math.max(0, match - 180),
              Math.max(0, match - 180) + 800,
            ),
            excerptStart: Math.max(0, match - 180),
          };
        })
        .filter(
          (item) =>
            (!query.length || item.score > 0) &&
            (call.name !== "search" ||
              !call.arguments.property ||
              (call.arguments.value === undefined
                ? call.arguments.property in item.properties
                : JSON.stringify(item.properties[call.arguments.property]) ===
                  JSON.stringify(call.arguments.value))),
        )
        .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
      const offset = args.offset ?? 0;
      const limit = args.limit ?? 20;
      return {
        ok: true,
        result: {
          matches: results.slice(offset, offset + limit),
          total: results.length,
          nextOffset: offset + limit < results.length ? offset + limit : null,
        },
      };
    }
    if (call.name === "note_schema") {
      const types = [
        ...new Set([
          ...this.available().map((note) => typeKey(noteTypePath(note))),
          ...this.run.createTypes.filter((type) => type !== "*"),
          ...Object.keys(this.port.schemas()).filter(
            (type) =>
              this.run.createTypes.some(
                (allowed) =>
                  allowed === "*" ||
                  type === allowed ||
                  type.startsWith(`${allowed}/`),
              ) &&
              (!this.port.permitsCreate ||
                this.port.permitsCreate(type.split("/"))),
          ),
        ]),
      ];
      return {
        ok: true,
        result: {
          types,
          createTypes: this.run.createTypes,
          schemas: Object.fromEntries(
            types
              .filter(
                (type) =>
                  !call.arguments.typePath || type === call.arguments.typePath,
              )
              .map((type) => [
                type,
                effectivePropertyDefinitions(
                  type.split("/"),
                  this.port.schemas(),
                ).map(({ def }) => def),
              ]),
          ),
        },
      };
    }
    if (call.name === "note_links") {
      const note = this.resolve(call.arguments.selector);
      const available = this.available();
      const resolve = createNoteResolver(available);
      const schemas = this.port.schemas();
      return {
        ok: true,
        result: {
          scope: "permitted_read_context",
          outgoing: getOutgoingTitles(note, schemas).map((link) => {
            const target = resolve(link);
            return target
              ? summary(target)
              : { reference: link, unresolved: true };
          }),
          backlinks: available
            .filter(
              (candidate) =>
                candidate.id !== note.id &&
                getOutgoingTitles(candidate, schemas).some(
                  (link) => resolve(link)?.id === note.id,
                ),
            )
            .map(summary),
        },
      };
    }
    if (call.name === "update_plan") {
      this.run.plan = call.arguments.steps.map((step) => ({
        text: step.text,
        status: step.status,
      }));
      await this.save();
      return { ok: true, result: this.run.plan };
    }
    if (call.name === "ask_user") {
      this.run.question = {
        question: call.arguments.question,
        options: call.arguments.options,
      };
      this.run.status = "waiting";
      await this.event("question", call.arguments.question);
      return { ok: true, result: { waitingForUser: true } };
    }
    if (call.name === "preview_changes")
      return {
        ok: true,
        result: this.run.proposals.filter(
          (item) => item.status === "pending" || item.status === "conflict",
        ),
      };
    if (call.name === "apply_changes") {
      const proposals = this.run.proposals
        .filter(
          (item) => item.status === "approved" || item.status === "applying",
        )
        .filter(
          (item) =>
            !call.arguments.proposalIds ||
            call.arguments.proposalIds.includes(item.id),
        );
      if (!proposals.length)
        return {
          ok: false,
          result: {
            approvalRequired: true,
            error:
              "Use the proposal review controls to approve these exact changes.",
          },
        };
      const results = [];
      for (const proposal of proposals)
        results.push(await this.commit(proposal));
      return { ok: results.every((result) => result.ok), result: results };
    }
    if (call.name === "memory") {
      const { memory } = await loadAgentGuidance(this.port.backend);
      if (call.arguments.operation === "read")
        return { ok: true, result: { memory, trusted: false } };
      // The model can suggest memory; only the human-controlled settings editor persists it.
      return {
        ok: false,
        result: {
          suggestedMemory: call.arguments.text,
          error:
            "Save or forget this preference using the visible Memory editor.",
        },
      };
    }
    if (call.name === "analyze_notes") {
      if (!this.port.analyze)
        throw new Error(
          "Enable independent analysis workers in agent settings first.",
        );
      const notes = call.arguments.selectors.map((selector) =>
        snapshotNote(this.resolve(selector)),
      );
      return {
        ok: true,
        result: {
          analyses: await this.port.analyze(call.arguments.question, notes),
          trusted: false,
          readOnly: true,
        },
      };
    }
    if (call.name === "zerus_cli") {
      // Never hand an unconstrained process the active vault. Map legacy reads through scoped tools.
      const [command, subcommand, ...rest] = call.arguments.args;
      if (
        call.arguments.args.some(
          (arg) => arg.startsWith("--vault") || arg === "--yes",
        )
      )
        throw new Error(
          "Vault overrides and mutation approvals are unavailable in the notes harness.",
        );
      if (command === "note" && subcommand === "list")
        return this.dispatch({ name: "note_list", arguments: {} });
      if (command === "note" && subcommand === "get")
        return this.dispatch({
          name: "note_get",
          arguments: { selector: rest[0] },
        });
      if (command === "search" && subcommand)
        return this.dispatch({
          name: "search",
          arguments: { query: subcommand },
        });
      if (
        (command === "type" && subcommand === "list") ||
        (command === "schema" && subcommand === "list")
      )
        return this.dispatch({ name: "note_schema", arguments: {} });
      return {
        ok: false,
        result: {
          error:
            "Use the dedicated scoped note tools. Advanced CLI execution cannot bypass the note context.",
          available: [
            "note_get",
            "note_list",
            "search",
            "note_schema",
            "note_links",
          ],
        },
      };
    }
    if (AI_MUTATION_TOOLS.has(call.name)) return this.propose(call);
    throw new Error("Unsupported tool");
  }
  async approve(ids: string[]) {
    await this.port.hydrate();
    await this.checkWrite();
    const proposals = ids.map((id) =>
      this.run.proposals.find(
        (item) => item.id === id && item.status === "pending",
      ),
    );
    if (proposals.some((item) => !item))
      throw new Error("Approval targets are no longer pending.");
    for (const proposal of proposals) {
      for (const before of proposal!.before) {
        const note = this.port.notes().find((item) => item.id === before.id);
        if (
          !note ||
          note.content !== before.content ||
          note.path !== before.path
        )
          throw new Error(
            "A proposal changed since it was prepared. Refresh it before approving.",
          );
        await this.checkWrite(note);
        await this.verify(note);
      }
    }
    for (const proposal of proposals) proposal!.status = "approved";
    await this.event("approval", `Approved ${ids.length} exact change(s)`, {
      ids,
    });
    const result = await this.execute({
      name: "apply_changes",
      arguments: { proposalIds: ids },
    });
    if (result.ok) {
      this.run.status =
        this.run.question ||
        this.run.proposals.some((item) =>
          ["pending", "approved", "applying", "conflict"].includes(item.status),
        )
          ? "waiting"
          : this.run.plan.some((item) => item.status !== "complete")
            ? "partial"
            : "complete";
      await this.save();
    }
    return result;
  }
  async reject(id: string) {
    const proposal = this.run.proposals.find((item) => item.id === id);
    if (!proposal || !["pending", "conflict"].includes(proposal.status))
      throw new Error("Proposal cannot be rejected.");
    proposal.status = "rejected";
    await this.save();
  }
  async undo(receiptId: string) {
    await this.port.hydrate();
    const receipt = this.run.receipts.find((item) => item.id === receiptId);
    if (!receipt || receipt.undoneAt)
      throw new Error("This change has already been undone or is unavailable.");
    await this.checkWrite();
    for (const after of receipt.after) {
      const note = this.port.notes().find((item) => item.id === after.id);
      if (!note || note.path !== after.path || note.content !== after.content)
        throw new Error(
          "The note changed after this operation. Undo would overwrite newer work.",
        );
      if (
        !this.run.writeIds.includes(note.id) ||
        (this.port.permitsWrite && !this.port.permitsWrite(note))
      )
        throw new Error("Undo target outside edit context.");
      await this.verify(note);
    }
    for (const after of receipt.after) {
      const note = this.port.notes().find((item) => item.id === after.id)!;
      const before = receipt.before.find((item) => item.id === note.id) ?? null;
      if (
        before &&
        this.port.permitsWrite &&
        !this.port.permitsWrite({ ...note, path: before.path })
      )
        throw new Error(
          "The original destination is outside the current edit context.",
        );
      await this.port.restore(before, note);
    }
    receipt.undoneAt = now();
    await this.event("committed", "Undid verified change", { receiptId });
  }
  async undoChanges(proposalId?: string) {
    const receipts = this.run.receipts.filter(
      (receipt) =>
        !receipt.undoneAt && (!proposalId || receipt.proposalId === proposalId),
    );
    const latest = new Map<string, AgentSnapshot>();
    for (const receipt of receipts)
      for (const after of receipt.after) latest.set(after.id, after);
    await this.port.hydrate();
    await this.checkWrite();
    for (const after of latest.values()) {
      const note = this.port.notes().find((item) => item.id === after.id);
      if (!note || note.content !== after.content || note.path !== after.path)
        throw new Error(
          "A note changed after these operations. Undo would overwrite newer work.",
        );
      if (this.port.permitsWrite && !this.port.permitsWrite(note))
        throw new Error("Undo target outside edit context.");
      await this.verify(note);
    }
    for (const receipt of receipts.slice().reverse())
      await this.undo(receipt.id);
  }
}
