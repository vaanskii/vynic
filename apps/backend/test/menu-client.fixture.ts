/** Current protocol fixture; no claim about an archived Windows binary. */
export const supportedMenuClient = {
  version: 1,
  capabilities: ['CANONICAL_MENU_V2'],
  appVersion: 'synthetic-compatible',
  buildNumber: 9,
};
export const supportedMenuClientHeader = JSON.stringify(supportedMenuClient);
