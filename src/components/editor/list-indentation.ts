import { indentUnit } from "@codemirror/language";

/**
 * CommonMark list nesting is most predictable at four-space boundaries.
 * CodeMirror defaults to two spaces, which can leave a list line in an
 * intermediate parse state and make its live-preview position jump.
 */
export const markdownListIndentation = indentUnit.of("    ");
