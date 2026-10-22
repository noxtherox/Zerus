import { useCallback, useEffect, useRef, useState } from "react";
import type { FileStorageDialogProps } from "@/components/notes/FileStorageDialog";
import type { ChooseFileStorage, FileStorageMode } from "@/lib/file-storage";

export function useFileStorageChoice() {
  const [request, setRequest] = useState<FileStorageDialogProps["request"]>(null);
  const resolveChoice = useRef<((mode: FileStorageMode | null) => void) | null>(null);
  useEffect(() => () => {
    resolveChoice.current?.(null);
    resolveChoice.current = null;
  }, []);

  const chooseStorage: ChooseFileStorage = useCallback((fileName, canKeepExternal, purpose = "create") => {
    resolveChoice.current?.(null);
    return new Promise<FileStorageMode | null>((resolve) => {
      resolveChoice.current = resolve;
      setRequest({ fileName, canKeepExternal, purpose });
    });
  }, []);

  const onChoose = useCallback((mode: FileStorageMode | null) => {
    resolveChoice.current?.(mode);
    resolveChoice.current = null;
    setRequest(null);
  }, []);

  return { chooseStorage, storageDialogProps: { request, onChoose } };
}
