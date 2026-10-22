import { HttpException, UnauthorizedException } from '@nestjs/common';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { PlatformAuthController } from './platform-auth.controller';
import { PlatformAuthService } from './platform-auth.service';

describe('PlatformAuthController login throttling', () => {
  const password = 'correct horse battery staple';
  let login: jest.Mock;
  let controller: PlatformAuthController;

  beforeEach(() => {
    login = jest.fn((email: string, secret: string) =>
      secret === password
        ? Promise.resolve({ token: 't', user: { email } })
        : Promise.reject(new UnauthorizedException('Invalid credentials')),
    );
    controller = new PlatformAuthController(
      { login } as unknown as PlatformAuthService,
      new EnrollmentRateLimiter(),
    );
  });

  const attempt = (email: string, secret: string, ip = '203.0.113.7') =>
    controller.login({ email, password: secret }, ip);

  const expect429 = async (promise: Promise<unknown>) => {
    await expect(promise).rejects.toMatchObject({ status: 429 });
    await expect(promise).rejects.toBeInstanceOf(HttpException);
  };

  it('locks one email after ten attempts even when the last guess is right', async () => {
    for (let i = 0; i < 10; i += 1) {
      await expect(attempt('Admin@Vynic.ge', 'wrong')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    }
    // Case and whitespace variants share the account, so they share the window.
    await expect429(attempt('  admin@vynic.ge ', password));
    expect(login).toHaveBeenCalledTimes(10);
  });

  it('locks one address after twenty attempts across different emails', async () => {
    for (let i = 0; i < 20; i += 1) {
      await expect(
        attempt(`user${i}@vynic.ge`, 'wrong'),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    }
    await expect429(attempt('fresh@vynic.ge', password));
    // Another address is unaffected.
    await expect(
      attempt('fresh@vynic.ge', password, '198.51.100.9'),
    ).resolves.toMatchObject({
      user: { email: 'fresh@vynic.ge' },
    });
  });

  it('throttles before touching the account, so a locked window cannot enumerate', async () => {
    for (let i = 0; i < 10; i += 1)
      await attempt('owner@vynic.ge', 'wrong').catch(() => undefined);
    login.mockClear();
    await expect429(attempt('owner@vynic.ge', password));
    expect(login).not.toHaveBeenCalled();
  });

  it('still rejects malformed input before consuming the window', async () => {
    await expect(attempt('', password)).rejects.toMatchObject({ status: 400 });
    await expect(attempt('a@b.c', password)).resolves.toBeDefined();
  });
});
