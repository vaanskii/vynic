/**
 * Allocates the identity of a reservation Cloud originated.
 *
 * The POS used to invent this, as `Date.now()` in milliseconds, and hand it back
 * over a synchronous LAN call. That had two costs. The booking had no id until
 * the restaurant answered, so a Cloud request could not confirm anything while
 * the POS was offline. And an at-least-once redelivery of "create this
 * reservation" produced a second reservation, because nothing tied the two
 * deliveries together.
 *
 * Naming it here fixes both: the command carries the id, the POS creates the
 * reservation only if that id is absent, and Cloud can answer its own caller
 * immediately.
 *
 * ## The shape, and why it is not a UUID
 *
 * POS-local reservation ids are 13-digit millisecond strings, and the POS still
 * mints those for bookings taken at the terminal. A Cloud id is the same
 * millisecond value followed by three random digits — 16 digits, still numeric,
 * still ordered by time.
 *
 * The extra digits are what makes a collision impossible rather than unlikely:
 * a 16-digit value can never equal a 13-digit one, so a Cloud id and a POS id
 * generated in the same millisecond are still different ids. A UUID would have
 * been the obvious choice but would have been the first non-numeric reservation
 * id in a system whose stored records, backups and website bridge have only
 * ever seen digits.
 */
export function allocatePosReservationId(now: number = Date.now()): string {
  const suffix = Math.floor(Math.random() * 1000)
    .toString()
    .padStart(3, '0');
  return `${now}${suffix}`;
}
