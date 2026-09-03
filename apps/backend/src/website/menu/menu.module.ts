import { Module } from '@nestjs/common';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { MenuController } from './menu.controller';
import { MenuService } from './menu.service';

@Module({
  imports: [WebsiteTenancyModule],
  controllers: [MenuController],
  providers: [MenuService],
  exports: [MenuService],
})
export class WebsiteMenuModule {}
