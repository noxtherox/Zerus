import Foundation

// Prompts and JSON schemas for the local pipelines. These are the phase 1
// winners; the eval runner (`evals/local-ai/runner`) uses them directly, so
// change them only together with an eval run.

public enum LocalAIPrompts {
    public static let route = """
        You classify a request made to a notes app. Choose exactly one intent:
        - ask: a question or search about information in the user's notes.
        - summarize: the user wants a summary of a note or of text.
        - edit: the user wants to change, add to, append, tag, rename, mark done, or create a note.
        The request may be in any language.
        """

    public static let ask = """
        You answer questions using only the notes provided. Each note is wrapped in <note id="..."> tags.
        Steps:
        1. "evidence": copy, word for word, up to three short passages from the notes that answer the question. Read every note carefully before deciding nothing is relevant.
        2. "answer": answer in one to three sentences using only that evidence, in the language requested.
        3. "found": true if the evidence answers the question, false if the notes do not contain the answer (then evidence is empty and the answer says the notes don't say).
        4. "sources": the ids of the notes the evidence came from.
        """

    public static func summarize(language: String, maxWords: Int) -> String {
        """
        You summarize a note for its author. Use only facts stated in the note; never add details.
        Keep names, dates, numbers and decisions exact. Write at most \(maxWords) words, in \(LocalAILanguage.name(language)).
        Write one plain paragraph with no headings or lists. Output only the summary.
        """
    }

    public static let rewrite = """
        You rewrite a selected passage from a note according to the user's instruction.
        Keep every fact, name, number and link unless the instruction says otherwise.
        Return in "text" only the rewritten selection — never the rest of the note. Keep Markdown formatting.
        """

    public static let append = """
        You write new text to append to the end of a note, following the user's instruction.
        Use only facts from the note. Return only the new text in "text", as Markdown.
        Write in the language of the note unless the instruction asks otherwise.
        """

    public static let findReplace = """
        You edit a note precisely, following the user's instruction.
        Return a list of edits. Each edit has:
        - "find": an exact excerpt copied character for character from the note (including Markdown such as "- [ ]" or "**"). It must occur only once in the note, so include enough of the line to be unique.
        - "replace": the new text that takes its place. To add a new line, find the line before it and replace it with that same line, a newline, and the new line.
        Examples: tick a checkbox: find "- [ ] Book tickets" replace "- [x] Book tickets". Change a date: find "Deadline: 3 May" replace "Deadline: 9 May".
        Change only what the instruction asks for.
        """

    public static let create = """
        You create a new note from the user's instruction. Return a short "title" and a Markdown "body".
        Write in the language the instruction asks for, otherwise in the language of the instruction.
        Use facts from the reference note when one is given; never invent personal facts.
        """

    public static let properties = """
        You change a note's properties (YAML frontmatter). Current properties are shown as JSON.
        Return a list of operations:
        - {"op": "set", "key": name, "value": [values]}: add or overwrite a property. "value" is always a list; use one item for a single value. For tags, give the complete new list.
        - {"op": "remove", "key": name, "value": []}: delete a property.
        Only include properties the instruction asks to change.
        """
}

public enum LocalAISchemas {
    public static let route = #"{"type":"object","properties":{"intent":{"type":"string","enum":["ask","summarize","edit"]}},"required":["intent"],"additionalProperties":false}"#
    public static func ask(ids: [String]) -> String {
        let idEnum = ids.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"type":"object","properties":{"evidence":{"type":"array","maxItems":3,"items":{"type":"string","maxLength":400}},"answer":{"type":"string","maxLength":600},"found":{"type":"boolean"},"sources":{"type":"array","maxItems":3,"items":{"enum":["#
            + idEnum + #"]}}},"required":["evidence","answer","found","sources"],"additionalProperties":false}"#
    }
    public static let text = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false}"#
    public static let findReplace = #"{"type":"object","properties":{"edits":{"type":"array","minItems":1,"maxItems":8,"items":{"type":"object","properties":{"find":{"type":"string","minLength":1},"replace":{"type":"string"}},"required":["find","replace"],"additionalProperties":false}}},"required":["edits"],"additionalProperties":false}"#
    public static let create = #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}},"required":["title","body"],"additionalProperties":false}"#
    public static let properties = #"{"type":"object","properties":{"ops":{"type":"array","minItems":1,"maxItems":6,"items":{"type":"object","properties":{"op":{"type":"string","enum":["set","remove"]},"key":{"type":"string"},"value":{"type":"array","items":{"type":"string"}}},"required":["op","key","value"],"additionalProperties":false}}},"required":["ops"],"additionalProperties":false}"#
}
