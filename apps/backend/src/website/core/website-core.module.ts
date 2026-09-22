import { Module } from '@nestjs/common';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { WebsiteCoreService } from './website-core.service';
import { WebsiteCoreController } from './website-core.controller';
@Module({
  imports: [WebsiteTenancyModule],
  providers: [WebsiteCoreService],
  controllers: [WebsiteCoreController],
  exports: [WebsiteCoreService],
})
export class WebsiteCoreModule {}
