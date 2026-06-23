import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AsyncVoidCallback = Future<void> Function();

class AdminPrintersSection extends StatefulWidget {
  const AdminPrintersSection({
    super.key,
    required this.kitchenPrinterController,
    required this.receiptPrinterController,
    required this.printerPortController,
    required this.isSavingPrinterSettings,
    required this.isTestingPrinters,
    required this.onSavePrinterSettings,
    required this.onTestPrinterConnections,
  });

  final TextEditingController kitchenPrinterController;
  final TextEditingController receiptPrinterController;
  final TextEditingController printerPortController;
  final bool isSavingPrinterSettings;
  final bool isTestingPrinters;
  final AsyncVoidCallback onSavePrinterSettings;
  final AsyncVoidCallback onTestPrinterConnections;

  @override
  State<AdminPrintersSection> createState() => _AdminPrintersSectionState();
}

enum _PrinterInputTarget { kitchen, receipt }

class _AdminPrintersSectionState extends State<AdminPrintersSection> {
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _accentDark = Color(0xFF0F766E);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _panel = Colors.white;
  static const Color _panelSoft = Color(0xFFF9FAFB);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _warning = Color(0xFFD97706);

  _PrinterInputTarget _activeTarget = _PrinterInputTarget.kitchen;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isBusy =>
      widget.isSavingPrinterSettings || widget.isTestingPrinters;

  TextEditingController get _activeController {
    return _activeTarget == _PrinterInputTarget.kitchen
        ? widget.kitchenPrinterController
        : widget.receiptPrinterController;
  }

  String get _activeTargetLabel {
    return _activeTarget == _PrinterInputTarget.kitchen
        ? 'სამზარეულოს IP'
        : 'ჩეკის IP';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 16 : 28,
                _isMobile ? 16 : 20,
                _isMobile ? 16 : 28,
                18,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showSidePanel = constraints.maxWidth >= 900;
                        if (!showSidePanel) {
                          return Column(
                            children: [
                              _buildPrinterPanel(),
                              const SizedBox(height: 12),
                              _buildKeyboardPanel(),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPrinterPanel()),
                            const SizedBox(width: 14),
                            SizedBox(width: 300, child: _buildKeyboardPanel()),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildInfoStrip(),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomDock(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.print_outlined, color: _accentDark),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'პრინტერები',
                  style: TextStyle(
                    color: _text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'სამზარეულოსა და ჩეკის პრინტერების ქსელური პარამეტრები.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStatusBadge(
            icon: Icons.lan_outlined,
            label: 'TCP 9100',
            color: _warning,
            background: const Color(0xFFFFFBEB),
            border: const Color(0xFFFDE68A),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterPanel() {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 16 : 18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'ქსელური პრინტერები',
                  style: TextStyle(
                    color: _text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _PrinterModeBadge(),
            ],
          ),
          const SizedBox(height: 14),
          _buildPrinterEndpoint(
            target: _PrinterInputTarget.kitchen,
            icon: Icons.soup_kitchen_outlined,
            title: 'სამზარეულო',
            subtitle: 'სამზარეულოს ჩეკები',
            controller: widget.kitchenPrinterController,
            label: 'სამზარეულოს ჩეკი IP',
            hint: 'მაგ. 192.168.100.33',
          ),
          const SizedBox(height: 10),
          _buildPrinterEndpoint(
            target: _PrinterInputTarget.receipt,
            icon: Icons.receipt_long_outlined,
            title: 'ჩეკი',
            subtitle: 'ბარისა და კლიენტის ქვითრები',
            controller: widget.receiptPrinterController,
            label: 'ბარის ჩეკი IP',
            hint: 'მაგ. 192.168.100.34',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 180,
            child: _buildSettingsTextField(
              controller: widget.printerPortController,
              label: 'პორტი',
              hint: '9100',
              keyboardType: TextInputType.number,
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterEndpoint({
    required _PrinterInputTarget target,
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    final isActive = _activeTarget == target;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _isBusy
          ? null
          : () {
              setState(() {
                _activeTarget = target;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFECFDF5) : _panelSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? _accent : _border,
            width: isActive ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isActive ? _accent : _border),
              ),
              child: Icon(icon, color: isActive ? _accentDark : _muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isActive)
                        const Icon(
                          Icons.radio_button_checked,
                          color: _accentDark,
                          size: 18,
                        )
                      else
                        const Icon(
                          Icons.radio_button_unchecked,
                          color: _muted,
                          size: 18,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildIpTextField(
                    controller: controller,
                    label: label,
                    hint: hint,
                    enabled: !_isBusy,
                    onTap: () {
                      setState(() {
                        _activeTarget = target;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'კლავიატურა',
                  style: TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildStatusBadge(
                icon: Icons.touch_app_outlined,
                label: _activeTargetLabel,
                color: _accentDark,
                background: const Color(0xFFECFDF5),
                border: const Color(0xFFA7F3D0),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: AnimatedBuilder(
              animation: _activeController,
              builder: (context, _) {
                final text = _activeController.text.trim();
                return Text(
                  text.isEmpty ? 'აირჩიეთ IP ველი' : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: text.isEmpty ? _muted : _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildKeypad(),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = <_PrinterKey>[
      _PrinterKey.text('1'),
      _PrinterKey.text('2'),
      _PrinterKey.text('3'),
      _PrinterKey.text('4'),
      _PrinterKey.text('5'),
      _PrinterKey.text('6'),
      _PrinterKey.text('7'),
      _PrinterKey.text('8'),
      _PrinterKey.text('9'),
      _PrinterKey.text('.'),
      _PrinterKey.text('0'),
      _PrinterKey.icon(Icons.backspace_outlined, 'delete'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        return OutlinedButton(
          onPressed: _isBusy ? null : () => _handleKey(key),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            foregroundColor: _text,
            side: const BorderSide(color: _border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: key.icon == null
              ? Text(
                  key.value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Icon(key.icon, size: 19),
        );
      },
    );
  }

  Widget _buildActionBar() {
    return Row(
      children: [
        Expanded(
          child: _BottomActionButton(
            icon: widget.isSavingPrinterSettings ? null : Icons.save_outlined,
            label: widget.isSavingPrinterSettings ? 'შენახვა...' : 'შენახვა',
            isPrimary: true,
            isLoading: widget.isSavingPrinterSettings,
            onPressed: widget.isSavingPrinterSettings
                ? null
                : widget.onSavePrinterSettings,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BottomActionButton(
            icon: widget.isTestingPrinters ? null : Icons.print_outlined,
            label: widget.isTestingPrinters
                ? 'შემოწმება...'
                : 'პრინტერის ტესტი',
            isLoading: widget.isTestingPrinters,
            onPressed: widget.isTestingPrinters
                ? null
                : widget.onTestPrinterConnections,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomDock() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        _isMobile ? 16 : 28,
        10,
        _isMobile ? 16 : 28,
        10,
      ),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: _buildActionBar(),
        ),
      ),
    );
  }

  Widget _buildInfoStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _accentDark, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'ამ ეტაპზე გამოიყენება მიმდინარე უსაფრთხო კონფიგურაცია: სამზარეულო + ჩეკი, ფიქსირებული პორტი 9100.',
              style: TextStyle(color: _text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onTap: onTap,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        fill: Colors.white,
      ),
    );
  }

  Widget _buildSettingsTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(label: label, hint: hint, fill: _surface),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required Color fill,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _muted),
      hintStyle: TextStyle(color: _muted.withValues(alpha: 0.62)),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accentDark, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _border.withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _border),
    );
  }

  void _handleKey(_PrinterKey key) {
    final controller = _activeController;
    if (key.value == 'delete') {
      final text = controller.text;
      if (text.isEmpty) return;
      controller.text = text.substring(0, text.length - 1);
    } else {
      controller.text = '${controller.text}${key.value}';
    }
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }
}

class _PrinterKey {
  const _PrinterKey._({required this.value, this.icon});

  factory _PrinterKey.text(String value) => _PrinterKey._(value: value);

  factory _PrinterKey.icon(IconData icon, String value) {
    return _PrinterKey._(value: value, icon: icon);
  }

  final String value;
  final IconData? icon;
}

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = false,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final background = isPrimary
        ? _AdminPrintersSectionState._accentDark
        : Colors.white;
    final foreground = isPrimary
        ? Colors.white
        : _AdminPrintersSectionState._text;
    final border = isPrimary
        ? _AdminPrintersSectionState._accentDark
        : _AdminPrintersSectionState._border;

    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 21),
            if (isLoading || icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterModeBadge extends StatelessWidget {
  const _PrinterModeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.desktop_windows_outlined,
            size: 16,
            color: Color(0xFF4338CA),
          ),
          SizedBox(width: 6),
          Text(
            'Windows POS',
            style: TextStyle(
              color: Color(0xFF3730A3),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
