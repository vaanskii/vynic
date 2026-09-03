import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { PosAuthContext } from '../auth/pos-auth-context';
import type { TenantContext } from '../tenancy/tenant-context';

/**
 * The Edge installation making a transport request.
 *
 * Narrower than PosAuthContext on purpose: `deviceId` is non-null. The work
 * queue routes work to a Device and lets only the claiming Device acknowledge
 * it, so an authentication that identifies no Device cannot use this transport
 * at all — which is why the legacy shared POS key is refused here.
 */
export interface EdgeDeviceContext extends TenantContext {
  deviceId: string;
}

interface EdgeAuthenticatedRequest {
  posAuthContext?: PosAuthContext;
}

/** The authenticated Edge Device and its Venue. */
export const EdgeDevice = createParamDecorator(
  (_data: unknown, context: ExecutionContext): EdgeDeviceContext => {
    const request = context
      .switchToHttp()
      .getRequest<EdgeAuthenticatedRequest>();
    const auth = request.posAuthContext;
    if (!auth?.deviceId) {
      throw new Error('EdgeDeviceGuard did not establish a device identity');
    }
    return {
      deviceId: auth.deviceId,
      venueId: auth.venueId,
      organizationId: auth.organizationId,
    };
  },
);
