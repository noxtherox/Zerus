import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { createAgentRun, NotesAgentRuntime } from "@/lib/ai-harness";
import { DEFAULT_AGENT_SETTINGS } from "@/lib/ai-harness-state";
import { disposableNotesVault } from "@/lib/ai-harness-fixture";
import { NotesAgentRunView } from "./NotesAgentControls";
import type { NotesAgentUI } from "./useNotesAgent";

describe("simple chat run controls", () => {
  it("keeps approvals, undo, and questions accessible while hiding activity details", async () => {
    const vault = await disposableNotesVault(["# Meeting\n\nDecision: ship Friday."]);
    const run = createAgentRun(
      "simple-chat", "device", "Update the meeting notes",
      { ...DEFAULT_AGENT_SETTINGS, mode: "review" }, vault.port.notes(), ["inbox"],
    );
    const runtime = new NotesAgentRuntime(run, vault.port);
    await runtime.initialize();
    await runtime.execute({ name: "note_get", arguments: {} });
    await runtime.execute({ name: "note_append", arguments: { text: "Owner: Ana." } });
    const render = () => renderToStaticMarkup(
      <NotesAgentRunView
        compact
        agent={{ runs: [run], error: "" } as NotesAgentUI}
        busy={false}
        port={() => vault.port}
        onResume={() => undefined}
      />,
    );

    const review = render();
    expect(review).toContain("Approve &amp; save");
    expect(review).toContain("Reject");
    expect(review).not.toContain("Activity &amp; usage");

    await runtime.approve([run.proposals[0].id]);
    expect(render()).toContain("Undo");

    await runtime.execute({ name: "ask_user", arguments: { question: "Which deadline should I use?", options: ["Friday", "Monday"] } });
    const question = render();
    expect(question).toContain("Which deadline should I use?");
    expect(question).toContain("Answer &amp; continue");
    expect(question).not.toContain("Activity &amp; usage");
  });
});
