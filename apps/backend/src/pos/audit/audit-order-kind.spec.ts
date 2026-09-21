import { deriveOrderKind } from './audit-order-kind';

/** `sequence` is what the POS assigns; the array is offered out of order. */
function event(
  type: string,
  sequence: number,
  details?: Record<string, unknown>,
) {
  return { type, sequence, details };
}

describe('deriveOrderKind', () => {
  it('reads a Walk-In from its creation event', () => {
    expect(
      deriveOrderKind([
        event('CREATE_WALKIN', 0, { orderKind: 'WALK_IN' }),
        event('ADD_ITEM', 1),
      ]),
    ).toBe('WALK_IN');
  });

  it('reads a Takeaway from its creation event', () => {
    expect(
      deriveOrderKind([
        event('CREATE_TAKEAWAY', 0, { orderKind: 'TAKEAWAY' }),
      ]),
    ).toBe('TAKEAWAY');
  });

  it('reads a seated booking from ACTIVATE_RESERVATION', () => {
    expect(
      deriveOrderKind([
        event('ACTIVATE_RESERVATION', 0, {
          orderKind: 'RESERVATION',
          reservationId: 'res-1',
        }),
      ]),
    ).toBe('RESERVATION');
  });

  it('prefers what the carrier declares over its event type', () => {
    // A Package is opened as a Walk-In that says it is a Package.
    expect(
      deriveOrderKind([
        event('CREATE_WALKIN', 0, { orderKind: 'PACKAGE' }),
        event('APPLY_PACKAGE', 1),
      ]),
    ).toBe('PACKAGE');
  });

  it('falls back to the event type when details declare nothing', () => {
    expect(deriveOrderKind([event('CREATE_WALKIN', 0)])).toBe('WALK_IN');
    expect(deriveOrderKind([event('CREATE_TAKEAWAY', 0)])).toBe('TAKEAWAY');
  });

  it('ignores an unrecognised declared kind', () => {
    expect(
      deriveOrderKind([event('CREATE_WALKIN', 0, { orderKind: 'BRUNCH' })]),
    ).toBe('WALK_IN');
  });

  it('uses the earliest creation event by sequence, not by arrival', () => {
    expect(
      deriveOrderKind([
        event('CLOSE', 2),
        event('ADD_ITEM', 1),
        event('CREATE_TAKEAWAY', 0),
      ]),
    ).toBe('TAKEAWAY');
  });

  it('recognises a Package carrier that only has APPLY_PACKAGE', () => {
    expect(
      deriveOrderKind([event('ADD_ITEM', 0), event('APPLY_PACKAGE', 1)]),
    ).toBe('PACKAGE');
  });

  it('answers null when nothing durable says what was opened', () => {
    expect(deriveOrderKind([])).toBeNull();
    expect(
      deriveOrderKind([
        { type: 'ADD_ITEM', previousQty: 0, newQty: 1 },
        { type: 'CLOSE' },
      ]),
    ).toBeNull();
  });

  it('does not guess from a report that merely looks like takeaway', () => {
    // Nothing here is a creation event. `floor` is not passed in at all,
    // because a floor-plan edit can change it under history.
    expect(deriveOrderKind([{ type: 'CLOSE' }])).toBeNull();
  });
});
