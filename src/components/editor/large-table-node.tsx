import type { JSX } from "react";
import {
  DecoratorNode,
  type NodeKey,
  type SerializedLexicalNode,
  type Spread,
} from "lexical";
import type * as Mdast from "mdast";
import { tableMarkdown } from "./table-data";
import { LargeTableView } from "./large-table-view";

type SerializedLargeTable = Spread<
  { table: Mdast.Table },
  SerializedLexicalNode
>;
export class LargeTableNode extends DecoratorNode<JSX.Element> {
  __table: Mdast.Table;
  static getType() {
    return "zerus-large-table";
  }
  static clone(node: LargeTableNode) {
    return new LargeTableNode(node.__table, node.__key);
  }
  constructor(table: Mdast.Table, key?: NodeKey) {
    super(key);
    this.__table = table;
  }
  static importJSON(node: SerializedLargeTable) {
    return new LargeTableNode(node.table);
  }
  exportJSON(): SerializedLargeTable {
    return {
      ...super.exportJSON(),
      type: "zerus-large-table",
      version: 1,
      table: this.__table,
    };
  }
  createDOM() {
    const el = document.createElement("div");
    el.className = "zerus-large-table";
    return el;
  }
  updateDOM() {
    return false;
  }
  isInline() {
    return false;
  }
  getTextContent() {
    return tableMarkdown(this.getLatest().__table);
  }
  exportDOM() {
    const element = document.createElement("pre");
    element.textContent = this.getTextContent();
    return { element };
  }
  setTable(table: Mdast.Table) {
    this.getWritable().__table = table;
  }
  decorate() {
    return <LargeTableView table={this.__table} nodeKey={this.__key} />;
  }
}
