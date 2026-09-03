import { EnrollmentRateLimiter } from './enrollment-rate-limiter';

describe('EnrollmentRateLimiter', () => {
  it('allows a key up to its limit and then refuses it', () => {
    const limiter = new EnrollmentRateLimiter();
    const now = 1_000_000;
    for (let i = 0; i < 5; i++) {
      expect(limiter.consume('ip:1.2.3.4', 5, 60_000, now)).toBe(true);
    }
    expect(limiter.consume('ip:1.2.3.4', 5, 60_000, now)).toBe(false);
  });

  it('keeps keys apart', () => {
    const limiter = new EnrollmentRateLimiter();
    const now = 1_000_000;
    expect(limiter.consume('ip:1.2.3.4', 1, 60_000, now)).toBe(true);
    expect(limiter.consume('ip:1.2.3.4', 1, 60_000, now)).toBe(false);
    expect(limiter.consume('code:7K2Q', 1, 60_000, now)).toBe(true);
  });

  it('opens the window again once it has passed', () => {
    const limiter = new EnrollmentRateLimiter();
    const now = 1_000_000;
    expect(limiter.consume('ip:1.2.3.4', 1, 60_000, now)).toBe(true);
    expect(limiter.consume('ip:1.2.3.4', 1, 60_000, now + 59_000)).toBe(false);
    expect(limiter.consume('ip:1.2.3.4', 1, 60_000, now + 60_001)).toBe(true);
  });
});
