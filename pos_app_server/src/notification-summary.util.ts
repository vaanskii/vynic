/** Collapse duplicate lines and keep the latest service-fee on/off state. */
export function normalizeChangeSummary(raw: unknown): string {
  const text = typeof raw === 'string' ? raw.trim() : '';
  if (!text) return '';

  const unique: string[] = [];
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (!unique.includes(trimmed)) unique.push(trimmed);
  }
  if (unique.length === 0) return '';

  for (let i = unique.length - 1; i >= 0; i--) {
    const line = unique[i];
    if (line.includes('ჩართული') || line.includes('გამორთული')) {
      return line;
    }
  }
  return unique[unique.length - 1];
}

export function mergeChangeSummaries(
  a: unknown,
  b: unknown,
): string | undefined {
  const merged = normalizeChangeSummary(
    [normalizeChangeSummary(a), normalizeChangeSummary(b)]
      .filter((s) => s.length > 0)
      .join('\n'),
  );
  return merged.length > 0 ? merged : undefined;
}
