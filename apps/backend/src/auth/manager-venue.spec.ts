import { UnauthorizedException } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { LoginThrottleService } from './login-throttle.service';

describe('Manager Venue lookup throttling', () => {
  it('successful identifier lookups never reset PIN failure counters', async () => {
    const throttle = new LoginThrottleService();
    const resolveManagerVenue = jest
      .fn()
      .mockResolvedValue({ code: 'venue-a' });
    const controller = new AuthController(
      { resolveManagerVenue } as unknown as AuthService,
      throttle,
    );
    for (let i = 0; i < 5; i++) throttle.recordFailure('client');
    await expect(
      controller.managerVenue({ venueCode: 'venue-a' }, 'client'),
    ).resolves.toEqual({ code: 'venue-a' });
    expect(() => throttle.assertNotLocked('client')).toThrow();
  });

  it('bounds invalid code attempts without locking the independent PIN endpoint', async () => {
    const throttle = new LoginThrottleService();
    const resolveManagerVenue = jest
      .fn()
      .mockRejectedValue(new UnauthorizedException('Restaurant unavailable'));
    const controller = new AuthController(
      { resolveManagerVenue } as unknown as AuthService,
      throttle,
    );
    for (let i = 0; i < 5; i++)
      await expect(
        controller.managerVenue({ venueCode: 'unknown' }, 'client'),
      ).rejects.toThrow('Restaurant unavailable');
    await expect(
      controller.managerVenue({ venueCode: 'unknown' }, 'client'),
    ).rejects.toMatchObject({ status: 429 });
    expect(resolveManagerVenue).toHaveBeenCalledTimes(5);
    expect(() => throttle.assertNotLocked('client')).not.toThrow();
  });
});
