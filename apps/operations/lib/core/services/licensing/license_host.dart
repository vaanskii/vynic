import 'package:flutter/material.dart';
import '../../../apps/windows_pos/screens/pos_first_run.dart';
import '../database_service.dart';
import '../edge/pos_enrollment_service.dart';
import '../pos/pos_locale.dart';
import 'subscription_license.dart';

class LicenseHost extends StatefulWidget {
  const LicenseHost({
    super.key,
    required this.child,
    this.license,
    this.navigatorKey,
    this.setupBuilder,
  });
  final Widget child;
  final SubscriptionLicense? license;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget Function(bool enrollmentOnly)? setupBuilder;
  @override
  State<LicenseHost> createState() => _LicenseHostState();
}

class _LicenseHostState extends State<LicenseHost> {
  bool records = false;
  bool settingUp = false;

  Widget _setupScreen(bool enrollmentOnly) =>
      widget.setupBuilder?.call(enrollmentOnly) ??
      PosFirstRun(enrollmentOnly: enrollmentOnly);

  Future<void> _openSetup(SubscriptionLicense license) async {
    final navigator = widget.navigatorKey?.currentState;
    if (settingUp || navigator == null) return;
    setState(() => settingUp = true);
    try {
      final connected = await navigator.push<bool>(
        MaterialPageRoute(builder: (_) => _setupScreen(true)),
      );
      if (!mounted) return;
      if (connected == true) {
        // First enrollment must rebuild the original first-run route so it can
        // continue with Manager setup. Established restaurant navigation stays.
        if (!DatabaseService.isSetupComplete() &&
            (DatabaseService.userBox?.isEmpty ?? true)) {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => _setupScreen(false)),
          );
        }
        setState(() => settingUp = false);
        // Enrollment grants no sales; only a fresh signed lease can do that.
        await license.verify();
      }
    } finally {
      if (mounted) setState(() => settingUp = false);
    }
  }

  bool opening = false;
  String? openError;
  String? lastReason;
  String text(BuildContext c, String ka, String en) =>
      PosLocale.code(c) == 'ka' ? ka : en;
  @override
  Widget build(BuildContext context) {
    final license = widget.license ?? SubscriptionLicense.instance;
    return AnimatedBuilder(
      animation: license,
      builder: (context, _) {
        if (!license.enabled) return widget.child;
        final lease = license.lease;
        final canSetup = widget.navigatorKey != null;
        final needsEnrollment =
            canSetup && PosEnrollmentService.needsEnrollment;
        if (lastReason != lease.reason) {
          records = false;
          lastReason = lease.reason;
        }
        final remaining = Duration(
          milliseconds: lease.remainingMs.clamp(0, 86400000),
        );
        final time =
            '${remaining.inHours}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
        final title = needsEnrollment
            ? text(
                context,
                'დააკავშირეთ ეს POS Vynic-თან',
                'Connect this POS to Vynic',
              )
            : switch (lease.reason) {
                'EXPIRED' =>
                  lease.kind == 'TRIAL'
                      ? text(
                          context,
                          'საცდელი პერიოდი დასრულდა',
                          'Your trial has ended',
                        )
                      : text(
                          context,
                          'გამოწერის ვადა ამოიწურა',
                          'Your subscription has expired',
                        ),
                'REVOKED' => text(
                  context,
                  'ლიცენზიის წვდომა შეჩერებულია',
                  'License access is suspended',
                ),
                'VALID' =>
                  lease.kind == 'TRIAL'
                      ? text(context, 'საცდელი პერიოდი', 'Trial')
                      : text(
                          context,
                          'აქტიური გამოწერა',
                          'Active subscription',
                        ),
                _ => text(
                  context,
                  'საჭიროა ონლაინ შემოწმება',
                  'Online verification required',
                ),
              };
        final warning =
            !lease.allowed ||
            license.offline ||
            lease.remainingMs <= 3600000 ||
            (lease.entitlementRemainingMs != null &&
                lease.entitlementRemainingMs! <= 3 * 86400000);

        final panel = Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  needsEnrollment
                      ? text(
                          context,
                          'დასაწყებად შეიყვანეთ თქვენი რესტორნის გვერდზე მიღებული მოწყობილობის კოდი. გაყიდვები ხელმისაწვდომი გახდება ლიცენზიის შემოწმების შემდეგ.',
                          'Enter the device code from your restaurant page to get started. Sales become available after license verification.',
                        )
                      : lease.allowed
                      ? text(
                          context,
                          'ოფლაინ მუშაობის დარჩენილი დრო: $time',
                          'Offline time remaining: $time',
                        )
                      : text(
                          context,
                          'ახალი გაყიდვები შეჩერებულია. ისტორია, ექსპორტი, სინქრონიზაცია და არსებული უცვლელი ანგარიშების დახურვა ხელმისაწვდომია.',
                          'New sales are paused. History, export, sync and settlement of unchanged existing bills remain available.',
                        ),
                ),
                if (lease.allowed && lease.entitlementRemainingMs != null)
                  Text(
                    text(
                      context,
                      'ვადის ამოწურვამდე: ${(lease.entitlementRemainingMs! / 3600000).ceil()} სთ',
                      'Expires in ${(lease.entitlementRemainingMs! / 3600000).ceil()} hours',
                    ),
                  ),
                if (license.error != null && !needsEnrollment)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      text(
                        context,
                        'შემოწმება ვერ მოხერხდა. შეამოწმეთ ინტერნეტი და სცადეთ ხელახლა.',
                        'Verification unavailable. Check your connection and retry.',
                      ),
                    ),
                  ),
                if (openError != null) Text(openError!),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (canSetup && !lease.allowed)
                      FilledButton.icon(
                        key: const Key('licenseSetup'),
                        onPressed: settingUp ? null : () => _openSetup(license),
                        icon: const Icon(Icons.phonelink_setup),
                        label: Text(
                          needsEnrollment
                              ? text(
                                  context,
                                  'POS-ის დაკავშირება',
                                  'Set up this POS',
                                )
                              : text(
                                  context,
                                  'POS-ის ხელახლა დაკავშირება',
                                  'Reconnect this POS',
                                ),
                        ),
                      ),
                    if (!needsEnrollment)
                      FilledButton(
                        onPressed: license.busy ? null : license.verify,
                        child: Text(
                          license.busy
                              ? text(context, 'მოწმდება…', 'Checking…')
                              : text(
                                  context,
                                  'ხელახლა შემოწმება',
                                  'Retry verification',
                                ),
                        ),
                      ),
                    if (!needsEnrollment)
                      OutlinedButton(
                        onPressed: opening
                            ? null
                            : () async {
                                setState(() {
                                  opening = true;
                                  openError = null;
                                });
                                try {
                                  await license.openPurchase();
                                } catch (_) {
                                  if (mounted)
                                    setState(
                                      () => openError = text(
                                        context,
                                        'გახსენით https://vynic.ge/pricing',
                                        'Open https://vynic.ge/pricing',
                                      ),
                                    );
                                }
                                if (mounted) setState(() => opening = false);
                              },
                        child: Text(
                          text(
                            context,
                            'შეძენა / განახლება',
                            'Purchase / renew',
                          ),
                        ),
                      ),
                    if (!lease.allowed && !records)
                      TextButton(
                        onPressed: () => setState(() => records = true),
                        child: Text(
                          text(
                            context,
                            'ისტორია და არსებული ანგარიშები',
                            'Records and existing bills',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        final blocked = !lease.allowed && !records && !settingUp;
        return Stack(
          children: [
            Offstage(
              offstage: blocked,
              child: Column(
                children: [
                  if (warning && !blocked && !settingUp)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .45,
                      ),
                      child: SingleChildScrollView(child: panel),
                    ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
            if (blocked)
              Positioned.fill(
                child: Material(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: panel,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
