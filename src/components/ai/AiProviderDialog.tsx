import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ExternalLink, Loader2, Plus, RefreshCw, X } from "@/lib/icons";
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
  readAiProviderProfile,
  type AiProvider,
  type AiProviderConfig,
  type CloudAiModel,
} from "@/lib/ai-provider-config";
import { openExternalUrl } from "@/lib/external-links";

const API_KEY_CREATION_URLS: Partial<Record<AiProvider, string>> = {
  anthropic: "https://platform.claude.com/settings/keys",
};

interface AiProviderDialogProps {
  open: boolean;
  config: AiProviderConfig;
  models: CloudAiModel[];
  modelsSource: string;
  loadingModels: boolean;
  codexAvailable: boolean;
  codexConnected: boolean;
  codexAccountLabel: string;
  codexPlanType: string;
  onOpenChange: (open: boolean) => void;
  onLoadModels: (provider: AiProvider, baseUrl: string, apiKey: string) => Promise<void>;
  onConnectCodex: () => Promise<boolean>;
  onRefreshCodex: () => Promise<boolean>;
  onConnectOpenRouter: () => Promise<boolean>;
  onSave: (config: AiProviderConfig, apiKey: string) => void;
}

export function AiProviderDialog({
  open,
  config,
  models,
  modelsSource,
  loadingModels,
  codexAvailable,
  codexConnected,
  codexAccountLabel,
  codexPlanType,
  onOpenChange,
  onLoadModels,
  onConnectCodex,
  onRefreshCodex,
  onConnectOpenRouter,
  onSave,
}: AiProviderDialogProps) {
  const [provider, setProvider] = useState<AiProvider>(config.provider);
  const [baseUrl, setBaseUrl] = useState(config.baseUrl);
  const [model, setModel] = useState(config.model);
  const [favoriteModels, setFavoriteModels] = useState(config.favoriteModels);
  const [newModel, setNewModel] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [savedKeyAvailable, setSavedKeyAvailable] = useState(false);
  const [connectingCodex, setConnectingCodex] = useState(false);
  const [connectingOpenRouter, setConnectingOpenRouter] = useState(false);

  useEffect(() => {
    if (!open) {
      setApiKey("");
      return;
    }
    setProvider(config.provider);
    setBaseUrl(config.baseUrl);
    setModel(config.model);
    setFavoriteModels(config.favoriteModels);
    setNewModel("");
    setApiKey("");
  }, [config, open]);

  useEffect(() => {
    if (!open || provider === "codex" || !baseUrl.trim()) {
      setSavedKeyAvailable(false);
      return;
    }
    let disposed = false;
    const timer = window.setTimeout(() => {
      void invoke<boolean>("cloud_ai_key_status", {
        provider,
        baseUrl: baseUrl.trim(),
      }).then((available) => {
        if (!disposed) setSavedKeyAvailable(available);
      }).catch(() => {
        if (!disposed) setSavedKeyAvailable(false);
      });
    }, 200);
    return () => {
      disposed = true;
      window.clearTimeout(timer);
    };
  }, [baseUrl, open, provider]);

  const selectProvider = (value: AiProvider) => {
    const saved = value === config.provider ? config : readAiProviderProfile(value);
    setProvider(value);
    setBaseUrl(saved.baseUrl);
    setModel(saved.model);
    setFavoriteModels(saved.favoriteModels);
    setApiKey("");
  };

  const canSave = Boolean(baseUrl.trim() && model.trim());
  const apiKeyCreationUrl = API_KEY_CREATION_URLS[provider];
  const providerModels = `${provider}:${baseUrl.trim()}` === modelsSource ? models : [];
  const modelOptions = [
    ...favoriteModels.map((id) => ({ id, name: id })),
    ...providerModels,
    ...(model ? [{ id: model, name: model }] : []),
  ].filter((item, index, items) => items.findIndex(({ id }) => id === item.id) === index);

  const addFavoriteModel = () => {
    const nextModel = newModel.trim();
    if (!nextModel || nextModel.length > 200) return;
    setFavoriteModels((current) => current.includes(nextModel) ? current : [...current, nextModel]);
    setModel(nextModel);
    setNewModel("");
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) setApiKey("");
        onOpenChange(nextOpen);
      }}
    >
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Configure AI chat</DialogTitle>
          <DialogDescription>
            Use your ChatGPT plan through Codex, or connect a cloud API.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Provider</Label>
            <Select value={provider} onValueChange={(value) => selectProvider(value as AiProvider)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="openai">OpenAI API key</SelectItem>
                <SelectItem value="codex">ChatGPT plan · Codex</SelectItem>
                <SelectItem value="anthropic">Anthropic (Claude)</SelectItem>
                <SelectItem value="openrouter">OpenRouter</SelectItem>
                <SelectItem value="compatible">OpenAI-compatible API</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <>
              {provider === "codex" && (
                <div className="space-y-3 rounded-md border border-border/70 bg-muted/25 p-3">
                  <div>
                    <p className="text-sm font-medium">Use your ChatGPT plan</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Zerus connects through the Codex app-server installed with ChatGPT or the Codex CLI. Codex owns the browser sign-in and credentials.
                    </p>
                  </div>
                  <Button
                    type="button"
                    variant={codexConnected ? "outline" : "default"}
                    className="w-full gap-2"
                    disabled={connectingCodex}
                    onClick={() => {
                      setConnectingCodex(true);
                      void (codexConnected ? onRefreshCodex() : onConnectCodex())
                        .finally(() => setConnectingCodex(false));
                    }}
                  >
                    {connectingCodex && <Loader2 className="h-4 w-4 animate-spin" />}
                    {connectingCodex
                      ? "Waiting for ChatGPT…"
                      : codexConnected
                        ? "Refresh ChatGPT connection"
                        : "Connect ChatGPT"}
                  </Button>
                  <p className="text-center text-xs text-muted-foreground">
                    {codexConnected
                      ? `Connected${codexAccountLabel ? ` as ${codexAccountLabel}` : ""}${codexPlanType ? ` · ${codexPlanType}` : ""}`
                      : codexAvailable
                        ? "Codex is installed and ready to connect"
                        : "Install ChatGPT or Codex CLI to enable this option"}
                  </p>
                </div>
              )}
              {provider !== "codex" && <>
              <div className="space-y-2">
                <Label htmlFor="ai-provider-url">API base URL</Label>
                <Input
                  id="ai-provider-url"
                  value={baseUrl}
                  onChange={(event) => setBaseUrl(event.target.value)}
                  disabled={provider !== "compatible"}
                  placeholder="https://api.example.com/v1"
                  autoCapitalize="none"
                  autoCorrect="off"
                />
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <Label htmlFor="ai-provider-key">API key</Label>
                  {provider === "openrouter" ? (
                    <Button
                      type="button"
                      variant={savedKeyAvailable ? "outline" : "default"}
                      size="sm"
                      className="h-7 gap-1.5 px-2 text-xs"
                      disabled={connectingOpenRouter}
                      onClick={() => {
                        setConnectingOpenRouter(true);
                        void onConnectOpenRouter()
                          .then((connected) => {
                            if (connected) setSavedKeyAvailable(true);
                          })
                          .finally(() => setConnectingOpenRouter(false));
                      }}
                    >
                      {connectingOpenRouter
                        ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        : <ExternalLink size={13} />}
                      {connectingOpenRouter
                        ? "Waiting for OpenRouter…"
                        : savedKeyAvailable
                          ? "Reconnect OpenRouter"
                          : "Connect OpenRouter"}
                    </Button>
                  ) : apiKeyCreationUrl ? (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-7 gap-1.5 px-2 text-xs"
                      onClick={() => void openExternalUrl(apiKeyCreationUrl)}
                    >
                      <ExternalLink size={13} /> Create API key
                    </Button>
                  ) : null}
                </div>
                <Input
                  id="ai-provider-key"
                  type="password"
                  value={apiKey}
                  onChange={(event) => setApiKey(event.target.value)}
                  placeholder="Enter a key, or leave blank to use the saved key"
                  autoComplete="off"
                />
                <p className="text-xs text-muted-foreground">
                  {apiKey.trim()
                    ? "This key will replace the saved key for this endpoint."
                    : savedKeyAvailable
                      ? provider === "openrouter"
                        ? "OpenRouter is connected. The generated key is stored securely on this device."
                        : "A saved key is available for this endpoint and will be reused."
                      : "Saved in this device’s secure credential store when supported. It is never put in your vault or browser storage."}
                </p>
              </div>
              </>}
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <Label htmlFor="ai-provider-model">Model</Label>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 gap-1.5"
                    disabled={loadingModels || !baseUrl.trim()}
                    onClick={() => void (provider === "codex"
                      ? onRefreshCodex()
                      : onLoadModels(provider, baseUrl.trim(), apiKey))}
                  >
                    {loadingModels ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw size={13} />}
                    Load models
                  </Button>
                </div>
                {modelOptions.length > 0 ? (
                  <Select
                    value={model || undefined}
                    onValueChange={(nextModel) => {
                      setModel(nextModel);
                      setFavoriteModels((current) => current.includes(nextModel)
                        ? current
                        : [...current, nextModel]);
                    }}
                  >
                    <SelectTrigger id="ai-provider-model"><SelectValue placeholder="Choose a model" /></SelectTrigger>
                    <SelectContent>
                      {modelOptions.map((item) => (
                        <SelectItem key={item.id} value={item.id}>
                          {item.name === item.id ? item.id : `${item.name} · ${item.id}`}
                        </SelectItem>
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
                <div className="space-y-2 pt-1">
                  <Label htmlFor="ai-provider-new-model">Favourite models</Label>
                  <div className="flex gap-2">
                    <Input
                      id="ai-provider-new-model"
                      value={newModel}
                      onChange={(event) => setNewModel(event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") {
                          event.preventDefault();
                          addFavoriteModel();
                        }
                      }}
                      placeholder="Enter a model ID"
                      autoCapitalize="none"
                      autoCorrect="off"
                    />
                    <Button
                      type="button"
                      variant="outline"
                      className="shrink-0 gap-1.5"
                      disabled={!newModel.trim() || newModel.trim().length > 200}
                      onClick={addFavoriteModel}
                    >
                      <Plus size={14} /> Add
                    </Button>
                  </div>
                  {favoriteModels.length > 0 && (
                    <div className="max-h-32 space-y-1.5 overflow-y-auto pr-1">
                      {favoriteModels.map((favorite) => (
                        <div
                          key={favorite}
                          className="flex items-center gap-2 rounded-md border border-border/70 bg-muted/25 px-2.5 py-1.5 text-xs"
                        >
                          <button
                            type="button"
                            className="min-w-0 flex-1 truncate text-left hover:text-foreground"
                            onClick={() => setModel(favorite)}
                            title={`Use ${favorite}`}
                          >
                            {favorite}
                          </button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            className="h-6 w-6 shrink-0"
                            onClick={() => setFavoriteModels((current) => current.filter((item) => item !== favorite))}
                            aria-label={`Remove ${favorite} from favourites`}
                            title="Remove from favourites"
                          >
                            <X size={13} />
                          </Button>
                        </div>
                      ))}
                    </div>
                  )}
                  <p className="text-xs text-muted-foreground">
                    Saved favourites stay available in the AI panel’s model switcher.
                  </p>
                </div>
              </div>
              <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-muted-foreground">
                Cloud requests send the current note and folder context to the selected provider and may incur usage charges.
              </div>
          </>
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
                {
                  provider,
                  baseUrl: baseUrl.trim(),
                  model: model.trim(),
                  favoriteModels,
                },
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
