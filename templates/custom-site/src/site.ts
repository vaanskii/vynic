import { createWebsiteClient, createWebsiteHooks } from "@vynic/website-client";
import { useEffect, useState } from "react";

/**
 * This frontend's identity. Must equal the "Custom frontend identity" the
 * operator records for the Venue in Platform Admin; conventionally the app
 * directory name (`apps/restaurant-x-web` → `restaurant-x-web`).
 *
 * `VITE_SITE_KEY` exists only so the template can be exercised against the
 * local fixture Venues; a real client app should hardcode its key.
 */
export const SITE_KEY: string =
  import.meta.env.VITE_SITE_KEY || "custom-site-template";

export const client = createWebsiteClient();
export const hooks = createWebsiteHooks({ useState, useEffect }, client);
