import { CustomerWebsiteController } from './customer-website.controller';

describe('Owner logo upload authority', () => {
  const actor = { customerAccountId: 'owner-a' };
  const owners = { venue: jest.fn() };
  const core = { settings: jest.fn() };
  const logos = { upload: jest.fn() };
  const controller = new CustomerWebsiteController(
    {} as any,
    owners as any,
    core as any,
    {} as any,
    {} as any,
    {} as any,
    logos as any,
  );
  beforeEach(() => {
    jest.resetAllMocks();
    core.settings.mockResolvedValue({ mode: 'SAAS' });
  });
  it('checks ownership before processing bytes and leaves save/publication separate', async () => {
    logos.upload.mockResolvedValue({
      url: '/media/website-logos/example.webp',
    });
    await expect(
      controller.uploadLogo(actor, 'venue-a'),
    ).resolves.toHaveProperty('url');
    expect(owners.venue).toHaveBeenCalledWith(actor, 'venue-a');
    expect(logos.upload).toHaveBeenCalledTimes(1);
  });
  it('uses the same ownership and CUSTOM safeguards for main photos', async () => {
    owners.venue.mockRejectedValueOnce(new Error('Not found'));
    await expect(controller.uploadHero(actor, 'venue-b')).rejects.toThrow();
    expect(logos.upload).not.toHaveBeenCalled();
    core.settings.mockResolvedValueOnce({ mode: 'CUSTOM' });
    await expect(controller.uploadHero(actor, 'vankisi')).rejects.toThrow(
      'SAAS',
    );
    expect(logos.upload).not.toHaveBeenCalled();
    await controller.uploadHero(actor, 'venue-a');
    expect(logos.upload).toHaveBeenCalledWith('venue-a', undefined, 'hero');
  });
  it('rejects another owner and CUSTOM sites before storage', async () => {
    owners.venue.mockRejectedValueOnce(new Error('Not found'));
    await expect(controller.uploadLogo(actor, 'venue-b')).rejects.toThrow();
    expect(logos.upload).not.toHaveBeenCalled();
    core.settings.mockResolvedValue({ mode: 'CUSTOM' });
    await expect(controller.uploadLogo(actor, 'vankisi')).rejects.toThrow(
      'SAAS',
    );
    expect(logos.upload).not.toHaveBeenCalled();
  });
});
