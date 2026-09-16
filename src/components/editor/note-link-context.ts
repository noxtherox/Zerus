import { createContext } from "react";

export const NoteLinkContext = createContext<(reference: string) => void>(() => {});
