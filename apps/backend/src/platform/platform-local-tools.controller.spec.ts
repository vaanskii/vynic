import {
  localDeletionControllers,
  PlatformLocalToolsController,
} from './platform-local-tools.controller';
import { localDockerEnabled } from '../local-tools/local-docker-guard';
jest.mock('../local-tools/local-docker-guard', () => ({
  localDockerEnabled: jest.fn(),
}));
describe('local deletion route registration', () => {
  it('has no deletion controller in production', () => {
    jest.mocked(localDockerEnabled).mockReturnValue(false);
    expect(localDeletionControllers()).toEqual([]);
    expect(() =>
      new PlatformLocalToolsController({} as never).venue(
        {} as never,
        'anything',
        {},
      ),
    ).toThrow('Not Found');
  });
  it('registers only the narrow local controller after the full guard passes', () => {
    jest.mocked(localDockerEnabled).mockReturnValue(true);
    expect(localDeletionControllers()).toEqual([PlatformLocalToolsController]);
  });
});
