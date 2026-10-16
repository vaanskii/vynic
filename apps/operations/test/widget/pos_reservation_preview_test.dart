import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_menu_preview.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import '../support/pos_visual_capture.dart';

void main() {
  setUpAll(loadPosVisualFonts);
  for (final scale in [1.0, 1.5]) {
    for (final empty in [false, true]) {
      testWidgets(
        'reservation preview $scale / empty=$empty keeps details and total through repeated close',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 768);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final reservation = Reservation(
            id: 'synthetic',
            customerName: 'ნინო საცდელი',
            customerPhone: '555000000',
            tableNumbers: const [],
            reservationDate: DateTime(2026, 10, 15),
            reservationTime: '20:30',
            numberOfGuests: 4,
            createdAt: DateTime(2026, 10, 15),
            createdBy: 'synthetic',
            preOrderItems: empty
                ? []
                : [
                    for (var i = 0; i < 12; i++)
                      OrderItem(
                        itemKey: '$i',
                        itemName: 'ჩაქაფული ტარხუნით და თეთრი ღვინით $i',
                        unitPrice: 10,
                        quantity: 2,
                        total: 20,
                        comment: 'მარილის გარეშე',
                      ),
                  ],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: PosTheme.light,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => RepaintBoundary(
                key: posVisualKey,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: PosScaledSurface(scale: 1, child: child!),
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => HomeReservationMenuPreview.show(
                      context: context,
                      reservation: reservation,
                      primaryColor: VynicFloorTokens.accentStrong,
                      textPrimary: VynicFloorTokens.text,
                      mutedText: VynicFloorTokens.textMuted,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          for (var cycle = 0; cycle < 2; cycle++) {
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            expect(
              find.text('ჯამი: ₾${empty ? '0.00' : '240.00'}').hitTestable(),
              findsOneWidget,
            );
            expect(
              find.text('ერთეულის რაოდენობა: ${empty ? 0 : 24}').hitTestable(),
              findsOneWidget,
            );
            if (!empty) {
              expect(find.text('მარილის გარეშე'), findsNothing);
              expect(find.text('შენიშვნა: მარილის გარეშე'), findsWidgets);
            } else {
              expect(
                find.text('ამ რეზერვაციას არ აქვს დამატებული მენიუ.'),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
            if (!empty && scale == 1 && cycle == 0)
              await capturePosVisual(tester, 'reservation-menu-preview');
            await tester.tap(find.text('დახურვა'));
            await tester.pumpAndSettle();
            expect(reservation.preOrderItems!.length, empty ? 0 : 12);
          }
        },
      );
    }
  }
}
