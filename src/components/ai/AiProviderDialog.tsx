import { useEffect, useState } from "react";
import { Loader2, RefreshCw } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  LOCAL_AI_CONFIG,
  type AiProvider,
  type AiProviderConfig,
  type CloudAiModel,
} from "@/lib/ai-provider-config";

const OPENROUTER_URL = "https://openrouter.ai/api/v1";
interface AiProviderDialogProps {
  open: boolean;
  config: AiProviderConfig;
  models: CloudAiModel[];
  modelsBaseUrl: string;
  loadingModels: boolean;
  onOpenChange: (open: boolean) => void;
  onLoadModels: (baseUrl: string, apiKey: string) => Promise<void>;
  onSave: (config: AiProviderConfig, apiKey: string) => void;
}

export function AiProviderDialog({
  open,
  config,
  models,
  modelsBaseUrl,
  loadingModels,
  onOpenChange,
  onLoadModels,
  onSave,
}: AiProviderDialogProps) {
  const [provider, setProvider] = useState<AiProvider>(config.provider);
  const [baseUrl, setBaseUrl] = useState(config.baseUrl);
  const [model, setModel] = useState(config.model);
  const [apiKey, setApiKey] = useState("");

  useEffect(() => {
    if (!open) {
      setApiKey("");
      return;
    }
    setProvider(config.provider);
    setBaseUrl(config.provider === "openrouter" ? OPENROUTER_URL : config.baseUrl);
    setModel(config.model);
    setApiKey("");
  }, [config, open]);

  const selectProvider = (value: AiProvider) => {
    setProvider(value);
    if (value === "local") {
      setBaseUrl("");
      setModel(LOCAL_AI_CONFIG.model);
    } else if (value === "openrouter") {
      setBaseUrl(OPENROUTER_URL);
      if (config.provider !== "openrouter") setModel("");
    } else if (config.provider !== "compatible") {
      setBaseUrl("");
      setModel("");
    }
  };

  const canSave = provider === "local" || Boolean(baseUrl.trim() && model.trim());
  const providerModels = baseUrl.trim() === modelsBaseUrl ? models : [];

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) setApiKey("");
        onOpenChange(nextOpen);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Configure AI chat</DialogTitle>
          <DialogDescription>
            Use Zerus’s offline model or connect an OpenAI-compatible cloud provider.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Provider</Label>
            <Select value={provider} onValueChange={(value) => selectProvider(value as AiProvider)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="local">Local · Qwen3 1.7B</SelectItem>
                <SelectItem value="openrouter">OpenRouter</SelectItem>
                <SelectItem value="compatible">OpenAI-compatible API</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {provider === "local" ? (
            <div className="rounded-md border border-border/70 bg-muted/35 px-3 py-2 text-sm text-muted-foreground">
              Runs locally with MLX. Notes and prompts stay on this device.
            </div>
          ) : (
            <>
              <div className="space-y-2">
                <Label htmlFor="ai-provider-url">API base URL</Label>
                <Input
                  id="ai-provider-url"
                  value={baseUrl}
                  onChange={(event) => setBaseUrl(event.target.value)}
                  disabled={provider === "openrouter"}
                  placeholder="https://api.example.com/v1"
                  autoCapitalize="none"
                  autoCorrect="off"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="ai-provider-key">API key</Label>
                <Input
                  id="ai-provider-key"
                  type="password"
                  value={apiKey}
                  onChange={(event) => setApiKey(event.target.value)}
                  placeholder="Enter a key, or leave blank to reuse this session"
                  autoComplete="off"
                />
                <p className="text-xs text-muted-foreground">
                  The key is kept in memory for this app session only and is never saved in your vault.
                </p>
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <Label htmlFor="ai-provider-model">Model</Label>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 gap-1.5"
                    disabled={loadingModels || !baseUrl.trim()}
                    onClick={() => void onLoadModels(baseUrl.trim(), apiKey)}
                  >
                    {loadingModels ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw size={13} />}
                    Load models
                  </Button>
                </div>
                {providerModels.length > 0 ? (
                  <Select value={model || undefined} onValueChange={setModel}>
                    <SelectTrigger id="ai-provider-model"><SelectValue placeholder="Choose a model" /></SelectTrigger>
                    <SelectContent>
                      {providerModels.map((item) => (
                        <SelectItem key={item.id} value={item.id}>{item.name} · {item.id}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : (
                  <Input
                    id="ai-provider-model"
                    value={model}
                    onChange={(event) => setModel(event.target.value)}
                    placeholder="Load models or enter a model ID"
                    autoCapitalize="none"
                    autoCorrect="off"
                  />
                )}
              </div>
              <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-muted-foreground">
                Cloud requests send the current note and folder context to the selected provider and may incur usage charges.
              </div>
            </>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => {
              setApiKey("");
              onOpenChange(false);
            }}
          >
            Cancel
          </Button>
          <Button
            disabled={!canSave}
            onClick={() => {
              onSave(
                { provider, baseUrl: baseUrl.trim(), model: model.trim() },
                apiKey,
              );
            }}
          >
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
