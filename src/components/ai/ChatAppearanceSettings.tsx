import { useId } from "react";
import { Switch } from "@/components/ui/switch";

export function ChatAppearanceSettings({
  simpleMode,
  onSimpleModeChange,
  disabled = false,
  error = "",
}: {
  simpleMode: boolean;
  onSimpleModeChange: (enabled: boolean) => void;
  disabled?: boolean;
  error?: string;
}) {
  const id = useId();
  return (
    <div className="rounded-xl border border-border/70 bg-muted/25 p-4">
      <div className="flex items-center justify-between gap-4">
        <div className="min-w-0">
          <label htmlFor={id} className="cursor-pointer text-sm font-medium">Simple mode</label>
          <p id={`${id}-description`} className="mt-1 text-xs leading-5 text-muted-foreground">
            A cleaner chat with messages, file uploads, and dictation. Hides context, agent controls, and activity details.
          </p>
        </div>
        <Switch
          id={id}
          checked={simpleMode}
          onCheckedChange={onSimpleModeChange}
          disabled={disabled}
          aria-describedby={`${id}-description`}
        />
      </div>
      {error && <p role="alert" className="mt-2 text-xs text-destructive">{error}</p>}
    </div>
  );
}
