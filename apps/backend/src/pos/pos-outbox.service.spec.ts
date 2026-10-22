import { PosOutboxService } from './pos-outbox.service';
import { PosCommandDispatcher } from './pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../shared/contracts/edge-command';

describe('durable legacy delivery admission', () => {
  it('propagates persistence failure instead of reporting a nonexistent queue entry', async () => {
    const failure = new Error('synthetic queue unavailable');
    const db = {
      device: { findFirst: jest.fn().mockResolvedValue(null) },
      posCallbackOutbox: { create: jest.fn().mockRejectedValue(failure) },
    };
    const outbox = new PosOutboxService(db as never, {} as never);
    const processDue = jest.spyOn(outbox, 'processDue');
    const dispatcher = new PosCommandDispatcher(
      db as never,
      {} as never,
      {} as never,
      outbox,
    );
    await expect(
      dispatcher.dispatch(
        { venueId: 'synthetic-venue' },
        {
          type: EdgeCommandTypes.STAFF_CREATE,
          payload: { username: 'synthetic' },
        },
      ),
    ).rejects.toBe(failure);
    expect(processDue).not.toHaveBeenCalled();
  });
});
