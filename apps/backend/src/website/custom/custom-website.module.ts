import { Module } from '@nestjs/common';
import { WebsiteCoreModule } from '../core/website-core.module';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { CustomWebsiteController } from './custom-website.controller';
import { CustomWebsiteService } from './custom-website.service';

@Module({
  imports: [WebsiteTenancyModule, WebsiteCoreModule],
  controllers: [CustomWebsiteController],
  providers: [CustomWebsiteService],
  exports: [CustomWebsiteService],
})
export class CustomWebsiteModule {}
