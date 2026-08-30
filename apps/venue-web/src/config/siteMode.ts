/**
 * Coming-soon mode limits the public site to the home page and shows a
 * construction notice. Enabled in production builds by default; set
 * VITE_COMING_SOON=false when you are ready to launch.
 */
export const isComingSoonMode =
  import.meta.env.VITE_COMING_SOON === 'true' ||
  (import.meta.env.PROD && import.meta.env.VITE_COMING_SOON !== 'false');
