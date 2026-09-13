import {
  BadRequestException,
  CanActivate,
  ExecutionContext,
  HttpException,
  Injectable,
  UnauthorizedException,
  createParamDecorator,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { requireEnv } from '../shared/require-env';
import { requireText } from '../platform/platform-validation';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';

export interface CustomerPrincipal {
  customerAccountId: string;
  organizationId: string;
}
export const CustomerActor = createParamDecorator(
  (_: unknown, context: ExecutionContext): CustomerPrincipal =>
    context.switchToHttp().getRequest().customer,
);
const fields = {
  id: true,
  organizationId: true,
  email: true,
  displayName: true,
  emailVerifiedAt: true,
  isActive: true,
} as const;
@Injectable()
export class CustomerAuth {
  constructor(
    private readonly db: PrismaService,
    private readonly jwt: JwtService,
    private readonly limiter: EnrollmentRateLimiter,
  ) {}
  async authenticate(
    body: Record<string, unknown>,
    ip: string,
    signup: boolean,
  ) {
    const email = requireText(body.email, 'email', { max: 254 }).toLowerCase();
    if (
      !this.limiter.consume(`customer-ip:${ip}`, 20, 900000) ||
      !this.limiter.consume(`customer-email:${email}`, 10, 900000)
    )
      throw new HttpException('Too many attempts. Try again later.', 429);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new BadRequestException('Invalid email');
    const password = body.password;
    if (
      typeof password !== 'string' ||
      password.length > 128 ||
      password.length < (signup ? 15 : 1)
    )
      throw new BadRequestException('Password must be 15–128 characters');
    let user;
    if (signup) {
      const policy = await this.db.onboardingPolicy.findUnique({
        where: { id: 'default' },
      });
      if (!policy?.enabled || !policy.trialPlanId)
        throw new HttpException('Pilot registration is not open yet.', 503);
      const displayName = requireText(body.displayName, 'name', { max: 100 });
      const passwordHash = await argon2.hash(password, {
        type: argon2.argon2id,
      });
      try {
        user = await this.db.$transaction(async (tx) => {
          const org = await tx.organization.create({
            data: { name: displayName },
          });
          const account = await tx.customerAccount.create({
            data: { organizationId: org.id, email, displayName, passwordHash },
            select: fields,
          });
          await tx.customerAuditEvent.create({
            data: {
              customerAccountId: account.id,
              action: 'account.created',
              targetType: 'Organization',
              targetId: org.id,
            },
          });
          return account;
        });
      } catch (error) {
        if ((error as { code?: string }).code === 'P2002')
          throw new BadRequestException(
            'Registration could not be completed. Try signing in.',
          );
        throw error;
      }
    } else {
      const row = await this.db.customerAccount.findUnique({
        where: { email },
      });
      if (!row?.isActive || !(await argon2.verify(row.passwordHash, password)))
        throw new UnauthorizedException('Invalid credentials');
      user = await this.db.customerAccount.findUniqueOrThrow({
        where: { id: row.id },
        select: fields,
      });
    }
    const access_token = await this.jwt.signAsync(
      { sub: user.id, typ: 'CUSTOMER' },
      {
        secret: requireEnv('JWT_SECRET'),
        audience: 'vynic-customer',
        issuer: 'vynic',
        expiresIn: 28800,
      },
    );
    return { access_token, account: user };
  }
  async resolve(token: string): Promise<CustomerPrincipal> {
    try {
      const payload = await this.jwt.verifyAsync(token, {
        secret: requireEnv('JWT_SECRET'),
        audience: 'vynic-customer',
        issuer: 'vynic',
      });
      if (payload.typ !== 'CUSTOMER') throw new Error('Wrong principal');
      const user = await this.db.customerAccount.findUnique({
        where: { id: payload.sub },
        select: fields,
      });
      if (!user?.isActive) throw new Error('Inactive account');
      return {
        customerAccountId: user.id,
        organizationId: user.organizationId,
      };
    } catch {
      throw new UnauthorizedException('Customer login required');
    }
  }
}
@Injectable()
export class CustomerGuard implements CanActivate {
  constructor(private readonly auth: CustomerAuth) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    const header = request.headers.authorization;
    if (typeof header !== 'string' || !header.startsWith('Bearer '))
      throw new UnauthorizedException('Customer login required');
    request.customer = await this.auth.resolve(header.slice(7));
    return true;
  }
}
