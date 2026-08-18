import { describe, expect, it } from "vitest";
import {
  getFileHubReference,
  isMarkdownFilePath,
  mostSpecificLocation,
  normalizeRelativeFilePath,
  parseFileLocations,
  pathInsideRoot,
  removeFileHubReference,
  resolveFileHubReference,
  serializeFileLocations,
  setFileHubReference,
  type FileHubReference,
} from "./file-hubs";

const locationReference: FileHubReference = {
  id: "file-1",
  name: "Proposal.docx",
  kind: "location",
  locationId: "company",
  path: "Clients/Acme/Proposal.docx",
  managed: false,
};

describe("file hub metadata", () => {
  it("only treats markdown extensions as editable notes", () => {
    expect(isMarkdownFilePath("/Users/me/Notes/Plan.md")).toBe(true);
    expect(isMarkdownFilePath("/Users/me/Notes/Plan.MARKDOWN")).toBe(true);
    expect(isMarkdownFilePath("/Users/me/Videos/demo.mp4")).toBe(false);
    expect(isMarkdownFilePath("/Users/me/Archive/data.bin")).toBe(false);
  });

  it("round-trips reserved flat frontmatter without changing the body", () => {
    const content = setFileHubReference("# Proposal\n\nNotes", locationReference);
    expect(content).toContain("zerus-file-kind: location");
    expect(content).toContain("zerus-file-path: Clients/Acme/Proposal.docx");
    expect(getFileHubReference(content)).toEqual(locationReference);
    expect(removeFileHubReference(content)).toBe("# Proposal\n\nNotes");
  });

  it("rejects unsafe relative paths", () => {
    expect(normalizeRelativeFilePath("Clients/Acme/file.pdf")).toBe("Clients/Acme/file.pdf");
    expect(normalizeRelativeFilePath("../secret.pdf")).toBeNull();
    expect(normalizeRelativeFilePath("/Users/me/file.pdf")).toBeNull();
    expect(normalizeRelativeFilePath("C:\\Users\\me\\file.pdf")).toBeNull();
  });
});

describe("portable file locations", () => {
  const locations = [
    { id: "drive", name: "OneDrive" },
    { id: "company", name: "Company" },
  ];

  it("chooses the most specific mapped base", () => {
    expect(
      mostSpecificLocation(
        "/Users/me/OneDrive/Company/Clients/Acme/Proposal.docx",
        locations,
        {
          drive: "/Users/me/OneDrive",
          company: "/Users/me/OneDrive/Company",
        },
      ),
    ).toEqual({
      location: locations[1],
      path: "Clients/Acme/Proposal.docx",
    });
  });

  it("resolves the same synced reference under different device roots", () => {
    const onMac = resolveFileHubReference(
      locationReference,
      "/Users/me/Vault",
      locations,
      { company: "/Users/me/Library/CloudStorage/Company" },
      {},
    );
    const onWindows = resolveFileHubReference(
      locationReference,
      "D:/Vault",
      locations,
      { company: "C:/Users/me/Company" },
      {},
    );
    expect(onMac.absolutePath).toBe(
      "/Users/me/Library/CloudStorage/Company/Clients/Acme/Proposal.docx",
    );
    expect(onWindows.absolutePath).toBe(
      "C:/Users/me/Company/Clients/Acme/Proposal.docx",
    );
  });

  it("uses a one-hub override before a missing location mapping", () => {
    const result = resolveFileHubReference(
      locationReference,
      null,
      locations,
      {},
      { "file-1": "/Volumes/Temporary/Proposal.docx" },
    );
    expect(result.absolutePath).toBe("/Volumes/Temporary/Proposal.docx");
    expect(result.missingMapping).toBe(false);
  });

  it("does not treat a sibling path as inside a root", () => {
    expect(pathInsideRoot("/Users/me/Drive", "/Users/me/Drive 2/file.pdf")).toBeNull();
  });

  it("validates the synced locations document", () => {
    const raw = serializeFileLocations(locations);
    expect(parseFileLocations(raw)).toEqual(locations);
    expect(parseFileLocations('{"version":2,"locations":[]}')).toEqual([]);
  });
});
