import {
  Body,
  Controller,
  Post,
  Get,
  Res,
  Req,
  ForbiddenException,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { CryptoService } from '../common/crypto.service';
import { CsrfService } from '../common/csrf.service';
import { WebsiteAuthService } from './auth.service';
import { AuthDto, ChangePasswordDto, RegisterDto } from './dto';
import { WebsiteAuthGuard } from './website-auth.guard';

@Controller('api/auth')
export class WebsiteAuthController {
  constructor(
    private readonly authService: WebsiteAuthService,
    private readonly cryptoService: CryptoService,
    private readonly csrfService: CsrfService,
  ) {}

  @Post('signup')
  async signup(
    @Body() dto: RegisterDto,
    @Res({ passthrough: true }) res: Response,
    @Req() req: Request,
  ) {
    this.assertCsrf(req);
    const tokens = await this.authService.signup(dto);
    this.setAuthCookies(res, tokens);
    return { message: 'Signup successful' };
  }

  @Post('signin')
  async signin(
    @Body() dto: AuthDto,
    @Res({ passthrough: true }) res: Response,
    @Req() req: Request,
  ) {
    this.assertCsrf(req);
    const tokens = await this.authService.signin(dto);
    this.setAuthCookies(res, tokens);
    return { message: 'Signin successful' };
  }

  @Post('logout')
  logout(@Res({ passthrough: true }) res: Response) {
    res.clearCookie('access_token');
    res.clearCookie('refresh_token');
    return { message: 'Logout successful' };
  }

  @Get('csrf')
  getCsrfToken(@Res({ passthrough: true }) res: Response) {
    const token = this.csrfService.generateToken();
    res.cookie('csrf_token', token, {
      httpOnly: false,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 24 * 60 * 60 * 1000,
    });
    return { csrfToken: token };
  }

  @Get('verify')
  async verify(@Req() req: Request) {
    try {
      const encryptedAccessToken = req.cookies['access_token'];
      if (!encryptedAccessToken) return { isAuthenticated: false };

      const accessToken = this.cryptoService.decrypt(encryptedAccessToken);
      const user = await this.authService.verifyToken(accessToken);
      return {
        isAuthenticated: true,
        user: {
          id: user.id,
          phone: user.phone,
          firstName: user.firstName,
          lastName: user.lastName,
          email: user.email,
          role: user.role,
        },
      };
    } catch {
      return { isAuthenticated: false };
    }
  }

  @UseGuards(WebsiteAuthGuard)
  @Post('change-password')
  async changePassword(@Body() dto: ChangePasswordDto, @Req() req: Request) {
    this.assertCsrf(req);
    const user = (req as Request & { user: { id: string } }).user;
    return this.authService.changePassword(user.id, dto);
  }

  private assertCsrf(req: Request) {
    const csrfToken = req.headers['x-csrf-token'] as string;
    const csrfCookie = req.cookies['csrf_token'];
    if (!this.csrfService.validateToken(csrfToken, csrfCookie)) {
      throw new ForbiddenException('Invalid CSRF token');
    }
  }

  private setAuthCookies(
    res: Response,
    tokens: { access_token: string; refresh_token: string },
  ) {
    const secure = process.env.NODE_ENV === 'production';
    res.cookie('access_token', this.cryptoService.encrypt(tokens.access_token), {
      httpOnly: true,
      secure,
      sameSite: 'strict',
      maxAge: 15 * 60 * 1000,
    });
    res.cookie('refresh_token', this.cryptoService.encrypt(tokens.refresh_token), {
      httpOnly: true,
      secure,
      sameSite: 'strict',
      maxAge: 7 * 24 * 60 * 60 * 1000,
    });
  }
}
