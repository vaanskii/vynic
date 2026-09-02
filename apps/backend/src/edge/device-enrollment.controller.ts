import {
  BadRequestException,
  Body,
  Controller,
  Post,
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { DeviceEnrollmentService } from './device-enrollment.service';

interface EnrollBody {
  enrollmentCode?: unknown;
  installationId?: unknown;
  platform?: unknown;
  displayName?: unknown;
}

function text(value: unknown, field: string, max: number): string {
  if (typeof value !== 'string' || !value.trim()) {
    throw new BadRequestException(`${field} is required`);
  }
  const trimmed = value.trim();
  if (trimmed.length > max) {
    throw new BadRequestException(`${field} is too long`);
  }
  return trimmed;
}

/**
 * The one route in Vynic that accepts a write without an authenticated
 * principal.
 *
 * It is not a general device-creation endpoint and must never become one. The
 * enrollment code *is* the credential: it is minted by an authenticated
 * administrator, bound to one Venue, single use and short-lived. There is
 * deliberately no `venueId` in the body — a terminal cannot name the tenant it
 * would like to join.
 *
 * Kept out of `EdgeTransportController` because that class guards every route
 * with `EdgeDeviceGuard`, and this is precisely the request made by a machine
 * that does not have a Device credential yet.
 */
@Controller('edge')
export class DeviceEnrollmentController {
  constructor(private readonly enrollments: DeviceEnrollmentService) {}

  @Post('enroll')
  async enroll(@Body() body: EnrollBody, @Req() request: Request) {
    const result = await this.enrollments.redeem({
      code: text(body.enrollmentCode, 'enrollmentCode', 64),
      installationId: text(body.installationId, 'installationId', 64),
      platform: text(body.platform, 'platform', 32),
      displayName:
        typeof body.displayName === 'string' && body.displayName.trim()
          ? body.displayName.trim().slice(0, 200)
          : undefined,
      clientIp: request.ip,
    });

    return {
      enrollmentId: result.enrollmentId,
      device: result.device,
      venue: result.venue,
      // Issued once. There is no route that reads it back.
      credential: result.credential,
      apiBaseUrl: result.apiBaseUrl,
      edgeContractVersion: result.edgeContractVersion,
      reusedExistingDevice: result.reusedExistingDevice,
      enrolledAt: result.enrolledAt.toISOString(),
    };
  }
}
