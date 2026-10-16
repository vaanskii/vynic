import { UnauthorizedException } from '@nestjs/common';
import { ManagerActivationController } from './manager-activation.controller';
import { ManagerActivationService } from './manager-activation.service';
import type { PosAuthContext } from './pos-auth-context';
import { LoginThrottleService } from './login-throttle.service';

const pos: PosAuthContext = {
  venueId: 'venue',
  organizationId: 'org',
  deviceId: 'device',
  authenticationMode: 'device',
};
describe('Manager activation throttle', () => {
  it('bounds invalid invitations without affecting ordinary PIN login counters', async () => {
    const complete = jest.fn().mockRejectedValue(new UnauthorizedException());
    const throttle = new LoginThrottleService();
    const controller = new ManagerActivationController(
      { complete } as unknown as ManagerActivationService,
      throttle,
    );
    for (let i = 0; i < 5; i++)
      await expect(
        controller.complete(pos, {}, 'client'),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(controller.complete(pos, {}, 'client')).rejects.toMatchObject({
      status: 429,
    });
    expect(complete).toHaveBeenCalledTimes(5);
    expect(() => throttle.assertNotLocked('client')).not.toThrow();
  });
  it('successful activation cannot reset PIN failures', async () => {
    const complete = jest.fn().mockResolvedValue({ completed: true });
    const throttle = new LoginThrottleService();
    const controller = new ManagerActivationController(
      { complete } as unknown as ManagerActivationService,
      throttle,
    );
    for (let i = 0; i < 5; i++) throttle.recordFailure('client');
    await expect(controller.complete(pos, {}, 'client')).resolves.toEqual({
      completed: true,
    });
    expect(() => throttle.assertNotLocked('client')).toThrow();
  });
});
