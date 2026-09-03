import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { PlatformRole } from '@prisma/client';

/**
 * The principal type a token was issued for.
 *
 * Present so a token can never be mistaken for one issued to a different kind
 * of principal. Manager and website tokens predate this claim and carry none,
 * which is by itself enough to refuse them at the platform boundary.
 */
export const PLATFORM_PRINCIPAL_TYPE = 'PLATFORM';

/** The audience a platform token is issued for, enforced at verification. */
export const PLATFORM_TOKEN_AUDIENCE = 'vynic-platform';
export const PLATFORM_TOKEN_ISSUER = 'vynic';

/**
 * A Vynic administrator making a control-plane request.
 *
 * Deliberately carries no venueId and no organizationId. A platform
 * administrator is cross-tenant by definition, and giving this a TenantContext
 * would invite tenant-scoped code to treat an operator as a restaurant
 * employee — which is the confusion the whole principal exists to avoid.
 */
export interface PlatformPrincipal {
  platformUserId: string;
  email: string;
  displayName: string;
  role: PlatformRole;
}

export interface PlatformAuthenticatedRequest {
  platformPrincipal?: PlatformPrincipal;
}

/** The authenticated Vynic administrator behind a control-plane request. */
export const PlatformActor = createParamDecorator(
  (_data: unknown, context: ExecutionContext): PlatformPrincipal => {
    const request = context
      .switchToHttp()
      .getRequest<PlatformAuthenticatedRequest>();
    if (!request.platformPrincipal) {
      throw new Error('PlatformAuthGuard did not establish a principal');
    }
    return request.platformPrincipal;
  },
);
