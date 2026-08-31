import { PlatformAuditService } from './platform-audit.service';

describe('PlatformAuditService', () => {
  it('applies bounded offset pagination to the platform trail', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const service = new PlatformAuditService({
      platformAuditEvent: { findMany },
    } as never);

    await service.recent(25, 50, '11111111-1111-4111-8111-111111111111');

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { targetId: '11111111-1111-4111-8111-111111111111' },
        take: 25,
        skip: 50,
      }),
    );
  });
});
