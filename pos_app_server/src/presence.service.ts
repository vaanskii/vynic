import { Injectable } from '@nestjs/common';

/**
 * Tracks manager mobile sockets authenticated via JWT (username → socket ids).
 */
@Injectable()
export class PresenceService {
  private readonly usernameToSockets = new Map<string, Set<string>>();

  addSocket(username: string, socketId: string): void {
    let set = this.usernameToSockets.get(username);
    if (!set) {
      set = new Set();
      this.usernameToSockets.set(username, set);
    }
    set.add(socketId);
  }

  removeSocket(socketId: string): void {
    for (const [user, set] of this.usernameToSockets) {
      if (set.delete(socketId) && set.size === 0) {
        this.usernameToSockets.delete(user);
      }
    }
  }

  isOnline(username: string): boolean {
    return (this.usernameToSockets.get(username)?.size ?? 0) > 0;
  }

  /** Usernames that currently have ≥1 authenticated socket connection. */
  getOnlineStaffUsernames(): Set<string> {
    return new Set(this.usernameToSockets.keys());
  }
}
