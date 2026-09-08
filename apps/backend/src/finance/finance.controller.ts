import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { StaffRole } from '../staff/staff-role';
import { FeatureGuard } from '../entitlements/feature.guard';
import { RequiresFeature } from '../entitlements/requires-feature.decorator';
import { FeatureKeys } from '../entitlements/feature-keys';
import { ManagerAuth, ManagerTenant } from '../auth/manager-auth-context';
import type { TenantContext } from '../tenancy/tenant-context';
import type { Actor } from './finance-common';
import {
  PayrollService,
  type CompensationInput,
  type PaymentInput,
  type AccrualInput,
} from './payroll.service';
import {
  ObligationsService,
  type ObligationInput,
} from './obligations.service';
import { PrismaService } from '../prisma.service';
import { payrollRemaining } from './financial-summary';
import { zero } from './finance-rules';
import { isSalaryCategory } from '../mobile/util/expense-category';

@Controller('mobile/finance')
@UseGuards(JwtAuthGuard, RolesGuard, FeatureGuard)
@Roles(StaffRole.MANAGER)
@RequiresFeature(FeatureKeys.MANAGER_APP)
export class FinanceController {
  constructor(
    private readonly payroll: PayrollService,
    private readonly obligations: ObligationsService,
    private readonly db: PrismaService,
  ) {}
  @Get('payroll') payrollList(
    @ManagerTenant() t: TenantContext,
    @Query('month') month?: string,
  ) {
    return this.payroll.overview(t, month);
  }
  @Post('staff/:id/compensation') compensation(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: CompensationInput,
  ) {
    return this.payroll.setCompensation(a, id, body);
  }
  @Get('staff/:id/history') payrollHistory(
    @ManagerTenant() t: TenantContext,
    @Param('id') id: string,
  ) {
    return this.payroll.history(t, id);
  }
  @Post('payroll/:id/payments') payrollPayment(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: PaymentInput,
  ) {
    return this.payroll.recordPayment(a, id, body);
  }
  @Post('payroll/:id/accruals') accrual(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: AccrualInput,
  ) {
    return this.payroll.recordAccrual(a, id, body);
  }
  @Get('obligations') obligationList(
    @ManagerTenant() t: TenantContext,
    @Query('month') month?: string,
  ) {
    return this.obligations.overview(t, month);
  }
  @Post('obligations') create(
    @ManagerAuth() a: Actor,
    @Body() body: ObligationInput,
  ) {
    return this.obligations.create(a, body);
  }
  @Patch('obligations/:id') update(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: ObligationInput,
  ) {
    return this.obligations.update(a, id, body);
  }
  @Get('obligations/:id/history') history(
    @ManagerTenant() t: TenantContext,
    @Param('id') id: string,
  ) {
    return this.obligations.history(t, id);
  }
  @Post('cycles/:id/reserves') reserve(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: PaymentInput,
  ) {
    return this.obligations.record(a, id, body, false);
  }
  @Post('cycles/:id/payments') payment(
    @ManagerAuth() a: Actor,
    @Param('id') id: string,
    @Body() body: PaymentInput,
  ) {
    return this.obligations.record(a, id, body, true);
  }
  @Get('legacy-salaries') async legacy(@ManagerTenant() t: TenantContext) {
    const rows = await this.db.expense.findMany({
      where: { venueId: t.venueId },
      orderBy: { createdAt: 'desc' },
    });
    return {
      entries: rows.filter((r) => isSalaryCategory(r.category)),
      classification: 'LEGACY_UNMAPPED_READ_ONLY',
    };
  }
  @Get('planning') async planning(@ManagerTenant() t: TenantContext) {
    const payroll = await this.payroll.overview(t);
    await this.obligations.overview(t);
    const cycles = await this.db.obligationCycle.findMany({
      where: { venueId: t.venueId, periodMonth: { lte: payroll.periodMonth } },
      include: { payments: true, reserves: true },
      orderBy: { dueDate: 'asc' },
    });
    const open = cycles
      .map((c) => this.obligations.present(c, payroll.today))
      .filter((c) => c.status !== 'PAID');
    return {
      today: payroll.today,
      businessDate: payroll.businessDate,
      payrollRemaining: await payrollRemaining(this.db, t, payroll.periodMonth),
      obligationsRemaining: open
        .reduce((s, c) => s.plus(c.remainingToPay), zero())
        .toFixed(2),
      dailyRecommendedReserve: open
        .reduce((s, c) => s.plus(c.dailyRecommendedReserve), zero())
        .toFixed(2),
      recommendations: open
        .filter((c) => c.dailyRecommendedReserve !== '0.00')
        .map((c) => ({
          name: c.name,
          periodMonth: c.periodMonth,
          amount: c.dailyRecommendedReserve,
        })),
    };
  }
}
