import { createParamDecorator, ExecutionContext } from '@nestjs/common';

import type { TenantContext } from '../tenancy/tenant-context';

export type PosAuthenticationMode = 'device' | 'legacy_shared_key';

// Re-exported so existing POS imports keep working. There is one definition of
// a tenant (src/tenancy/tenant-context.ts) and both authentication mechanisms
// produce it.
export type { TenantContext };

export interface PosAuthContext extends TenantContext {
  authenticationMode: PosAuthenticationMode;
  deviceId: string | null;
}

export interface PosAuthenticatedRequest {
  headers: Record<string, string | string[] | undefined>;
  posAuthContext?: PosAuthContext;
}

/**
 * Transport-only access to the identity established by PosSyncGuard.
 * Application and snapshot services receive the typed value as an argument;
 * they never parse HTTP headers or depend on the request object.
 */
export const PosAuth = createParamDecorator(
  (_data: unknown, context: ExecutionContext): PosAuthContext => {
    const request = context
      .switchToHttp()
      .getRequest<PosAuthenticatedRequest>();
    if (!request.posAuthContext) {
      throw new Error('PosSyncGuard did not establish an auth context');
    }
    return request.posAuthContext;
  },
);
