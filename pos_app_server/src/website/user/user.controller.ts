import { Controller, Get, Patch, Body, UseGuards, Request } from '@nestjs/common';
import { WebsiteAuthGuard } from '../auth/website-auth.guard';
import { UserService } from './user.service';

interface RequestWithUser extends Request {
  user: { id: string; email: string };
}

@Controller('api/user')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @UseGuards(WebsiteAuthGuard)
  @Get('profile')
  async getProfile(@Request() req: RequestWithUser) {
    return this.userService.getProfile(req.user.id);
  }

  @UseGuards(WebsiteAuthGuard)
  @Get('reservations')
  async getUserReservations(@Request() req: RequestWithUser) {
    return this.userService.getUserReservations(req.user.id);
  }

  @UseGuards(WebsiteAuthGuard)
  @Patch('profile')
  async updateProfile(
    @Request() req: RequestWithUser,
    @Body() dto: { firstName: string; lastName: string },
  ) {
    return this.userService.updateProfile(req.user.id, dto);
  }
}
