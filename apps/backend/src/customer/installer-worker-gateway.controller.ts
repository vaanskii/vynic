import { Body, Controller, Header, Headers, Post } from '@nestjs/common';
import { InstallerDownloadsService } from './installer-downloads.service';
import {
  requireInstallerGateway,
  workerRequest,
} from './installer-worker-gateway';

@Controller('customer/downloads/worker')
export class InstallerWorkerGatewayController {
  constructor(private readonly downloads: InstallerDownloadsService) {}
  @Post('authorize')
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  authorize(
    @Headers('authorization') secret: string | undefined,
    @Body() body: Record<string, unknown>,
  ) {
    requireInstallerGateway(secret);
    return this.downloads.workerDecision(workerRequest(body));
  }
}
