import { ClientSettingsSchema, type ClientSettings } from "@backplane/contracts";

import { getLocalStorageItem, setLocalStorageItem } from "./hooks/useLocalStorage";

const CLIENT_SETTINGS_STORAGE_KEY = "backplane:client-settings:v1";

function hasWindow(): boolean {
  return typeof window !== "undefined";
}

export function readBrowserClientSettings(): ClientSettings | null {
  if (!hasWindow()) {
    return null;
  }

  return getLocalStorageItem(CLIENT_SETTINGS_STORAGE_KEY, ClientSettingsSchema);
}

export function writeBrowserClientSettings(settings: ClientSettings): void {
  if (!hasWindow()) {
    return;
  }

  setLocalStorageItem(CLIENT_SETTINGS_STORAGE_KEY, settings, ClientSettingsSchema);
}
