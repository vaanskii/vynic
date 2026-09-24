import { cloudMenuAdmission } from './cloud-menu-admission';

const models = ['device', 'deviceEnrollment', 'menuCategory', 'menuItem', 'table', 'order', 'cloudSale', 'posReservation', 'auditReport', 'dailySnapshot', 'setting', 'expense', 'quickOrderDraft', 'edgeFoundationInstallation'];
function fixture(overrides = {}) {
  const tx: any = { venue: { findUniqueOrThrow: jest.fn().mockResolvedValue({ menuAuthority: 'POS', cloudMenuEditingEnabled: true, websiteConfig: { mode: 'SAAS' }, ...overrides }) } };
  for (const model of models) tx[model] = { count: jest.fn().mockResolvedValue(0) };
  return tx;
}
describe('first-use Cloud menu admission', () => {
  it('admits an empty venue and scopes every check to that venue', async () => {
    const tx = fixture();
    expect(await cloudMenuAdmission(tx, 'venue-a')).toMatchObject({ authority: 'POS', canEnableCloud: true, reason: null });
    for (const model of models) expect(tx[model].count).toHaveBeenCalledWith({ where: { venueId: 'venue-a' } });
  });
  it.each(models)('blocks existing %s history, including inactive devices', async model => {
    const tx = fixture();
    tx[model].count.mockResolvedValue(1);
    expect(await cloudMenuAdmission(tx, 'venue-a')).toMatchObject({ canEnableCloud: false, reason: expect.any(String) });
  });
  it.each([{ websiteConfig: { mode: 'CUSTOM' } }, { activeOperationalDeviceId: 'primary' }])('blocks protected venue configuration %j', async config => {
    expect(await cloudMenuAdmission(fixture(config), 'venue-a')).toMatchObject({ canEnableCloud: false });
  });
  it('reports Cloud venues without offering a second transition', async () => {
    expect(await cloudMenuAdmission(fixture({ menuAuthority: 'CLOUD' }), 'venue-a')).toEqual({ authority: 'CLOUD', enabled: true, canEnableCloud: true, reason: null });
  });
});
