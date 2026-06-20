import { Module } from '@nestjs/common';
import { WebsiteAuthModule } from '../auth/auth.module';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  imports: [WebsiteAuthModule],
  controllers: [UserController],
  providers: [UserService],
})
export class WebsiteUserModule {}
