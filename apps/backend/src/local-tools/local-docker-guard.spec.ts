import { requireLocalDocker } from './local-docker-guard';
import {
  assertMatrixComplete,
  preservedModels,
  specialModels,
  venueModels,
} from './deletion-matrix';
import { Prisma } from '@prisma/client';
const env = {
  VYNIC_LOCAL_DOCKER: 'true',
  DATABASE_URL: 'postgresql://vynic:secret@postgres:5432/vynic_local_prod',
};
describe('local maintenance guard', () => {
  it('accepts only the explicit isolated Docker connection', () =>
    expect(() => requireLocalDocker(env, true)).not.toThrow());
  it.each([
    ['VYNIC_LOCAL_DOCKER', 'false'],
    ['VYNIC_LOCAL_DOCKER', ''],
    [
      'DATABASE_URL',
      'postgresql://vynic:secret@postgres:5432/vankisi_database',
    ],
    [
      'DATABASE_URL',
      'postgresql://vynic:secret@remote.example:5432/vynic_local_prod',
    ],
    [
      'DATABASE_URL',
      'postgresql://vynic:secret@localhost:5432/vynic_local_prod',
    ],
    ['DATABASE_URL', env.DATABASE_URL + '?host=remote.example'],
    ['DATABASE_URL', env.DATABASE_URL + '?dbname=vankisi_database'],
    ['DATABASE_URL', env.DATABASE_URL + '#ignored'],
    ['DATABASE_URL', ''],
    ['DATABASE_URL', env.DATABASE_URL.replace(':5432', ':5433')],
    [
      'DATABASE_URL',
      env.DATABASE_URL.replace('vynic:secret', 'postgres:secret'),
    ],
  ])('refuses %s=%s before connecting', (key, value) =>
    expect(() => requireLocalDocker({ ...env, [key]: value }, true)).toThrow(),
  );
  it('rejects execution outside Docker', () =>
    expect(() => requireLocalDocker(env, false)).toThrow());
  it('classifies every actual model explicitly', () =>
    expect(assertMatrixComplete).not.toThrow());
  it('preserves the complete control plane outside all delete lists', () => {
    expect(preservedModels).toEqual([
      'PlatformUser',
      'PlatformAuditEvent',
      'Plan',
      'Feature',
      'PlanFeature',
      'OnboardingPolicy',
      'SecurityAdmission',
      'InstallerDownloadGrant',
      'InvitationResumeSession',
    ]);
    for (const name of preservedModels)
      expect([...venueModels, ...specialModels]).not.toContain(name);
  });
  it('orders restrictive venue foreign keys child first (explicit cycle exceptions)', () => {
    const order: readonly string[] = [...venueModels, 'Venue'];
    for (const model of Prisma.dmmf.datamodel.models) {
      if (!order.includes(model.name)) continue;
      for (const field of model.fields) {
        if (
          !field.relationFromFields?.length ||
          !order.includes(field.type) ||
          field.relationOnDelete === 'Cascade' ||
          field.relationOnDelete === 'SetNull'
        )
          continue;
        if (model.name === field.type) continue; // Payroll adjustments explicitly first; SupplierPayment NO ACTION at statement end.
        expect(
          `${model.name} -> ${field.type}: ${order.indexOf(model.name) < order.indexOf(field.type)}`,
        ).toMatch(/true$/);
      }
    }
  });
});
