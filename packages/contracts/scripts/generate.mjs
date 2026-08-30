#!/usr/bin/env node
/**
 * Renders the Dart and TypeScript table-identity implementations from
 * packages/contracts/schema/table-identity.contract.json.
 *
 *   node packages/contracts/scripts/generate.mjs           write the outputs
 *   node packages/contracts/scripts/generate.mjs --check    fail if stale
 *
 * `--check` is what CI runs: it regenerates in memory and exits non-zero if
 * the committed output differs, so an edit to a generated file or a change to
 * the schema without regenerating is caught rather than merged.
 *
 * Deliberately dependency-free. Node's standard library only, so there is no
 * install step, no lockfile, and nothing to keep up to date. The encoding is a
 * short algorithm, not a message shape, so a schema language that emits data
 * classes (JSON Schema, OpenAPI, Protobuf) could not express it — what varies
 * between versions of this contract is the floor vocabulary and the bounds,
 * and those are exactly what the schema holds and the templates below read.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PKG = join(HERE, '..');
const REPO = join(PKG, '..', '..');

const SCHEMA = join(PKG, 'schema', 'table-identity.contract.json');

// The canonical rendered artefacts.
const DART_OUT = join(PKG, 'generated', 'dart', 'table_identity.dart');
const TS_OUT = join(PKG, 'generated', 'typescript', 'table-identity.ts');

// Byte-identical copies inside each app, because neither toolchain can reach
// outside its own package without a change we do not want to make: Dart would
// need a path dependency in pubspec.yaml, and an import above the server's
// sources would move tsc's inferred rootDir to the repo root, relocating
// dist/src/main.js and breaking `npm run start:prod`. All four files are
// rendered from the one schema and all four are validated by --check, so they
// cannot drift; the source of truth is still the schema alone.
const DART_APP_OUT = join(
  REPO,
  'apps',
  'operations',
  'lib',
  'core',
  'contracts',
  'table_identity.dart',
);
const TS_APP_OUT = join(
  REPO,
  'apps',
  'backend',
  'src',
  'shared',
  'contracts',
  'table-identity.ts',
);

const contract = JSON.parse(readFileSync(SCHEMA, 'utf8'));
const { contractVersion, canonicalTableId, tableRef, legacyTableCode } = contract;
if (canonicalTableId?.format !== 'uuid') {
  throw new Error('canonicalTableId.format must be "uuid"');
}
const { separator } = tableRef;
const { minTableNumber, floors } = legacyTableCode;

const schemaRel = relative(REPO, SCHEMA).replaceAll('\\', '/');

/** Floors ordered high offset first — decode picks the first one the code clears. */
const byOffsetDesc = [...floors].sort((a, b) => b.offset - a.offset);
const lowest = byOffsetDesc[byOffsetDesc.length - 1];

function banner(lineComment) {
  return [
    `${lineComment} GENERATED FILE — DO NOT EDIT.`,
    `${lineComment}`,
    `${lineComment} Rendered from ${schemaRel}`,
    `${lineComment} by packages/contracts/scripts/generate.mjs.`,
    `${lineComment}`,
    `${lineComment} Change the schema and regenerate; edits here are overwritten and`,
    `${lineComment} CI fails on a stale or hand-edited output.`,
  ].join('\n');
}

// ── Dart ─────────────────────────────────────────────────────────────────────

function dartFloorConst(f) {
  const max = f.maxTableNumber === null ? 'null' : String(f.maxTableNumber);
  return `  _Floor(key: '${f.key}', offset: ${f.offset}, maxTableNumber: ${max}),`;
}

function renderDart() {
  const decodeBranches = byOffsetDesc
    .filter((f) => f !== lowest)
    .map(
      (f) =>
        `    if (code > ${f.offset}) {\n` +
        `      return (floor: '${f.key}', tableNumber: '\${code - ${f.offset}}');\n` +
        `    }`,
    )
    .join('\n');

  return `${banner('//')}

/// Table identity: immutable UUIDs plus the compatibility [encodeTableRef]
/// and transitional integer [encodeTableCode] forms shared with apps/backend.
library;

const int tableIdentityContractVersion = ${contractVersion};

/// Immutable identity of one physical table.
typedef CanonicalTableId = String;

/// Transitional reservation-era integer identity.
typedef LegacyTableCode = int;

/// Lossless floor/number compatibility reference.
typedef TableRef = String;

final RegExp _canonicalTableIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\$',
);

/// Whether [raw] is a canonical RFC 4122 UUID string.
bool isCanonicalTableId(String raw) => _canonicalTableIdPattern.hasMatch(raw);

/// Separator between the floor key and the table number in a table ref.
const String tableRefSeparator = '${separator}';

class _Floor {
  const _Floor({
    required this.key,
    required this.offset,
    required this.maxTableNumber,
  });

  final String key;
  final int offset;
  final int? maxTableNumber;
}

const List<_Floor> _floors = [
${floors.map(dartFloorConst).join('\n')}
];

const int _minTableNumber = ${minTableNumber};

_Floor? _floorByKey(String key) {
  for (final floor in _floors) {
    if (floor.key == key) return floor;
  }
  return null;
}

/// The parsed table number, or null when [raw] is not a whole number at or
/// above the minimum.
int? _parseTableNumber(String raw) {
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < _minTableNumber) return null;
  return parsed;
}

/// Whether [floor] and [tableNumber] can be represented as a legacy code.
///
/// Pickers must hide tables that fail this check rather than offering them,
/// because [encodeTableCode] throws for exactly the same inputs.
bool canEncodeTableCode({
  required String floor,
  required String tableNumber,
}) {
  final parsed = _parseTableNumber(tableNumber);
  if (parsed == null) return false;
  final target = _floorByKey(floor);
  if (target == null) return false;
  final max = target.maxTableNumber;
  return max == null || parsed <= max;
}

/// Encodes [floor] and [tableNumber] into the legacy integer code.
///
/// Throws [ArgumentError] rather than returning a code that would decode as a
/// different table.
int encodeTableCode({required String floor, required String tableNumber}) {
  final parsed = _parseTableNumber(tableNumber);
  if (parsed == null) {
    throw ArgumentError('Invalid table number: \$tableNumber');
  }
  final target = _floorByKey(floor);
  if (target == null) {
    throw ArgumentError(
      'Floor "\$floor" cannot be encoded as a reservation table code; '
      'only \${_floors.map((f) => f.key).join('/')} are supported',
    );
  }
  final max = target.maxTableNumber;
  if (max != null && parsed > max) {
    throw ArgumentError(
      'Table \$parsed on the \$floor floor cannot be encoded as a '
      'reservation table code (would decode as another floor\\'s table)',
    );
  }
  return parsed + target.offset;
}

/// Decodes a legacy integer code back into a floor and table number.
///
/// Total by design: it validates nothing, so every code — including ones
/// [encodeTableCode] would never produce — maps somewhere, exactly as the
/// hand-written implementations did.
({String floor, String tableNumber}) decodeTableCode(int code) {
${decodeBranches}
    return (floor: '${lowest.key}', tableNumber: '\${code - ${lowest.offset}}');
}

/// A lossless compatibility reference: \`floor\${tableRefSeparator}tableNumber\`.
String encodeTableRef({required String floor, required String tableNumber}) {
  return '\$floor\$tableRefSeparator\$tableNumber';
}

/// Parses [raw] back into a floor and table number, or null when malformed.
///
/// Splits on the FIRST separator only: floor keys never contain it, so any
/// later occurrence belongs to the table number.
({String floor, String tableNumber})? tryDecodeTableRef(String raw) {
  final separator = raw.indexOf(tableRefSeparator);
  if (separator <= 0 || separator >= raw.length - 1) {
    return null;
  }
  final floor = raw.substring(0, separator).trim();
  final tableNumber = raw.substring(separator + 1).trim();
  if (floor.isEmpty || tableNumber.isEmpty) {
    return null;
  }
  return (floor: floor, tableNumber: tableNumber);
}
`;
}

// ── TypeScript ───────────────────────────────────────────────────────────────

function tsFloorConst(f) {
  const max = f.maxTableNumber === null ? 'null' : String(f.maxTableNumber);
  return `  { key: '${f.key}', offset: ${f.offset}, maxTableNumber: ${max} },`;
}

function renderTs() {
  const decodeBranches = byOffsetDesc
    .filter((f) => f !== lowest)
    .map(
      (f) =>
        `  if (code > ${f.offset}) {\n` +
        `    return { floor: '${f.key}', tableNumber: String(code - ${f.offset}) };\n` +
        `  }`,
    )
    .join('\n');

  return `${banner('//')}

/**
 * Table identity: immutable UUIDs plus the compatibility \`encodeTableRef\`
 * and transitional integer \`encodeTableCode\` forms shared with apps/operations.
 */

export const TABLE_IDENTITY_CONTRACT_VERSION = ${contractVersion};

/** Immutable identity of one physical table. */
export type CanonicalTableId = string;

/** Transitional reservation-era integer identity. */
export type LegacyTableCode = number;

/** Lossless floor/number compatibility reference. */
export type TableRef = string;

const CANONICAL_TABLE_ID_PATTERN =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** Whether \`raw\` is a canonical RFC 4122 UUID string. */
export function isCanonicalTableId(raw: string): raw is CanonicalTableId {
  return CANONICAL_TABLE_ID_PATTERN.test(raw);
}

/** Separator between the floor key and the table number in a table ref. */
export const TABLE_REF_SEPARATOR = '${separator}';

interface Floor {
  key: string;
  offset: number;
  maxTableNumber: number | null;
}

const FLOORS: readonly Floor[] = [
${floors.map(tsFloorConst).join('\n')}
];

const MIN_TABLE_NUMBER = ${minTableNumber};

function floorByKey(key: string): Floor | undefined {
  return FLOORS.find((floor) => floor.key === key);
}

/**
 * The parsed table number, or null when \`raw\` is not a whole number at or
 * above the minimum. Matches Dart's int.tryParse: an optional sign followed
 * by digits and nothing else, so "5abc" is rejected rather than read as 5.
 */
function parseTableNumber(raw: string): number | null {
  const trimmed = raw.trim();
  if (!/^[+-]?\\d+$/.test(trimmed)) return null;
  const parsed = Number.parseInt(trimmed, 10);
  if (!Number.isFinite(parsed) || parsed < MIN_TABLE_NUMBER) return null;
  return parsed;
}

/**
 * Whether \`floor\` and \`tableNumber\` can be represented as a legacy code.
 *
 * Pickers must hide tables that fail this check rather than offering them,
 * because \`encodeTableCode\` throws for exactly the same inputs.
 */
export function canEncodeTableCode(
  floor: string,
  tableNumber: string,
): boolean {
  const parsed = parseTableNumber(tableNumber);
  if (parsed === null) return false;
  const target = floorByKey(floor);
  if (!target) return false;
  return target.maxTableNumber === null || parsed <= target.maxTableNumber;
}

/**
 * Encodes \`floor\` and \`tableNumber\` into the legacy integer code.
 *
 * Throws rather than returning a code that would decode as a different table.
 */
export function encodeTableCode(floor: string, tableNumber: string): number {
  const parsed = parseTableNumber(tableNumber);
  if (parsed === null) {
    throw new Error(\`Invalid table number: \${tableNumber}\`);
  }
  const target = floorByKey(floor);
  if (!target) {
    throw new Error(
      \`Floor "\${floor}" cannot be encoded as a reservation table code; \` +
        \`only \${FLOORS.map((f) => f.key).join('/')} are supported\`,
    );
  }
  if (target.maxTableNumber !== null && parsed > target.maxTableNumber) {
    throw new Error(
      \`Table \${parsed} on the \${floor} floor cannot be encoded as a \` +
        \`reservation table code (would decode as another floor's table)\`,
    );
  }
  return parsed + target.offset;
}

/**
 * Decodes a legacy integer code back into a floor and table number.
 *
 * Total by design: it validates nothing, so every code — including ones
 * \`encodeTableCode\` would never produce — maps somewhere, exactly as the
 * hand-written implementations did.
 */
export function decodeTableCode(code: number): {
  floor: string;
  tableNumber: string;
} {
${decodeBranches}
  return { floor: '${lowest.key}', tableNumber: String(code - ${lowest.offset}) };
}

/** A lossless compatibility reference: \`floor\${TABLE_REF_SEPARATOR}tableNumber\`. */
export function encodeTableRef(floor: string, tableNumber: string): string {
  return \`\${floor}\${TABLE_REF_SEPARATOR}\${tableNumber}\`;
}

/**
 * Parses \`raw\` back into a floor and table number, or null when malformed.
 *
 * Splits on the FIRST separator only: floor keys never contain it, so any
 * later occurrence belongs to the table number.
 */
export function tryDecodeTableRef(
  raw: string,
): { floor: string; tableNumber: string } | null {
  const separator = raw.indexOf(TABLE_REF_SEPARATOR);
  if (separator <= 0 || separator >= raw.length - 1) {
    return null;
  }
  const floor = raw.slice(0, separator).trim();
  const tableNumber = raw.slice(separator + 1).trim();
  if (floor.length === 0 || tableNumber.length === 0) {
    return null;
  }
  return { floor, tableNumber };
}
`;
}

// ── Emit ─────────────────────────────────────────────────────────────────────

const dart = renderDart();
const ts = renderTs();

const outputs = [
  { path: DART_OUT, body: dart },
  { path: DART_APP_OUT, body: dart },
  { path: TS_OUT, body: ts },
  { path: TS_APP_OUT, body: ts },
];

const check = process.argv.includes('--check');
let stale = 0;

for (const { path, body } of outputs) {
  const rel = relative(REPO, path).replaceAll('\\', '/');
  if (check) {
    let current = null;
    try {
      current = readFileSync(path, 'utf8');
    } catch {
      current = null;
    }
    if (current !== body) {
      console.error(`stale: ${rel}`);
      stale += 1;
    } else {
      console.log(`ok:    ${rel}`);
    }
  } else {
    writeFileSync(path, body);
    console.log(`wrote: ${rel}`);
  }
}

if (check && stale > 0) {
  console.error(
    `\n${stale} generated file(s) do not match the schema. ` +
      `Run: node packages/contracts/scripts/generate.mjs`,
  );
  process.exit(1);
}
