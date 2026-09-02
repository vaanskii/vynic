import {
  formatEnrollmentCode,
  generateEnrollmentCode,
  parseEnrollmentCode,
} from './enrollment-code';

describe('enrollment code', () => {
  it('generates a twelve-character code split into selector and secret', () => {
    for (let i = 0; i < 200; i++) {
      const code = generateEnrollmentCode();
      expect(code.normalized).toHaveLength(12);
      expect(code.selector).toHaveLength(4);
      expect(code.secret).toHaveLength(8);
      expect(code.selector + code.secret).toBe(code.normalized);
      // No I, L, O or U — the characters a human cannot read off a screen.
      expect(code.normalized).toMatch(/^[0-9A-HJKMNP-TV-Z]{12}$/);
    }
  });

  it('does not repeat itself', () => {
    const seen = new Set(
      Array.from({ length: 500 }, () => generateEnrollmentCode().normalized),
    );
    expect(seen.size).toBe(500);
  });

  it('reads what an operator actually types', () => {
    const canonical = parseEnrollmentCode('7K2QM4XB9TFR');
    expect(canonical?.normalized).toBe('7K2QM4XB9TFR');
    expect(canonical?.selector).toBe('7K2Q');
    expect(canonical?.secret).toBe('M4XB9TFR');

    for (const typed of [
      '7k2q-m4xb-9tfr',
      ' 7K2Q M4XB 9TFR ',
      '7K2Q_M4XB_9TFR',
    ]) {
      expect(parseEnrollmentCode(typed)?.normalized).toBe('7K2QM4XB9TFR');
    }
  });

  it('maps the characters people confuse rather than refusing them', () => {
    // I and L read as 1, O reads as 0 — none of them are in the alphabet, so
    // there is exactly one sensible reading of each.
    expect(parseEnrollmentCode('I1L1OO001111')?.normalized).toBe(
      '111100001111',
    );
  });

  it('refuses anything that cannot be a code', () => {
    expect(parseEnrollmentCode('')).toBeNull();
    expect(parseEnrollmentCode('7K2Q-M4XB')).toBeNull();
    expect(parseEnrollmentCode('7K2QM4XB9TFRX')).toBeNull();
    // U is excluded from the alphabet and is not mapped to anything.
    expect(parseEnrollmentCode('UUUUUUUUUUUU')).toBeNull();
    expect(parseEnrollmentCode('vynic-device-v1.aaa.bbb')).toBeNull();
  });

  it('shows a code in groups of four', () => {
    expect(formatEnrollmentCode('7K2QM4XB9TFR')).toBe('7K2Q-M4XB-9TFR');
  });
});
