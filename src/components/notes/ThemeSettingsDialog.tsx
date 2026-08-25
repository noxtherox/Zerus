import { useEffect, useState } from "react";
import {
  Bot,
  CheckCircle2,
  Download,
  FolderCog,
  FolderOpen,
  MapPin,
  Plus,
  RotateCcw,
  Save,
  Trash2,
  TerminalSquare,
} from "@/lib/icons";
import { invoke } from "@tauri-apps/api/core";
import { save as saveDialog } from "@tauri-apps/plugin-dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  DEFAULT_DARK_THEME,
  DEFAULT_LIGHT_THEME,
  MAX_SAVED_THEME_NAME_LENGTH,
  type AppearanceMode,
  type ThemeSlot,
  type ZerusTheme,
  THEME_PRESETS,
  THEME_TOKENS,
  deleteSavedTheme,
  isValidHex,
  loadSavedThemes,
  loadThemePreferences,
  resolveThemeSlot,
  saveNamedTheme,
  saveThemePreferences,
} from "@/lib/theme";
import {
  DEFAULT_INTERFACE_ZOOM,
  INTERFACE_ZOOM_OPTIONS,
  loadInterfaceZoom,
  saveInterfaceZoom,
  type InterfaceZoom,
} from "@/lib/interface-preferences";
import { DEFAULT_TYPE, noteTitle, typeKey } from "@/lib/note-utils";
import {
  DEFAULT_NOTE_ALIGNMENT,
  DEFAULT_NOTE_WIDTH,
  loadNoteAlignment,
  loadNoteWidth,
  NOTE_ALIGNMENT_OPTIONS,
  NOTE_WIDTH_OPTIONS,
  saveNoteAlignment,
  saveNoteWidth,
  type NoteAlignment,
  type NoteWidth,
} from "@/lib/note-preferences";
import {
  addFileLocation,
  clearVaultVersionHistory,
  fileLocationUsages,
  getFileLocationMappings,
  mapFileLocation,
  refreshVaultFromDisk,
  removeFileLocation,
  renameFileLocation,
  updateVersionHistorySettings,
  useVault,
} from "@/store/notes-store";

/** Hex text field that tolerates partial input while typing. */
function HexInput({
  value,
  onCommit,
}: {
  value: string;
  onCommit: (hex: string) => void;
}) {
  const [draft, setDraft] = useState(value);

  // Follow external changes (color picker, presets, reset)
  useEffect(() => setDraft(value), [value]);

  return (
    <input
      value={draft}
      onChange={(event) => {
        const next = event.target.value;
        setDraft(next);
        if (isValidHex(next)) onCommit(next.trim());
      }}
      onBlur={() => setDraft(value)}
      spellCheck={false}
      className="w-20 rounded-md border border-border bg-transparent px-2 py-1 font-mono text-xs uppercase focus:outline-none focus:ring-1 focus:ring-ring"
    />
  );
}

interface ThemeSettingsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultNoteType: string[];
  hideSubtypeNotes: boolean;
  existingTypePaths: string[][];
  onDefaultNoteTypeChange: (typePath: string[]) => void;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
}

interface CliStatus {
  installed: boolean;
  executablePath: string;
  onPath: boolean;
  version: string;
}

interface MigrationPreview {
  notesScanned: number;
  notesChanged: number;
  idsAdded: number;
  pinnedAdded: number;
  archivedAdded: number;
  blocked: boolean;
  warnings: string[];
}

export function ThemeSettingsDialog({
  open,
  onOpenChange,
  defaultNoteType,
  hideSubtypeNotes,
  existingTypePaths,
  onDefaultNoteTypeChange,
  onHideSubtypeNotesChange,
}: ThemeSettingsDialogProps) {
  const [themePreferences, setThemePreferences] = useState(
    loadThemePreferences,
  );
  const [editingTheme, setEditingTheme] = useState<ThemeSlot>(() =>
    resolveThemeSlot(loadThemePreferences().mode),
  );
  const [savedThemes, setSavedThemes] = useState(loadSavedThemes);
  const [themeName, setThemeName] = useState("");
  const [interfaceZoom, setInterfaceZoom] =
    useState<InterfaceZoom>(loadInterfaceZoom);
  const [noteWidth, setNoteWidth] = useState<NoteWidth>(loadNoteWidth);
  const [noteAlignment, setNoteAlignment] =
    useState<NoteAlignment>(loadNoteAlignment);
  const [locationDraft, setLocationDraft] = useState("");
  const [cliStatus, setCliStatus] = useState<CliStatus | null>(null);
  const [migrationPreview, setMigrationPreview] =
    useState<MigrationPreview | null>(null);
  const [cliBusy, setCliBusy] = useState(false);
  const [cliMessage, setCliMessage] = useState("");
  const [cliMessageKind, setCliMessageKind] = useState<"success" | "error">(
    "success",
  );
  const [cliInstallConfirmOpen, setCliInstallConfirmOpen] = useState(false);
  const [clearHistoryConfirmOpen, setClearHistoryConfirmOpen] = useState(false);
  const { fileLocations, historyError, historySettings, isDesktop, location, notes } = useVault();
  const locationMappings = getFileLocationMappings();

  useEffect(() => {
    if (open) {
      const preferences = loadThemePreferences();
      setThemePreferences(preferences);
      setEditingTheme(resolveThemeSlot(preferences.mode));
      setSavedThemes(loadSavedThemes());
      setInterfaceZoom(loadInterfaceZoom());
      setNoteWidth(loadNoteWidth());
      setNoteAlignment(loadNoteAlignment());
      if (isDesktop) {
        void invoke<CliStatus>("cli_status").then(setCliStatus);
        if (location) {
          const pinnedPaths = notes.filter((note) => note.pinned).map((note) => note.path);
          const archivedPaths = notes.filter((note) => note.archived).map((note) => note.path);
          void invoke<MigrationPreview>("cli_migration_preview", {
            vaultPath: location,
            pinnedPaths,
            archivedPaths,
          }).then(setMigrationPreview);
        }
      }
    }
  }, [isDesktop, location, notes, open]);

  // Changes apply immediately so you can preview them behind the dialog
  const update = (patch: Partial<ZerusTheme>) => {
    setThemePreferences((previous) => {
      const key = editingTheme === "light" ? "lightTheme" : "darkTheme";
      const next = {
        ...previous,
        [key]: { ...previous[key], ...patch },
      };
      saveThemePreferences(next);
      return next;
    });
  };

  const theme =
    editingTheme === "light"
      ? themePreferences.lightTheme
      : themePreferences.darkTheme;

  const setAppearanceMode = (mode: AppearanceMode) => {
    const next = { ...themePreferences, mode };
    setThemePreferences(next);
    saveThemePreferences(next);
    setEditingTheme(resolveThemeSlot(mode));
  };

  const defaultTypeKey = typeKey(defaultNoteType);
  const cleanThemeName = themeName.trim();
  const hasBuiltInName = THEME_PRESETS.some(
    (preset) =>
      preset.name.toLocaleLowerCase() === cleanThemeName.toLocaleLowerCase(),
  );
  const replacesSavedTheme = savedThemes.some(
    (saved) =>
      saved.name.toLocaleLowerCase() === cleanThemeName.toLocaleLowerCase(),
  );
  const typeOptions = [
    DEFAULT_TYPE,
    ...existingTypePaths,
    defaultNoteType,
  ].filter(
    (path, index, paths) =>
      paths.findIndex((candidate) => typeKey(candidate) === typeKey(path)) ===
      index,
  );

  const installCli = async (prepareNotes: boolean) => {
    if (prepareNotes && !location) return;

    setCliBusy(true);
    setCliMessage("");
    try {
      let idsAdded: number | null = null;
      if (prepareNotes && location) {
        const pinnedPaths = notes
          .filter((note) => note.pinned)
          .map((note) => note.path);
        const archivedPaths = notes
          .filter((note) => note.archived)
          .map((note) => note.path);
        const migration = await invoke<MigrationPreview>(
          "cli_migration_apply",
          { vaultPath: location, pinnedPaths, archivedPaths },
        );
        await refreshVaultFromDisk();
        const nextPreview = await invoke<MigrationPreview>(
          "cli_migration_preview",
          { vaultPath: location, pinnedPaths, archivedPaths },
        );
        setMigrationPreview(nextPreview);
        idsAdded = migration.idsAdded;
      }

      const status = await invoke<CliStatus>("cli_install");
      setCliStatus(status);

      if (idsAdded !== null) {
        setCliMessage(
          idsAdded === 0
            ? "CLI installed successfully. Your notes already have zerus-id."
            : `CLI installed successfully. Added zerus-id to ${idsAdded} ${idsAdded === 1 ? "note" : "notes"}.`,
        );
      } else {
        setCliMessage(`CLI reinstalled successfully at ${status.executablePath}.`);
      }
      setCliMessageKind("success");
    } catch (error) {
      setCliMessage(String(error));
      setCliMessageKind("error");
    } finally {
      setCliBusy(false);
    }
  };

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="h-[min(660px,calc(100vh-2rem))] max-h-none max-w-2xl grid-rows-[auto_minmax(0,1fr)] overflow-hidden">
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
          <DialogDescription>
            Choose how Zerus looks, behaves, and connects to your files.
          </DialogDescription>
        </DialogHeader>
        <Tabs defaultValue="general" className="flex min-h-0 min-w-0 flex-col">
          <TabsList className="grid w-full shrink-0 grid-cols-4">
            <TabsTrigger value="general">General</TabsTrigger>
            <TabsTrigger value="appearance">Appearance</TabsTrigger>
            <TabsTrigger value="sync">Sync</TabsTrigger>
            <TabsTrigger value="cli">CLI</TabsTrigger>
          </TabsList>

          <TabsContent value="cli" className="mt-4 min-h-0 flex-1 space-y-4 overflow-y-auto pr-1">
            {isDesktop ? (
              <>
                <div className="rounded-lg border border-border p-4">
                  <div className="flex items-start gap-3">
                    <TerminalSquare className="mt-0.5 shrink-0 text-muted-foreground" size={18} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium">Zerus command line</p>
                      <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                        Installing the CLI will enable your AI agents to interact directly with the commands for Zerus, which makes it clearer for the agent to work. For that, we will need to introduce some hidden properties in your notes which will not affect how you use the desktop application. Here&apos;s a preview.
                      </p>
                      <div className="mt-3 rounded-md bg-muted/60 p-3 text-xs">
                        {migrationPreview ? (
                          <>
                            <p>{migrationPreview.notesChanged} of {migrationPreview.notesScanned} notes will be updated.</p>
                            <p className="mt-1 text-muted-foreground">
                              {migrationPreview.idsAdded} note IDs, {migrationPreview.pinnedAdded} pinned statuses, and {migrationPreview.archivedAdded} archived statuses will be added as hidden data.
                            </p>
                            {migrationPreview.blocked && (
                              <p className="mt-2 text-destructive">Some notes need review before migration: {migrationPreview.warnings.join(" · ")}</p>
                            )}
                          </>
                        ) : (
                          <p className="text-muted-foreground">Preparing migration preview…</p>
                        )}
                      </div>
                      <div className="mt-3 flex flex-wrap gap-2">
                        <Button
                          size="sm"
                          disabled={
                            cliBusy ||
                            (!cliStatus?.installed &&
                              (!migrationPreview ||
                                migrationPreview.blocked ||
                                !location))
                          }
                          onClick={() => {
                            if (cliStatus?.installed) {
                              void installCli(false);
                            } else {
                              setCliInstallConfirmOpen(true);
                            }
                          }}
                        >
                          {cliStatus?.installed ? "Reinstall CLI" : "Install CLI"}
                        </Button>
                      </div>
                      {cliStatus?.installed && (
                        <p className="mt-2 flex items-center gap-1 text-xs text-muted-foreground">
                          <CheckCircle2 size={13} className="text-green-600" /> Installed at {cliStatus.executablePath}{!cliStatus.onPath && " · Add its folder to PATH to use zerus anywhere."}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
                <div className="rounded-lg border border-border p-4">
                  <div className="flex items-start gap-3">
                    <Bot className="mt-0.5 shrink-0 text-muted-foreground" size={18} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium">AI agent skills</p>
                      <p className="mt-1 text-xs text-muted-foreground">Install instructions that teach an agent to use Zerus safely and consistently.</p>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {["Claude", "Codex", "Hermes"].map((agent) => (
                          <Button
                            key={agent}
                            size="sm"
                            variant="outline"
                            disabled={cliBusy}
                            onClick={async () => {
                              setCliBusy(true);
                              try {
                                const path = await invoke<string>("cli_install_skill", { agent: agent.toLowerCase().replace(" ", "-"), profile: null });
                                setCliMessage(`${agent} skill installed at ${path}`);
                                setCliMessageKind("success");
                              } catch (error) {
                                setCliMessage(String(error));
                                setCliMessageKind("error");
                              } finally {
                                setCliBusy(false);
                              }
                            }}
                          >
                            Install for {agent}
                          </Button>
                        ))}
                      </div>
                      <div className="mt-5 border-t border-border pt-4">
                        <Button
                          size="sm"
                          variant="outline"
                          className="gap-1.5"
                          disabled={cliBusy}
                          onClick={async () => {
                            setCliBusy(true);
                            try {
                              const path = await saveDialog({
                                title: "Download Zerus skill",
                                defaultPath: "zerus-skill.md",
                                filters: [
                                  {
                                    name: "Markdown",
                                    extensions: ["md"],
                                  },
                                ],
                              });
                              if (!path) return;

                              setCliMessage("");
                              const savedPath = await invoke<string>(
                                "cli_export_skill",
                                { path },
                              );
                              setCliMessage(`Zerus skill saved to ${savedPath}`);
                              setCliMessageKind("success");
                            } catch (error) {
                              setCliMessage(String(error));
                              setCliMessageKind("error");
                            } finally {
                              setCliBusy(false);
                            }
                          }}
                        >
                          <Download size={13} />
                          Download skill for other agents
                        </Button>
                      </div>
                    </div>
                  </div>
                </div>
                {cliMessage && (
                  <p
                    className={`flex items-center gap-1 text-xs ${
                      cliMessageKind === "success"
                        ? "text-green-600"
                        : "text-destructive"
                    }`}
                    role="status"
                  >
                    {cliMessageKind === "success" && <CheckCircle2 size={13} />}
                    {cliMessage}
                  </p>
                )}
              </>
            ) : (
              <div className="rounded-lg border border-border p-3 text-sm">CLI installation is available in the desktop app.</div>
            )}
          </TabsContent>

          <TabsContent value="sync" className="mt-4 min-h-0 flex-1 overflow-y-auto pr-1">
            {isDesktop ? (
              <div>
              <p className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                File locations
              </p>
              <div className="space-y-2 rounded-lg border border-border p-3">
                <p className="text-xs text-muted-foreground">
                  Names sync with the vault. Each device maps the name to its
                  own local cloud-folder root.
                </p>
                {fileLocations.map((location) => {
                  const usages = fileLocationUsages(location.id);
                  const mapped = locationMappings[location.id];
                  return (
                    <div key={location.id} className="rounded-md border p-2">
                      <div className="flex items-center gap-2">
                        <FolderCog size={14} className="shrink-0 text-muted-foreground" />
                        <Input
                          defaultValue={location.name}
                          className="h-7 min-w-0 flex-1 text-xs"
                          aria-label="File location name"
                          onBlur={(event) =>
                            renameFileLocation(location.id, event.target.value)
                          }
                        />
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-7 gap-1 text-xs"
                          onClick={() => void mapFileLocation(location.id)}
                        >
                          <MapPin size={12} /> {mapped ? "Remap" : "Map"}
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-destructive hover:text-destructive"
                          disabled={usages.length > 0}
                          title={
                            usages.length
                              ? `Used by: ${usages.map(noteTitle).join(", ")}`
                              : "Remove location"
                          }
                          onClick={() => removeFileLocation(location.id)}
                        >
                          <Trash2 size={13} />
                        </Button>
                      </div>
                      <p className="mt-1 truncate pl-6 text-[11px] text-muted-foreground">
                        {mapped ?? "Not configured on this device"}
                        {usages.length > 0 && ` · ${usages.length} hub${usages.length === 1 ? "" : "s"}`}
                      </p>
                    </div>
                  );
                })}
                <div className="flex gap-2">
                  <Input
                    value={locationDraft}
                    onChange={(event) => setLocationDraft(event.target.value)}
                    placeholder="Company OneDrive"
                    className="h-8 text-xs"
                  />
                  <Button
                    size="sm"
                    className="h-8 shrink-0 gap-1 text-xs"
                    disabled={!locationDraft.trim()}
                    aria-label="Browse for the file location folder"
                    title="Browse for the local folder on this computer"
                    onClick={async () => {
                      if (await addFileLocation(locationDraft)) setLocationDraft("");
                    }}
                  >
                    <FolderOpen size={13} /> Browse folder
                  </Button>
                </div>
              </div>
              </div>
            ) : (
              <div className="rounded-lg border border-border p-3">
                <p className="text-sm font-medium">File locations</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Local folder mappings are available in the desktop app.
                </p>
              </div>
            )}
          </TabsContent>

          <TabsContent value="general" className="mt-4 min-h-0 flex-1 overflow-y-auto pr-1">
          <p className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Note list
          </p>
          <div className="mb-5 flex items-center justify-between gap-4 rounded-lg border border-border p-3">
            <div>
              <label
                htmlFor="hide-subtype-notes"
                className="text-sm font-medium"
              >
                Hide sub-type notes
              </label>
              <p className="mt-0.5 text-xs text-muted-foreground">
                When a type is selected, show only notes directly inside that
                folder.
              </p>
            </div>
            <Switch
              id="hide-subtype-notes"
              checked={hideSubtypeNotes}
              onCheckedChange={onHideSubtypeNotesChange}
            />
          </div>
          <p className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            New notes
          </p>
          <div className="mb-5 rounded-lg border border-border p-3">
            <label
              htmlFor="default-note-type"
              className="block text-sm font-medium"
            >
              Default type
            </label>
            <p className="mb-3 mt-0.5 text-xs text-muted-foreground">
              Used when you create a note from All Notes. If you do not choose
              one, Inbox is used.
            </p>
            <Select
              value={defaultTypeKey}
              onValueChange={(key) => {
                const next = typeOptions.find((path) => typeKey(path) === key);
                if (next) onDefaultNoteTypeChange(next);
              }}
            >
              <SelectTrigger id="default-note-type">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {typeOptions.map((path) => {
                  const key = typeKey(path);
                  return (
                    <SelectItem key={key} value={key}>
                      {key === typeKey(DEFAULT_TYPE)
                        ? "Inbox (default)"
                        : path.join(" / ")}
                    </SelectItem>
                  );
                })}
              </SelectContent>
            </Select>
          </div>
          <p className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Version history
          </p>
          <div className="mb-5 space-y-4 rounded-lg border border-border p-3">
            <div className="flex items-center justify-between gap-4">
              <div>
                <label htmlFor="history-enabled" className="text-sm font-medium">Record version history</label>
                <p className="mt-0.5 text-xs text-muted-foreground">Every content autosave is recorded. Turning this off preserves existing versions.</p>
              </div>
              <Switch id="history-enabled" checked={historySettings.enabled} onCheckedChange={(enabled) => void updateVersionHistorySettings({ ...historySettings, enabled })} />
            </div>
            <div className="grid grid-cols-[1fr_110px] items-end gap-3">
              <div>
                <label htmlFor="history-checkpoints" className="text-sm font-medium">Retained checkpoints</label>
                <p className="mt-0.5 text-xs text-muted-foreground">One checkpoint represents up to 50 versions. Kept versions are exempt.</p>
              </div>
              {historySettings.checkpointLimit === null ? (
                <Button variant="outline" size="sm" onClick={() => void updateVersionHistorySettings({ ...historySettings, checkpointLimit: 10 })}>Unlimited</Button>
              ) : (
                <Input key={historySettings.checkpointLimit} id="history-checkpoints" type="number" min={1} max={100} defaultValue={historySettings.checkpointLimit} onBlur={(event) => {
                  const checkpointLimit = Math.max(1, Math.min(100, Number(event.target.value) || 1));
                  void updateVersionHistorySettings({ ...historySettings, checkpointLimit });
                }} />
              )}
            </div>
            <div className="flex items-center justify-between gap-3">
              <Button variant="ghost" size="sm" className="px-0 text-xs text-muted-foreground" onClick={() => void updateVersionHistorySettings({ ...historySettings, checkpointLimit: historySettings.checkpointLimit === null ? 10 : null })}>{historySettings.checkpointLimit === null ? "Use a fixed limit" : "Keep unlimited checkpoints"}</Button>
              <Button variant="outline" size="sm" className="text-destructive hover:text-destructive" onClick={() => setClearHistoryConfirmOpen(true)}>Clear all history</Button>
            </div>
            {historyError && <p className="text-xs text-destructive">{historyError}</p>}
          </div>
          </TabsContent>

          <TabsContent value="appearance" className="mt-4 min-h-0 flex-1 overflow-y-auto pr-1">
          <p className="pb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Appearance
          </p>
          <div className="mb-5 rounded-lg border border-border p-3">
            <label htmlFor="appearance-mode" className="block text-sm font-medium">
              Theme
            </label>
            <p className="mb-3 mt-0.5 text-xs text-muted-foreground">
              Choose a fixed appearance or follow your system setting.
            </p>
            <Select
              value={themePreferences.mode}
              onValueChange={(value: AppearanceMode) => setAppearanceMode(value)}
            >
              <SelectTrigger id="appearance-mode">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="light">Light</SelectItem>
                <SelectItem value="dark">Dark</SelectItem>
                <SelectItem value="system">Match system</SelectItem>
              </SelectContent>
            </Select>
            <label
              htmlFor="interface-zoom"
              className="mt-4 block text-sm font-medium"
            >
              Interface zoom
            </label>
            <p className="mb-3 mt-0.5 text-xs text-muted-foreground">
              Scales text, controls, icons, and the rest of the interface.
            </p>
            <Select
              value={String(interfaceZoom)}
              onValueChange={(value) => {
                const zoom = Number(value) as InterfaceZoom;
                setInterfaceZoom(zoom);
                saveInterfaceZoom(zoom);
              }}
            >
              <SelectTrigger id="interface-zoom">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {INTERFACE_ZOOM_OPTIONS.map((zoom) => (
                  <SelectItem key={zoom} value={String(zoom)}>
                    {zoom}%{zoom === DEFAULT_INTERFACE_ZOOM ? " (Default)" : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <label
              htmlFor="note-width"
              className="mt-4 block text-sm font-medium"
            >
              Note width
            </label>
            <p className="mb-3 mt-0.5 text-xs text-muted-foreground">
              Sets the width of the writing area within the editor.
            </p>
            <Select
              value={String(noteWidth)}
              onValueChange={(value) => {
                const width = Number(value) as NoteWidth;
                setNoteWidth(width);
                saveNoteWidth(width);
              }}
            >
              <SelectTrigger id="note-width">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {NOTE_WIDTH_OPTIONS.map((width) => (
                  <SelectItem key={width} value={String(width)}>
                    {width}%
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <label
              htmlFor="note-alignment"
              className="mt-4 block text-sm font-medium"
            >
              Alignment
            </label>
            <Select
              value={noteAlignment}
              onValueChange={(value: NoteAlignment) => {
                setNoteAlignment(value);
                saveNoteAlignment(value);
              }}
            >
              <SelectTrigger id="note-alignment" className="mt-2">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {NOTE_ALIGNMENT_OPTIONS.map((alignment) => (
                  <SelectItem key={alignment} value={alignment}>
                    {alignment === "center" ? "Center" : "Left"}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="mb-4 rounded-lg border border-border p-3">
            <label htmlFor="theme-to-customize" className="block text-sm font-medium">
              Customize theme
            </label>
            <p className="mb-3 mt-0.5 text-xs text-muted-foreground">
              Pick the palette Zerus uses for each system appearance.
            </p>
            <Select
              value={editingTheme}
              onValueChange={(value: ThemeSlot) => setEditingTheme(value)}
            >
              <SelectTrigger id="theme-to-customize">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="light">Light theme</SelectItem>
                <SelectItem value="dark">Dark theme</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <p className="pb-2 text-xs font-medium text-muted-foreground">
            Presets for the {editingTheme} theme
          </p>
          <div className="flex flex-wrap gap-2 pb-4">
            {THEME_PRESETS.map((preset) => (
              <button
                type="button"
                key={preset.name}
                onClick={() => update(preset.theme)}
                className="flex items-center gap-1.5 rounded-full border border-border px-2.5 py-1 text-xs transition-colors hover:bg-muted"
              >
                <span className="flex overflow-hidden rounded-full border border-black/10">
                  {[
                    preset.theme.sidebarBg,
                    preset.theme.surface,
                    preset.theme.accent,
                  ].map((color) => (
                    <span
                      key={color}
                      className="h-3 w-3"
                      style={{ backgroundColor: color }}
                    />
                  ))}
                </span>
                {preset.name}
              </button>
            ))}
          </div>
          {savedThemes.length > 0 && (
            <div className="pb-4">
              <p className="pb-2 text-xs font-medium text-muted-foreground">
                Saved themes
              </p>
              <div className="flex flex-wrap gap-2">
                {savedThemes.map((saved) => (
                  <div
                    key={saved.name}
                    className="flex items-center overflow-hidden rounded-full border border-border"
                  >
                    <button
                      type="button"
                      onClick={() => update(saved.theme)}
                      className="flex items-center gap-1.5 py-1 pl-2.5 pr-2 text-xs transition-colors hover:bg-muted"
                    >
                      <span className="flex overflow-hidden rounded-full border border-black/10">
                        {[
                          saved.theme.sidebarBg,
                          saved.theme.surface,
                          saved.theme.accent,
                        ].map((color) => (
                          <span
                            key={color}
                            className="h-3 w-3"
                            style={{ backgroundColor: color }}
                          />
                        ))}
                      </span>
                      {saved.name}
                    </button>
                    <button
                      type="button"
                      aria-label={`Delete saved theme ${saved.name}`}
                      title={`Delete ${saved.name}`}
                      onClick={() =>
                        setSavedThemes(deleteSavedTheme(saved.name))
                      }
                      className="border-l border-border px-2 py-1.5 text-muted-foreground transition-colors hover:bg-muted hover:text-destructive"
                    >
                      <Trash2 size={12} />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div className="space-y-1">
            {THEME_TOKENS.map((token) => (
              <div
                key={token.key}
                className="flex items-center gap-3 rounded-md px-1 py-1.5"
              >
                <label
                  htmlFor={`theme-${token.key}`}
                  className="min-w-0 flex-1"
                >
                  <span className="block text-sm">{token.label}</span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {token.hint}
                  </span>
                </label>
                <HexInput
                  value={theme[token.key]}
                  onCommit={(hex) => update({ [token.key]: hex })}
                />
                <input
                  id={`theme-${token.key}`}
                  type="color"
                  value={theme[token.key]}
                  onChange={(event) =>
                    update({ [token.key]: event.target.value })
                  }
                  className="h-7 w-9 shrink-0 cursor-pointer rounded border border-border bg-transparent p-0.5"
                />
              </div>
            ))}
          </div>
          <div className="mt-3 rounded-md border border-border p-3">
            <label htmlFor="theme-name" className="text-sm font-medium">
              Save these colours as a theme
            </label>
            <p className="mb-2 mt-0.5 text-xs text-muted-foreground">
              Your saved theme will appear above with the built-in presets.
            </p>
            <div className="flex gap-2">
              <Input
                id="theme-name"
                value={themeName}
                maxLength={MAX_SAVED_THEME_NAME_LENGTH}
                onChange={(event) => setThemeName(event.target.value)}
                placeholder="Theme name"
                className="h-8 text-xs"
                onKeyDown={(event) => {
                  if (
                    event.key === "Enter" &&
                    cleanThemeName &&
                    !hasBuiltInName
                  ) {
                    setSavedThemes(saveNamedTheme(cleanThemeName, theme));
                  }
                }}
              />
              <Button
                type="button"
                size="sm"
                className="h-8 shrink-0 gap-1.5 text-xs"
                disabled={!cleanThemeName || hasBuiltInName}
                onClick={() =>
                  setSavedThemes(saveNamedTheme(cleanThemeName, theme))
                }
              >
                <Save size={13} />
                {replacesSavedTheme ? "Update theme" : "Save theme"}
              </Button>
            </div>
            {hasBuiltInName && (
              <p className="mt-1.5 text-xs text-destructive">
                Choose a name that is different from a built-in theme.
              </p>
            )}
          </div>
          <div className="flex justify-end pt-3">
            <Button
              variant="outline"
              size="sm"
              className="gap-1.5"
              onClick={() => {
                const preferences = {
                  mode: "system" as const,
                  lightTheme: { ...DEFAULT_LIGHT_THEME },
                  darkTheme: { ...DEFAULT_DARK_THEME },
                };
                setThemePreferences(preferences);
                saveThemePreferences(preferences);
                setEditingTheme(resolveThemeSlot(preferences.mode));
                setInterfaceZoom(DEFAULT_INTERFACE_ZOOM);
                saveInterfaceZoom(DEFAULT_INTERFACE_ZOOM);
                setNoteWidth(DEFAULT_NOTE_WIDTH);
                saveNoteWidth(DEFAULT_NOTE_WIDTH);
                setNoteAlignment(DEFAULT_NOTE_ALIGNMENT);
                saveNoteAlignment(DEFAULT_NOTE_ALIGNMENT);
                onHideSubtypeNotesChange(false);
              }}
            >
              <RotateCcw size={13} /> Reset to defaults
            </Button>
          </div>
          </TabsContent>
        </Tabs>
        </DialogContent>
      </Dialog>
      <AlertDialog
        open={cliInstallConfirmOpen}
        onOpenChange={setCliInstallConfirmOpen}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Install the Zerus CLI?</AlertDialogTitle>
            <AlertDialogDescription>
              To make your notes safely addressable from the command line,
              Zerus will add a hidden <code>zerus-id</code> property to
              {migrationPreview
                ? ` ${migrationPreview.idsAdded} ${migrationPreview.idsAdded === 1 ? "note" : "notes"}`
                : " your notes"}
              . This will not change how your notes look or work in the desktop
              app.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => void installCli(true)}>
              Install CLI
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog open={clearHistoryConfirmOpen} onOpenChange={setClearHistoryConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader><AlertDialogTitle>Clear all version history?</AlertDialogTitle><AlertDialogDescription>This permanently deletes automatic and kept versions for every note in this vault. Current notes and live images are not changed.</AlertDialogDescription></AlertDialogHeader>
          <AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction className="bg-destructive text-destructive-foreground" onClick={() => void clearVaultVersionHistory().then(() => setClearHistoryConfirmOpen(false))}>Clear all history</AlertDialogAction></AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
