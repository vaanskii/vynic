import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { TenantContext } from '../tenancy/tenant-context';

/**
 * Who is making a Manager request, and which Venue they are acting inside.
 *
 * Four separate questions, deliberately kept as four fields:
 *   authentication → staffId / username (who are you?)
 *   role           → role               (what may you do here?)
 *   tenant         → venueId            (whose data is this?)
 *   entitlement    → resolved elsewhere (did this Venue buy Manager?)
 *
 * Every field is resolved server-side from the Staff row named by the token's
 * subject. None of it comes from the request body.
 */
export interface ManagerAuthContext extends TenantContext {
  staffId: string;
  username: string;
  role: string;
}

/**
 * What JwtStrategy puts on `req.user`.
 *
 * `userId` is the pre-existing field name and is kept so handlers that already
 * read it are unaffected.
 */
export interface ManagerRequestUser extends ManagerAuthContext {
  userId: string;
}

interface ManagerAuthenticatedRequest {
  user?: ManagerRequestUser;
}

function readManagerUser(context: ExecutionContext): ManagerRequestUser {
  const request = context
    .switchToHttp()
    .getRequest<ManagerAuthenticatedRequest>();
  if (!request.user) {
    throw new Error('JwtAuthGuard did not establish a manager identity');
  }
  return request.user;
}

/** The authenticated Venue for a Manager request. */
export const ManagerTenant = createParamDecorator(
  (_data: unknown, context: ExecutionContext): TenantContext => {
    const { venueId, organizationId } = readManagerUser(context);
    return { venueId, organizationId };
  },
);

/** The full authenticated Manager principal, when a handler needs the person too. */
export const ManagerAuth = createParamDecorator(
  (_data: unknown, context: ExecutionContext): ManagerAuthContext => {
    const { staffId, username, role, venueId, organizationId } =
      readManagerUser(context);
    return { staffId, username, role, venueId, organizationId };
  },
);
