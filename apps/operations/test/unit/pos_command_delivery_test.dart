import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';

/// What the Manager is allowed to tell somebody after pressing a button.
///
/// While the backend reached the POS over the LAN, a 2xx could not come back
/// before the terminal had answered, so "the request succeeded" and "the POS did
/// it" were the same fact. With a queue they are not, and the Manager has to be
/// able to tell them apart — otherwise it reports a printed check to a manager
/// standing at a printer that has not been asked yet.
void main() {
  PosCommandDelivery read(String status) =>
      PosCommandDelivery.fromResponse(<String, dynamic>{
        'success': true,
        'posDelivery': <String, dynamic>{'status': status, 'commandId': 'c1'},
      });

  test('only an outcome the POS reported counts as done', () {
    expect(read('SUCCEEDED').isDone, isTrue);
    expect(read('DELIVERED_LEGACY').isDone, isTrue);

    expect(read('QUEUED').isDone, isFalse);
    expect(read('CLAIMED').isDone, isFalse);
    expect(read('FAILED').isDone, isFalse);
    expect(read('UNAVAILABLE').isDone, isFalse);
  });

  test('a lease is not a completion', () {
    // CLAIMED means a terminal is holding the work, not that it ran it.
    expect(read('CLAIMED').isPending, isTrue);
    expect(read('QUEUED').isPending, isTrue);
    expect(read('SUCCEEDED').isPending, isFalse);
  });

  test('an older backend reports nothing, and that is not a failure', () {
    expect(
      PosCommandDelivery.fromResponse(<String, dynamic>{'success': true}),
      PosCommandDelivery.unknown,
    );
    expect(PosCommandDelivery.fromResponse(null), PosCommandDelivery.unknown);
    expect(
      PosCommandDelivery.fromResponse(<String, dynamic>{'posDelivery': 'nope'}),
      PosCommandDelivery.unknown,
    );
    // Unknown is neither done nor pending: nobody reported, so the caller
    // decides what to say rather than being handed a claim.
    expect(PosCommandDelivery.unknown.isDone, isFalse);
    expect(PosCommandDelivery.unknown.isPending, isFalse);
  });

  test('an unrecognised status is not silently read as success', () {
    expect(read('SOMETHING_NEW'), PosCommandDelivery.unknown);
  });
}
