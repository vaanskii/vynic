import { SetMetadata } from '@nestjs/common';
import { WebsiteUserRole } from '@prisma/client';

export const WEBSITE_ROLES_KEY = 'website_roles';
export const WebsiteRoles = (...roles: WebsiteUserRole[]) =>
  SetMetadata(WEBSITE_ROLES_KEY, roles);
