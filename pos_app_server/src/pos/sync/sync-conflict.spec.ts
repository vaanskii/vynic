import {
  parseDate,
  posWinsOrderConflict,
  pendingStaffUsernames,
} from './sync-conflict';

describe('parseDate', () => {
  it('parses a valid ISO string', () => {
    const d = parseDate('2026-06-27T10:00:00.000Z');
    expect(d).toBeInstanceOf(Date);
    expect(d?.toISOString()).toBe('2026-06-27T10:00:00.000Z');
  });

  it('returns null for missing / empty / non-string input', () => {
    expect(parseDate(undefined)).toBeNull();
    expect(parseDate(null)).toBeNull();
    expect(parseDate('')).toBeNull();
    expect(parseDate('   ')).toBeNull();
    expect(parseDate(123)).toBeNull();
  });

  it('returns null for an unparseable string', () => {
    expect(parseDate('not-a-date')).toBeNull();
  });
});

describe('posWinsOrderConflict (last-write-wins)', () => {
  const manager = new Date('2026-06-27T10:00:00.000Z');

  it('POS wins when its edit is strictly newer than the queued mobile edit', () => {
    const posNewer = '2026-06-27T10:00:05.000Z';
    expect(posWinsOrderConflict(posNewer, manager)).toBe(true);
  });

  it('mobile wins when the queued edit is newer than the POS edit', () => {
    const posOlder = '2026-06-27T09:59:55.000Z';
    expect(posWinsOrderConflict(posOlder, manager)).toBe(false);
  });

  it('mobile wins on an exact tie (POS only wins strictly-newer)', () => {
    const posSame = manager.toISOString();
    expect(posWinsOrderConflict(posSame, manager)).toBe(false);
  });

  it('mobile wins when the POS sent no timestamp (legacy / backwards-compatible)', () => {
    expect(posWinsOrderConflict(undefined, manager)).toBe(false);
    expect(posWinsOrderConflict('', manager)).toBe(false);
    expect(posWinsOrderConflict('garbage', manager)).toBe(false);
  });

  it('mobile wins when there is no recorded manager edit time', () => {
    expect(posWinsOrderConflict('2026-06-27T10:00:05.000Z', undefined)).toBe(
      false,
    );
    expect(posWinsOrderConflict('2026-06-27T10:00:05.000Z', null)).toBe(false);
  });
});

describe('pendingStaffUsernames', () => {
  it('collects usernames from create/pin/role rows', () => {
    const names = pendingStaffUsernames([
      { endpoint: '/mobile-user-create', payload: { username: 'john' } },
      { endpoint: '/mobile-user-update-pin', payload: { username: 'mary' } },
      { endpoint: '/mobile-user-update-role', payload: { username: 'sam' } },
    ]);
    expect([...names].sort()).toEqual(['john', 'mary', 'sam']);
  });

  it('protects the NEW username on a rename', () => {
    const names = pendingStaffUsernames([
      {
        endpoint: '/mobile-user-rename',
        payload: { oldUsername: 'old', newUsername: 'new' },
      },
    ]);
    expect(names.has('new')).toBe(true);
    // The old name is being retired, so it is not protected from reconcile.
    expect(names.has('old')).toBe(false);
  });

  it('does NOT protect a queued delete (the user should be removed)', () => {
    const names = pendingStaffUsernames([
      { endpoint: '/mobile-user-delete', payload: { username: 'gone' } },
    ]);
    expect(names.has('gone')).toBe(false);
  });

  it('ignores non-user endpoints and blank/invalid usernames', () => {
    const names = pendingStaffUsernames([
      { endpoint: '/mobile-order-update', payload: { username: 'notstaff' } },
      { endpoint: '/mobile-user-create', payload: { username: '   ' } },
      { endpoint: '/mobile-user-create', payload: {} },
      { endpoint: '/mobile-user-create', payload: null },
    ]);
    expect(names.size).toBe(0);
  });

  it('trims surrounding whitespace', () => {
    const names = pendingStaffUsernames([
      { endpoint: '/mobile-user-create', payload: { username: '  jane  ' } },
    ]);
    expect(names.has('jane')).toBe(true);
  });
});
