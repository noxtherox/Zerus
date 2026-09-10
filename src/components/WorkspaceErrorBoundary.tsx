import { Component, type ErrorInfo, type ReactNode } from "react";

/** Remount the interface without reloading the store or losing pending edits. */
export class WorkspaceErrorBoundary extends Component<
  { children: ReactNode },
  { error: Error | null }
> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Zerus: workspace rendering failed", error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div role="alert" className="flex h-screen items-center justify-center bg-background p-6 text-foreground">
        <div className="max-w-sm space-y-4 text-center">
          <h1 className="text-xl font-semibold">Couldn’t display the workspace</h1>
          <p className="text-sm text-muted-foreground">
            Try reopening the interface. Your pending note changes will stay in memory.
          </p>
          <button
            className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground"
            onClick={() => this.setState({ error: null })}
          >
            Reopen interface
          </button>
          <details className="text-left text-xs text-muted-foreground">
            <summary>Error details</summary>
            <pre className="mt-2 whitespace-pre-wrap break-words">{String(this.state.error)}</pre>
          </details>
        </div>
      </div>
    );
  }
}
