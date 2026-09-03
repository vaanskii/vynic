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
const EDGE_SCHEMA = join(PKG, 'schema', 'edge-command.contract.json');

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

// The Cloud <-> Edge envelope renders both languages since Step 6B, when the
// POS gained an Edge client that claims and acknowledges work.
const EDGE_TS_OUT = join(PKG, 'generated', 'typescript', 'edge-command.ts');
const EDGE_TS_APP_OUT = join(
  REPO,
  'apps',
  'backend',
  'src',
  'shared',
  'contracts',
  'edge-command.ts',
);
const EDGE_DART_OUT = join(PKG, 'generated', 'dart', 'edge_command.dart');
const EDGE_DART_APP_OUT = join(
  REPO,
  'apps',
  'operations',
  'lib',
  'core',
  'contracts',
  'edge_command.dart',
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

// ── Cloud ↔ Edge command envelope ────────────────────────────────────────────

const edgeContract = JSON.parse(readFileSync(EDGE_SCHEMA, 'utf8'));
const edgeSchemaRel = relative(REPO, EDGE_SCHEMA).replaceAll('\\', '/');

function edgeBanner() {
  return [
    '// GENERATED FILE — DO NOT EDIT.',
    '//',
    `// Rendered from ${edgeSchemaRel}`,
    '// by packages/contracts/scripts/generate.mjs.',
    '//',
    '// Change the schema and regenerate; edits here are overwritten and',
    '// CI fails on a stale or hand-edited output.',
  ].join('\n');
}

/** Renders one command type's schema entry as a doc comment. */
function edgeTypeDoc(c, indent) {
  const lines = [c.description];
  if (c.idempotency) lines.push('', `Idempotency: ${c.idempotency}`);
  const fields = Object.entries(c.payload ?? {});
  if (fields.length > 0) {
    lines.push('', 'Payload:');
    for (const [name, shape] of fields) lines.push(`- \`${name}\`: ${shape}`);
  } else {
    lines.push('', 'Payload: none.');
  }
  if (c.failure) lines.push('', `Failure: ${c.failure}`);
  if (c.repeatAfterInterruption === false) {
    lines.push(
      '',
      'Not repeated after an interrupted execution: the outcome is unknown and',
      'repeating it would be worse than reporting it.',
    );
  }
  const pad = ' '.repeat(indent);
  return [
    `${pad}/**`,
    ...lines.map((l) => (l ? `${pad} * ${l}` : `${pad} *`)),
    `${pad} */`,
  ].join('\n');
}

function renderEdgeTs() {
  const {
    contractVersion,
    compatibleContractVersions,
    limits,
    resultStatuses,
    commandTypes,
  } = edgeContract;
  const compatible = compatibleContractVersions ?? [contractVersion];
  // One member per line, prettier's own shape for a union this long, so the
  // generated file is not something the formatter wants to rewrite.
  const typeUnion =
    '\n  | ' + commandTypes.map((c) => `'${c.type}'`).join('\n  | ');
  const typeConsts = commandTypes
    .map((c) => `${edgeTypeDoc(c, 2)}\n  ${c.type}: '${c.type}',`)
    .join('\n\n');
  const idempotentSet = commandTypes
    .filter((c) => c.idempotent)
    .map((c) => `  '${c.type}',`)
    .join('\n');
  const noRepeatSet = commandTypes
    .filter((c) => c.repeatAfterInterruption === false)
    .map((c) => `  '${c.type}',`)
    .join('\n');
  const resultUnion = resultStatuses.map((r) => `'${r}'`).join(' | ');

  return `${edgeBanner()}

/**
 * The Cloud → Edge work contract.
 *
 * Cloud cannot reach a restaurant's LAN, so the Edge opens the connection with
 * its Device credential, claims work, executes it locally, and reports the
 * outcome. Delivery is at-least-once: a claim is a lease, and a lease that
 * expires unacknowledged is offered again. Every command type must therefore be
 * safe to execute twice, which is what \`EDGE_IDEMPOTENT_COMMAND_TYPES\` records.
 *
 * The version travels on every envelope so an Edge running an older build can
 * decline work it does not understand rather than guessing at it.
 */
export const EDGE_COMMAND_CONTRACT_VERSION = ${contractVersion};

/** Batch size the Edge gets when it asks for none, and the ceiling it cannot exceed. */
export const EDGE_COMMAND_DEFAULT_BATCH_SIZE = ${limits.defaultBatchSize};
export const EDGE_COMMAND_MAX_BATCH_SIZE = ${limits.maxBatchSize};

/** How long a claimed command stays leased before it becomes available again. */
export const EDGE_COMMAND_CLAIM_LEASE_SECONDS = ${limits.claimLeaseSeconds};

/** Redeliveries before a command is given up on and recorded as failed. */
export const EDGE_COMMAND_MAX_ATTEMPTS = ${limits.maxAttempts};

/**
 * Every envelope version an up-to-date Edge understands, newest first.
 *
 * A fleet does not upgrade all at once, so Cloud has to be able to serve the
 * version before this one while builds catch up. An Edge sends this list on
 * every claim and Cloud withholds anything outside it.
 */
export const EDGE_COMMAND_COMPATIBLE_VERSIONS: readonly number[] = [${compatible.join(', ')}];

export const EdgeCommandTypes = {
${typeConsts}
} as const;

export type EdgeCommandType =${typeUnion};

/**
 * Command types that may be executed more than once without extra effect.
 *
 * A type absent from this set must not be enqueued until its Edge handler
 * carries its own idempotency, because at-least-once delivery will eventually
 * hand it over twice.
 */
export const EDGE_IDEMPOTENT_COMMAND_TYPES: ReadonlySet<string> = new Set([
${idempotentSet}
]);

/**
 * Types whose Edge handler must NOT re-run after an interrupted execution.
 *
 * These are the ones whose side effect leaves the machine — paper, mostly. A
 * command the POS started and never finished has an unknown outcome, and
 * quietly doing it again is worse than reporting that nobody knows.
 */
export const EDGE_NO_REPEAT_AFTER_INTERRUPTION: ReadonlySet<string> = new Set([
${noRepeatSet}
]);

export type EdgeCommandResultStatus = ${resultUnion};

/** One unit of work, as the Edge receives it. */
export interface EdgeCommandEnvelope {
  contractVersion: number;
  commandId: string;
  type: string;
  payload: unknown;
  /** Stable per Venue: the same intent enqueued twice is the same command. */
  idempotencyKey: string;
  /** How many times this command has been handed out, this delivery included. */
  attempt: number;
  issuedAt: string;
  /** After this instant the command may be offered to an Edge again. */
  leaseExpiresAt: string;
}

/** What the Edge reports back once it has executed — or failed to execute — a command. */
export interface EdgeCommandResult {
  contractVersion: number;
  commandId: string;
  status: EdgeCommandResultStatus;
  /** Short machine-readable outcome, e.g. \`printer_offline\`. */
  code?: string | null;
  detail?: string | null;
}
`;
}

/** Renders one command type's schema entry as a Dart doc comment. */
function edgeTypeDartDoc(c, indent) {
  const lines = [c.description];
  if (c.idempotency) lines.push('', `Idempotency: ${c.idempotency}`);
  const fields = Object.entries(c.payload ?? {});
  if (fields.length > 0) {
    lines.push('', 'Payload:');
    for (const [name, shape] of fields) lines.push(`- \`${name}\`: ${shape}`);
  } else {
    lines.push('', 'Payload: none.');
  }
  if (c.failure) lines.push('', `Failure: ${c.failure}`);
  if (c.repeatAfterInterruption === false) {
    lines.push(
      '',
      'Not repeated after an interrupted execution: the outcome is unknown and',
      'repeating it would be worse than reporting it.',
    );
  }
  const pad = ' '.repeat(indent);
  return lines.map((l) => (l ? `${pad}/// ${l}` : `${pad}///`)).join('\n');
}

/** camelCase Dart identifier for a SCREAMING_SNAKE contract type. */
function dartTypeName(type) {
  const [head, ...rest] = type.toLowerCase().split('_');
  return head + rest.map((w) => w[0].toUpperCase() + w.slice(1)).join('');
}

function renderEdgeDart() {
  const {
    contractVersion,
    compatibleContractVersions,
    limits,
    resultStatuses,
    commandTypes,
  } = edgeContract;
  const compatible = compatibleContractVersions ?? [contractVersion];
  const typeConsts = commandTypes
    .map(
      (c) =>
        `${edgeTypeDartDoc(c, 2)}\n  static const String ${dartTypeName(c.type)} = '${c.type}';`,
    )
    .join('\n\n');
  // Rendered one per line: dart format would otherwise rewrite a long set
  // literal, and a generated file that the formatter wants to change is a
  // generated file --check reports as stale on every developer's machine.
  const dartSet = (types) =>
    types.map((c) => `    '${c.type}',`).join('\n');
  const allTypes = dartSet(commandTypes);
  const idempotent = dartSet(commandTypes.filter((c) => c.idempotent));
  const noRepeat = dartSet(
    commandTypes.filter((c) => c.repeatAfterInterruption === false),
  );
  const resultConsts = resultStatuses
    .map((r) => `  static const String ${r.toLowerCase()} = '${r}';`)
    .join('\n');

  return `${edgeBanner()}

/// The Cloud → Edge work contract, as the POS sees it.
///
/// Cloud cannot reach a restaurant's LAN, so the Edge opens the connection with
/// its Device credential, claims work, executes it locally, and reports the
/// outcome. Delivery is at-least-once: a claim is a lease, and a lease that
/// expires unacknowledged is offered again, so every command type must be safe
/// to execute twice.
library;

/// The envelope version this build speaks. Sent on every claim so Cloud
/// withholds work this POS would not understand.
const int edgeCommandContractVersion = ${contractVersion};

/// Batch size requested when none is given, and the ceiling Cloud enforces.
const int edgeCommandDefaultBatchSize = ${limits.defaultBatchSize};
const int edgeCommandMaxBatchSize = ${limits.maxBatchSize};

/// How long a claimed command stays leased before Cloud offers it again.
const int edgeCommandClaimLeaseSeconds = ${limits.claimLeaseSeconds};

/// Redeliveries before Cloud gives up on a command.
const int edgeCommandMaxAttempts = ${limits.maxAttempts};

/// Every envelope version this build understands, newest first.
///
/// A fleet does not upgrade all at once, so an Edge has to keep accepting the
/// version before its own while Cloud still holds work enqueued under it. Sent
/// on every claim; Cloud withholds anything outside this list.
const List<int> edgeCommandCompatibleVersions = <int>[${compatible.join(', ')}];

/// Every command type this contract version defines.
class EdgeCommandTypes {
  EdgeCommandTypes._();

${typeConsts}

  static const Set<String> all = <String>{
${allTypes}
  };

  /// Types safe to execute more than once.
  ///
  /// A type absent from this set must not be executed on redelivery without a
  /// handler-specific idempotency boundary of its own.
  static const Set<String> idempotent = <String>{
${idempotent}
  };

  /// Types that must NOT be re-run after an interrupted execution.
  ///
  /// These are the ones whose side effect leaves the machine — paper, mostly.
  /// A command the POS started and never finished has an unknown outcome, and
  /// quietly doing it again is worse than reporting that nobody knows.
  static const Set<String> noRepeatAfterInterruption = <String>{
${noRepeat}
  };
}

/// What the Edge may report back about a command.
class EdgeCommandResultStatus {
  EdgeCommandResultStatus._();

${resultConsts}
}

/// One unit of work, as the Edge receives it.
class EdgeCommandEnvelope {
  const EdgeCommandEnvelope({
    required this.contractVersion,
    required this.commandId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    required this.attempt,
    required this.issuedAt,
    required this.leaseExpiresAt,
  });

  final int contractVersion;
  final String commandId;
  final String type;
  final Object? payload;

  /// Stable per Venue: the same intent enqueued twice is the same command.
  final String idempotencyKey;

  /// How many times this command has been handed out, this delivery included.
  final int attempt;
  final DateTime issuedAt;

  /// After this instant Cloud may offer the command to an Edge again.
  final DateTime leaseExpiresAt;

  /// Whether this build understands the envelope well enough to execute it.
  bool get isSupportedVersion =>
      edgeCommandCompatibleVersions.contains(contractVersion);

  /// Parses one envelope, or throws [FormatException] on a malformed one.
  ///
  /// Deliberately strict about the fields the transport depends on: a command
  /// without an id or a type cannot be acknowledged, and silently defaulting
  /// either would lose work rather than report it.
  factory EdgeCommandEnvelope.fromJson(Map<String, dynamic> json) {
    final commandId = json['commandId'];
    final type = json['type'];
    if (commandId is! String || commandId.isEmpty) {
      throw const FormatException('Edge command is missing commandId');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('Edge command is missing type');
    }
    return EdgeCommandEnvelope(
      contractVersion: _asInt(json['contractVersion'], 0),
      commandId: commandId,
      type: type,
      payload: json['payload'],
      idempotencyKey: json['idempotencyKey'] is String
          ? json['idempotencyKey'] as String
          : '',
      attempt: _asInt(json['attempt'], 1),
      issuedAt: _asTime(json['issuedAt']),
      leaseExpiresAt: _asTime(json['leaseExpiresAt']),
    );
  }
}

/// What the Edge sends back once it has executed — or failed to execute — one.
class EdgeCommandResult {
  const EdgeCommandResult({
    required this.commandId,
    required this.status,
    this.code,
    this.detail,
  });

  const EdgeCommandResult.succeeded(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.succeeded;

  const EdgeCommandResult.failed(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.failed;

  final String commandId;
  final String status;

  /// Short machine-readable outcome, e.g. \`printer_offline\`.
  final String? code;
  final String? detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contractVersion': edgeCommandContractVersion,
    'commandId': commandId,
    'status': status,
    if (code != null) 'code': code,
    if (detail != null) 'detail': detail,
  };
}

int _asInt(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

DateTime _asTime(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
`;
}

// ── Emit ─────────────────────────────────────────────────────────────────────

const dart = renderDart();
const ts = renderTs();
const edgeTs = renderEdgeTs();
const edgeDart = renderEdgeDart();

const outputs = [
  { path: DART_OUT, body: dart },
  { path: DART_APP_OUT, body: dart },
  { path: TS_OUT, body: ts },
  { path: TS_APP_OUT, body: ts },
  { path: EDGE_TS_OUT, body: edgeTs },
  { path: EDGE_TS_APP_OUT, body: edgeTs },
  { path: EDGE_DART_OUT, body: edgeDart },
  { path: EDGE_DART_APP_OUT, body: edgeDart },
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
