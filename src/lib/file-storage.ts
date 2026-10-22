export type FileStorageMode = "copy" | "external" | "external-backup";

export type ChooseFileStorage = (
  fileName: string,
  canKeepExternal: boolean,
  purpose?: "create" | "attach" | "copy",
) => Promise<FileStorageMode | null>;
