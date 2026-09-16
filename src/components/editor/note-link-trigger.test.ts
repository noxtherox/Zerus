import { describe, expect, it } from "vitest";
import { matchNoteLinkTrigger } from "./note-link-trigger";

describe("note link shortcuts", () => {
  it.each(["@", "[["])("opens with %s before any query", trigger => {
    expect(matchNoteLinkTrigger(trigger)).toEqual({ leadOffset: 0, matchingString: "", replaceableString: trigger });
  });
  it.each(["@", "[["])("replaces only %s and the query", trigger => {
    expect(matchNoteLinkTrigger(`See ${trigger}Project Alpha`)).toEqual({ leadOffset: 4, matchingString: "Project Alpha", replaceableString: `${trigger}Project Alpha` });
  });
  it.each(["person@example.com", "[[Done]]", "@@", "[[[", "@line\nbreak", "plain text"])("ignores %s", text => {
    expect(matchNoteLinkTrigger(text)).toBeNull();
  });
  it("supports brackets next to prose and punctuation in note titles", () => {
    expect(matchNoteLinkTrigger("See[[Projects/Alpha: Q3" )?.matchingString).toBe("Projects/Alpha: Q3");
  });
});
