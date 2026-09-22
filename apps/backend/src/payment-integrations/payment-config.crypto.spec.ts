import {
  encryptPaymentConfig,
  decryptPaymentConfig,
} from './payment-config.crypto';
describe('payment encryption', () => {
  const previous = process.env.PAYMENT_INTEGRATION_MASTER_KEY;
  beforeEach(() => {
    process.env.PAYMENT_INTEGRATION_MASTER_KEY = 'ab'.repeat(32);
  });
  afterAll(() => {
    if (previous === undefined)
      delete process.env.PAYMENT_INTEGRATION_MASTER_KEY;
    else process.env.PAYMENT_INTEGRATION_MASTER_KEY = previous;
  });
  it('randomizes encryption, authenticates tenant and revision and detects tampering', () => {
    const config = { clientSecret: 'never-plaintext' };
    const encrypted = encryptPaymentConfig('a', '1', config);
    expect(encrypted).not.toBe(encryptPaymentConfig('a', '1', config));
    expect(encrypted).not.toContain(config.clientSecret);
    expect(decryptPaymentConfig('a', '1', encrypted)).toEqual(config);
    expect(() => decryptPaymentConfig('b', '1', encrypted)).toThrow();
    expect(() => decryptPaymentConfig('a', '2', encrypted)).toThrow();
    const parts = encrypted.split('.');
    parts[3] = Buffer.from('tampered').toString('base64');
    expect(() => decryptPaymentConfig('a', '1', parts.join('.'))).toThrow();
    process.env.PAYMENT_INTEGRATION_MASTER_KEY = 'cd'.repeat(32);
    expect(() => decryptPaymentConfig('a', '1', encrypted)).toThrow();
  });
  it.each(['', 'short', 'z'.repeat(64)])(
    'fails closed with malformed key',
    (key) => {
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = key;
      expect(() => encryptPaymentConfig('a', '1', {})).toThrow(
        'Payment encryption key unavailable',
      );
    },
  );
});
