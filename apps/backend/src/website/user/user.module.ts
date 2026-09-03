import { Module } from '@nestjs/common';
import { WebsiteAuthModule } from '../auth/auth.module';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  imports: [WebsiteAuthModule, WebsiteTenancyModule],
  controllers: [UserController],
  providers: [UserService],
})
export class WebsiteUserModule {}
