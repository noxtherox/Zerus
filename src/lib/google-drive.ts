import { invoke } from "@tauri-apps/api/core";

export interface DriveAccount { accountId: string; email: string }
export interface DriveStatus { configured: boolean; account: DriveAccount | null }
export interface DriveRequest {
  path: string;
  method?: "GET" | "POST" | "PATCH" | "PUT";
  query?: Record<string, string>;
  body?: string;
  contentType?: string;
  ifMatch?: string;
}
export interface DriveResponse { status: number; body: string; etag?: string }
export type DriveTransport = (request: DriveRequest) => Promise<DriveResponse>;

export function driveCommand<T>(request: Record<string, unknown>): Promise<T> {
  return invoke<T>("plugin:mobile-vault|google_drive", { request });
}

export function driveTransport(accountId: string): DriveTransport {
  return (request) => driveCommand({ ...request, accountId, operation: "request" });
}

export function encodeDriveBytes(bytes: Uint8Array): string {
  let text = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(text);
}
export function decodeDriveBytes(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (char) => char.charCodeAt(0));
}
export function driveJSON(value: unknown): string {
  return encodeDriveBytes(new TextEncoder().encode(JSON.stringify(value)));
}
export class DriveError extends Error {
  constructor(public readonly status: number, message: string) { super(message); }
}
export async function driveFetch(transport: DriveTransport, request: DriveRequest): Promise<DriveResponse> {
  const response = await transport(request);
  if (response.status < 200 || response.status >= 300) {
    const message = response.status === 412
      ? "This file changed in Google Drive. Your edit was not uploaded. Copy your edit before reloading the vault."
      : response.status === 401 ? "Google Drive sign-in expired. Reconnect your account."
      : response.status === 403 ? "Google Drive denied access. Check folder permissions, storage space, and API limits."
      : response.status === 404 ? "This Google Drive file no longer exists or is no longer accessible."
      : response.status === 429 ? "Google Drive is busy. Wait a moment, then retry."
      : `Google Drive request failed (${response.status}). Retry when connected.`;
    throw new DriveError(response.status, message);
  }
  return response;
}
export function parseDriveJSON<T>(response: DriveResponse): T {
  return JSON.parse(new TextDecoder().decode(decodeDriveBytes(response.body))) as T;
}

export const DRIVE_FOLDER = "application/vnd.google-apps.folder";
export interface DriveFile {
  id: string; name: string; mimeType: string; parents?: string[];
  modifiedTime?: string; createdTime?: string; version?: string; trashed?: boolean;
  capabilities?: { canEdit?: boolean; canAddChildren?: boolean };
}
export const DRIVE_FIELDS = "id,name,mimeType,parents,modifiedTime,createdTime,version,trashed,capabilities(canEdit,canAddChildren)";
export function driveId(id: string): string {
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error("Invalid Google Drive file ID.");
  return id;
}
export async function listDriveChildren(transport: DriveTransport, parent: string): Promise<DriveFile[]> {
  const files: DriveFile[] = [];
  let pageToken: string | undefined;
  do {
    const page = parseDriveJSON<{ files: DriveFile[]; nextPageToken?: string }>(await driveFetch(transport, {
      path: "/drive/v3/files",
      query: { q: `'${driveId(parent)}' in parents and trashed = false`, fields: `nextPageToken,files(${DRIVE_FIELDS})`,
        pageSize: "1000", spaces: "drive", ...(pageToken ? { pageToken } : {}) },
    }));
    files.push(...page.files);
    pageToken = page.nextPageToken;
  } while (pageToken);
  return files;
}

export interface DriveVaultSelection extends DriveAccount { folderId: string; name: string }
const SELECTION_KEY = "zerus.google-drive.vault.v1";
export function savedDriveVault(): DriveVaultSelection | null {
  const value = localStorage.getItem(SELECTION_KEY);
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as DriveVaultSelection;
    if (![parsed.accountId, parsed.email, parsed.folderId, parsed.name].every((part) => typeof part === "string" && part.length > 0)) return null;
    driveId(parsed.folderId);
    return parsed;
  } catch { return null; }
}
export function saveDriveVault(value: DriveVaultSelection | null): void {
  if (value) localStorage.setItem(SELECTION_KEY, JSON.stringify(value));
  else localStorage.removeItem(SELECTION_KEY);
}
