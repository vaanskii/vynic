import { Injectable } from '@nestjs/common';

/** Presence uses Venue + username, never a globally ambiguous username. */
@Injectable()
export class PresenceService {
  private readonly sockets = new Map<
    string,
    { venueId: string; username: string }
  >();

  addSocket(venueId: string, username: string, socketId: string): void {
    this.sockets.set(socketId, { venueId, username });
  }

  removeSocket(socketId: string): void {
    this.sockets.delete(socketId);
  }

  getOnlineStaffUsernames(venueId: string): Set<string> {
    return new Set(
      [...this.sockets.values()]
        .filter((s) => s.venueId === venueId)
        .map((s) => s.username),
    );
  }
}
