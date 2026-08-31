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

  it('includes device-targeted events for a venue through the device relationship', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const deviceFindMany = jest
      .fn()
      .mockResolvedValue([{ id: '22222222-2222-4222-8222-222222222222' }]);
    const service = new PlatformAuditService({
      platformAuditEvent: { findMany },
      device: { findMany: deviceFindMany },
    } as never);

    await service.recent(
      100,
      0,
      undefined,
      '11111111-1111-4111-8111-111111111111',
    );

    expect(deviceFindMany).toHaveBeenCalledWith({
      where: { venueId: '11111111-1111-4111-8111-111111111111' },
      select: { id: true },
    });
    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          OR: [
            {
              targetType: 'Venue',
              targetId: '11111111-1111-4111-8111-111111111111',
            },
            {
              targetType: 'Device',
              targetId: { in: ['22222222-2222-4222-8222-222222222222'] },
            },
          ],
        },
      }),
    );
  });
});
