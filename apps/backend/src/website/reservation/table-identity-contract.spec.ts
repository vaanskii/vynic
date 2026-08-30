import { readFileSync } from 'fs';
import { join } from 'path';
import {
  canEncodeTableCode,
  decodeTableCode,
  encodeTableCode,
} from './reservation-table-codes';

/**
 * Golden compatibility tests for the table-identity contract.
 *
 * Reads the same fixture as the Dart suite in
 * `apps/operations/test/unit/table_identity_contract_test.dart`. One fixture,
 * two languages: that is what proves the two implementations agree, rather
 * than a comment asserting that they do.
 *
 * Written against the hand-written implementation before either side was
 * switched to the generated contract, so it pins existing behaviour rather
 * than describing intended behaviour.
 */

type EncodeCase = { floor: string; tableNumber: string; code: number };
type InvalidCase = { floor: string; tableNumber: string; why: string };
type DecodeCase = { code: number; floor: string; tableNumber: string };
type CanEncodeCase = { floor: string; tableNumber: string; expected: boolean };
type DivergenceCase = {
  floor: string;
  tableNumber: string;
  dart: string;
  typescript: number;
  risk: string;
};

const vectors = JSON.parse(
  readFileSync(
    join(
      __dirname,
      '../../../../../packages/contracts/schema/table-identity.vectors.json',
    ),
    'utf8',
  ),
) as {
  contractVersion: number;
  encode: { valid: EncodeCase[]; invalid: InvalidCase[] };
  decode: { cases: DecodeCase[] };
  canEncode: { cases: CanEncodeCase[] };
  legacyDivergence: { resolution: string; cases: DivergenceCase[] };
};

describe('table identity contract', () => {
  it('is the contract version this build expects', () => {
    expect(vectors.contractVersion).toBe(1);
  });

  describe('encodeTableCode', () => {
    it('encodes every valid vector to its recorded code', () => {
      for (const v of vectors.encode.valid) {
        expect(encodeTableCode(v.floor, v.tableNumber)).toBe(v.code);
      }
    });

    it('rejects every invalid vector rather than mis-encoding it', () => {
      for (const v of vectors.encode.invalid) {
        expect(() => encodeTableCode(v.floor, v.tableNumber)).toThrow();
      }
    });
  });

  describe('decodeTableCode', () => {
    it('decodes every vector to its recorded floor and table', () => {
      for (const v of vectors.decode.cases) {
        expect(decodeTableCode(v.code)).toEqual({
          floor: v.floor,
          tableNumber: v.tableNumber,
        });
      }
    });

    it('round-trips every valid encode vector', () => {
      for (const v of vectors.encode.valid) {
        expect(
          decodeTableCode(encodeTableCode(v.floor, v.tableNumber)),
        ).toEqual({ floor: v.floor, tableNumber: v.tableNumber.trim() });
      }
    });
  });

  describe('canEncodeTableCode', () => {
    it('decides bookability exactly as recorded', () => {
      for (const v of vectors.canEncode.cases) {
        expect(canEncodeTableCode(v.floor, v.tableNumber)).toBe(v.expected);
      }
    });

    it('agrees with encodeTableCode on every canEncode vector', () => {
      for (const v of vectors.canEncode.cases) {
        let encoded = true;
        try {
          encodeTableCode(v.floor, v.tableNumber);
        } catch {
          encoded = false;
        }
        expect(encoded).toBe(v.expected);
      }
    });
  });

  describe('legacy divergence', () => {
    it('no longer accepts the inputs the hand-written version mis-encoded', () => {
      // Before the shared contract these inputs returned a number here while
      // Dart threw — the two implementations had already drifted apart. The
      // contract converges on the strict side. Nothing reachable changes: all
      // six call sites pass WebsiteTable.posFloor / posTableNumber, and the
      // only writer of those columns seeds first floor 1-10 and second 1-4.
      expect(vectors.legacyDivergence.resolution).toBe('strict');
      for (const v of vectors.legacyDivergence.cases) {
        expect(() => encodeTableCode(v.floor, v.tableNumber)).toThrow();
      }
    });
  });

  describe('the real seeded table set is unaffected', () => {
    // The complete domain of live inputs, from WEBSITE_TABLE_MAPPINGS.
    const seeded = [
      ...Array.from({ length: 10 }, (_, i) => ({
        posFloor: 'first',
        posTableNumber: String(i + 1),
      })),
      ...Array.from({ length: 4 }, (_, i) => ({
        posFloor: 'second',
        posTableNumber: String(i + 1),
      })),
    ];

    it('encodes all 14 seeded tables to the codes they have always had', () => {
      const codes = seeded.map((t) =>
        encodeTableCode(t.posFloor, t.posTableNumber),
      );
      expect(codes).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
    });

    it('round-trips every seeded table back to itself', () => {
      for (const t of seeded) {
        const decoded = decodeTableCode(
          encodeTableCode(t.posFloor, t.posTableNumber),
        );
        expect(decoded).toEqual({
          floor: t.posFloor,
          tableNumber: t.posTableNumber,
        });
      }
    });
  });
});
