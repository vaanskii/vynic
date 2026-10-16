import { json, urlencoded } from 'express';

/** Install before the general POS/webhook parsers, which accept larger bodies. */
export function websiteAuthBodyParsers() {
  return [
    json({ limit: '8kb' }),
    urlencoded({ extended: false, limit: '8kb', parameterLimit: 12 }),
  ];
}
