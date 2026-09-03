import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/** Guards all routes that require a valid mobile JWT. */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
