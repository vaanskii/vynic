import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { WebsiteCoreService } from './website-core.service';
import { WebsiteMenuService } from './website-menu.service';
import { WebsitePreviewTokens } from './website-preview';
import { WebsiteCoreController } from './website-core.controller';
@Module({
  imports: [WebsiteTenancyModule, JwtModule.register({})],
  providers: [WebsiteCoreService, WebsiteMenuService, WebsitePreviewTokens],
  controllers: [WebsiteCoreController],
  exports: [WebsiteCoreService, WebsiteMenuService, WebsitePreviewTokens],
})
export class WebsiteCoreModule {}
