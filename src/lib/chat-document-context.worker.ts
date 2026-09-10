import { selectDocumentContextCore } from "./chat-documents";

self.onmessage = async ({ data }: MessageEvent<Parameters<typeof selectDocumentContextCore>>) => {
  try {
    self.postMessage({ result: await selectDocumentContextCore(...data) });
  } catch (error) {
    self.postMessage({ error: String(error) });
  }
};
