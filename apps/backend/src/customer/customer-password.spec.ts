import { customerPassword } from './customer-auth';

describe('owner password length', () => {
  it.each([8, 15, 128])('accepts %i characters for signup and invitations', length => {
    expect(customerPassword('x'.repeat(length), true)).toHaveLength(length);
  });
  it.each([0, 7, 129])('rejects %i characters for new passwords', length => {
    expect(() => customerPassword('x'.repeat(length), true)).toThrow();
  });
  it('keeps existing login password validation compatible', () => {
    expect(customerPassword('legacy', false)).toBe('legacy');
  });
});
