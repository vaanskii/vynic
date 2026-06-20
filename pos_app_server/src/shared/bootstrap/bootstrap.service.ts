import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { WebsiteUserRole } from '@prisma/client';
import * as argon from 'argon2';
import { PrismaService } from '../prisma/prisma.service';
import { WEBSITE_TABLE_MAPPINGS } from './website-table-mappings';

@Injectable()
export class BootstrapService implements OnModuleInit {
  private readonly logger = new Logger(BootstrapService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    await this.seedWebsiteTables();
    await this.seedWebsiteAdminIfConfigured();
    await this.reportMenuStatus();
    this.logEnvGaps();
  }

  private async seedWebsiteTables(): Promise<void> {
    for (const mapping of WEBSITE_TABLE_MAPPINGS) {
      await this.prisma.websiteTable.upsert({
        where: { websiteTableNumber: mapping.websiteTableNumber },
        create: mapping,
        update: {
          posTableNumber: mapping.posTableNumber,
          posFloor: mapping.posFloor,
          capacity: mapping.capacity,
        },
      });
    }
    this.logger.log(`Website tables ready (${WEBSITE_TABLE_MAPPINGS.length} mappings)`);
  }

  private adminCredentials():
    | { phone: string; email: string; password: string }
    | null {
    const phone =
      this.config.get<string>('SUPER_ADMIN_PHONE');
    const password =
      this.config.get<string>('SUPER_ADMIN_PASSWORD');

    if (!phone?.trim() || !password?.trim()) {
      return null;
    }

    return {
      phone: phone.trim(),
      email: (
        this.config.get<string>('SUPER_ADMIN_EMAIL') ||
        'admin@example.com'
      ).trim(),
      password: password.trim(),
    };
  }

  private async seedWebsiteAdminIfConfigured(): Promise<void> {
    const credentials = this.adminCredentials();
    if (!credentials) {
      const adminCount = await this.prisma.websiteUser.count({
        where: { role: WebsiteUserRole.SUPER_ADMIN },
      });
      if (adminCount === 0) {
        this.logger.warn(
          'No website SUPER_ADMIN — set SUPER_ADMIN_PHONE + SUPER_ADMIN_PASSWORD in .env',
        );
      }
      return;
    }

    const hash = await argon.hash(credentials.password);
    await this.prisma.websiteUser.upsert({
      where: { phone: credentials.phone },
      create: {
        phone: credentials.phone,
        email: credentials.email,
        password: hash,
        role: WebsiteUserRole.SUPER_ADMIN,
        firstName: 'Admin',
      },
      update: {
        email: credentials.email,
        password: hash,
        role: WebsiteUserRole.SUPER_ADMIN,
      },
    });
    this.logger.log(`Website SUPER_ADMIN ready (${credentials.phone})`);
  }

  private async reportMenuStatus(): Promise<void> {
    const menuItems = await this.prisma.menuItem.count();
    if (menuItems === 0) {
      this.logger.warn(
        'Menu is empty — sync from Windows POS (/sync/manager-data). Website /api/menu stays empty until then.',
      );
      return;
    }
    this.logger.log(`Menu ready (${menuItems} items from POS sync)`);
  }

  private logEnvGaps(): void {
    const optionalWebsite = [
      'JWT_REFRESH_SECRET',
      'COOKIE_ENCRYPTION_KEY',
      'BOG_CLIENT_ID',
      'BOG_CLIENT_SECRET',
      'FRONTEND_URL',
      'API_URL',
    ];
    const missing = optionalWebsite.filter((key) => !this.config.get(key)?.trim());
    if (missing.length > 0) {
      this.logger.warn(`Website features incomplete — missing: ${missing.join(', ')}`);
    }
  }
}
