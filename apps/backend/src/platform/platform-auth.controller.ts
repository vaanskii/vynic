import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuthService } from './platform-auth.service';
import { requireText } from './platform-validation';

interface LoginBody {
  email?: string;
  password?: string;
}

/** Sign-in for Vynic administrators. */
@Controller('platform/auth')
export class PlatformAuthController {
  constructor(private readonly auth: PlatformAuthService) {}

  @Post('login')
  async login(@Body() body: LoginBody) {
    // Length-checked, not format-checked: a wrong address must fail exactly the
    // way a wrong password does, so the response cannot enumerate accounts.
    const email = requireText(body.email, 'email', { max: 320 });
    const password = requireText(body.password, 'password', { max: 512 });
    return this.auth.login(email, password);
  }

  @Get('me')
  @UseGuards(PlatformAuthGuard)
  me(@PlatformActor() actor: PlatformPrincipal) {
    return actor;
  }
}
