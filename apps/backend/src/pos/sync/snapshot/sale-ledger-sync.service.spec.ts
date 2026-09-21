import { cloudSaleCountsAsRevenue } from './sale-ledger-sync.service';

describe('Cloud Sale revenue predicate', () => {
  it.each([
    ['normal fiscal Sale', true, false, false, true],
    ['internal Sale', false, false, false, false],
    ['cancelled Sale', true, true, false, false],
    ['restored Sale', true, false, true, false],
  ])(
    'matches POS semantics for %s',
    (_name, isFiscal, isCancelled, restoredToOrder, expected) => {
      expect(
        cloudSaleCountsAsRevenue({
          isFiscal: isFiscal as boolean,
          isCancelled: isCancelled as boolean,
          restoredToOrder: restoredToOrder as boolean,
        }),
      ).toBe(expected);
    },
  );
});
