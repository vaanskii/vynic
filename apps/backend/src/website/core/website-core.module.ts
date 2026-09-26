import { HostnameRequestsService } from './hostname-requests';
import { WebsiteLogoService } from './website-logo.service';
import { WebsiteLogoController } from './website-logo.controller';
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { WebsiteCoreService } from './website-core.service';
import { WebsiteMenuService } from './website-menu.service';
import { WebsitePreviewTokens } from './website-preview';
import { WebsiteCoreController } from './website-core.controller';
import { VenuePublicProfileService } from './venue-public-profile.service';
import { WebsiteVenueController } from './website-venue.controller';
import { WebsiteVenueService } from './website-venue.service';
@Module({
  imports: [WebsiteTenancyModule, JwtModule.register({})],
  providers: [
    HostnameRequestsService,
    WebsiteLogoService,
    WebsiteCoreService,
    WebsiteMenuService,
    WebsitePreviewTokens,
    VenuePublicProfileService,
    WebsiteVenueService,
  ],
  controllers: [
    WebsiteLogoController,
    WebsiteCoreController,
    WebsiteVenueController,
  ],
  exports: [
    HostnameRequestsService,
    WebsiteLogoService,
    WebsiteCoreService,
    WebsiteMenuService,
    WebsitePreviewTokens,
    VenuePublicProfileService,
    WebsiteVenueService,
  ],
})
export class WebsiteCoreModule {}
