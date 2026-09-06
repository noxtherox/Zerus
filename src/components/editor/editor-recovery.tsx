import { Component, type ReactNode } from "react";

type Props = {
  markdown: string;
  onChange: (markdown: string) => void;
  readOnly: boolean;
  children: ReactNode;
};
/** A JavaScript/editor error must not make the underlying note inaccessible. */
export class EditorRecoveryBoundary extends Component<
  Props,
  { error: string | null }
> {
  state: { error: string | null } = { error: null };
  static getDerivedStateFromError(error: Error) {
    return { error: error.message };
  }
  recover(error: string) {
    this.setState({ error });
  }
  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="zerus-editor-recovery">
        <p role="alert">
          The formatted editor could not open this note. Your Markdown is
          available below.
        </p>
        <textarea
          aria-label="Note Markdown recovery"
          value={this.props.markdown}
          readOnly={this.props.readOnly}
          onChange={(event) => this.props.onChange(event.target.value)}
          spellCheck={false}
        />
        <button type="button" onClick={() => this.setState({ error: null })}>
          Retry formatted editor
        </button>
      </div>
    );
  }
}
