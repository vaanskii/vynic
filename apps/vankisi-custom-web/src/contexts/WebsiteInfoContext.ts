import { createContext, useContext } from "react";
import type { WebsiteInfoState } from "../services/website-info";

export const websiteInfoContext = createContext<
  { state: WebsiteInfoState; reload: () => void } | undefined
>(undefined);
export function useWebsiteInfo() {
  const value = useContext(websiteInfoContext);
  if (!value) throw new Error("WebsiteInfoProvider is required");
  return value;
}
