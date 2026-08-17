import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/ui/vynic_colors.dart';

const Color _borderColor = Color(0xFFE5E7EB);
const Color _panelSoft = Color(0xFFF9FAFB);
const Color _textPrimary = Color(0xFF111827);
const Color _textMuted = Color(0xFF6B7280);

/// Display & interface — its own management-centre section.
///
/// It used to be one card among many inside Settings, which buried controls
/// that change how the whole POS is laid out. Here each control also states
/// what it currently resolves to, because several of them only bite in
/// combination (density is only honoured in Fixed mode, for instance) and that
/// was impossible to tell from the old card.
class AdminDisplaySection extends StatelessWidget {
  const AdminDisplaySection({
    super.key,
    required this.displaySettings,
    required this.onDisplaySettingsChanged,
    required this.isSaving,
    required this.onSave,
  });

  final PosDisplaySettings displaySettings;
  final ValueChanged<PosDisplaySettings> onDisplaySettingsChanged;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.sizeOf(context);
    final layoutClass = displaySettings.layoutClassForWidth(windowSize.width);
    final effectiveDensity = displaySettings.effectiveDensityForWidth(
      windowSize.width,
    );
    final densityIsDerived =
        displaySettings.displayMode == PosDisplayMode.automatic;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionHeader(
            icon: Icons.desktop_windows_outlined,
            title: 'ეკრანი და ინტერფეისი',
            subtitle:
                'როგორ იშლება POS ამ ტერმინალზე — მასშტაბი, სიმკვრივე, '
                'გვერდითი პანელი და მაგიდის ფილების ზომა.',
          ),
          const SizedBox(height: 14),
          AdminPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final tiles = [
                      _DisplaySummaryTile(
                        label: 'ფანჯრის ზომა',
                        value:
                            '${windowSize.width.round()} x '
                            '${windowSize.height.round()}',
                        icon: Icons.monitor_outlined,
                      ),
                      _DisplaySummaryTile(
                        label: 'აქტიური განლაგება',
                        value: displaySettings.activeLayoutLabel(windowSize),
                        icon: Icons.view_compact_alt_outlined,
                      ),
                      _DisplaySummaryTile(
                        label: 'ზომის კლასი',
                        value: layoutClass.label.toUpperCase(),
                        icon: Icons.straighten_outlined,
                      ),
                    ];
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i != 0) const SizedBox(height: 10),
                            tiles[i],
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        for (var i = 0; i < tiles.length; i++) ...[
                          if (i != 0) const SizedBox(width: 12),
                          Expanded(child: tiles[i]),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _DisplayControlBlock(
                  title: 'რეჟიმი',
                  helper:
                      'ავტომატური — სიმკვრივეს ფანჯრის სიგანე ირჩევს. '
                      'ფიქსირებული — თქვენი არჩევანი მოქმედებს ყოველთვის.',
                  child: _OptionGroup<PosDisplayMode>(
                    value: displaySettings.displayMode,
                    options: const [
                      _OptionItem(PosDisplayMode.automatic, 'ავტომატური'),
                      _OptionItem(PosDisplayMode.fixed, 'ფიქსირებული'),
                    ],
                    onChanged: (value) => onDisplaySettingsChanged(
                      displaySettings.copyWith(displayMode: value),
                    ),
                  ),
                ),
                _DisplayControlBlock(
                  title: 'სიმკვრივე',
                  helper: densityIsDerived
                      ? 'ავტომატურ რეჟიმში ახლა მოქმედებს '
                            '„${_densityLabel(effectiveDensity)}“. არჩევა '
                            'რეჟიმს ავტომატურად გადაიყვანს ფიქსირებულზე.'
                      : 'კომპაქტური მეტს ათავსებს 1024 x 768 ეკრანზე.',
                  child: _OptionGroup<PosUiDensity>(
                    value: displaySettings.density,
                    options: const [
                      _OptionItem(PosUiDensity.compact, 'კომპაქტური'),
                      _OptionItem(PosUiDensity.comfortable, 'თავისუფალი'),
                    ],
                    // Choosing a density means "use this one" — so it also
                    // flips the mode to Fixed. Without that, picking a density
                    // in Automatic mode did nothing at all, which is what made
                    // this control look broken.
                    onChanged: (value) => onDisplaySettingsChanged(
                      displaySettings.copyWith(
                        density: value,
                        displayMode: PosDisplayMode.fixed,
                      ),
                    ),
                  ),
                ),
                _DisplayControlBlock(
                  title: 'მასშტაბი',
                  helper:
                      'ზრდის მთელ ინტერფეისს. ეს არ არის გეგმის მასშტაბი — '
                      'სართულის რედაქტორს თავისი zoom აქვს.',
                  child: _OptionGroup<int>(
                    value: displaySettings.scalePercent,
                    options: const [
                      _OptionItem(90, '90%'),
                      _OptionItem(100, '100%'),
                      _OptionItem(110, '110%'),
                    ],
                    onChanged: (value) => onDisplaySettingsChanged(
                      displaySettings.copyWith(scalePercent: value),
                    ),
                  ),
                ),
                _DisplayControlBlock(
                  title: 'გვერდითი პანელი',
                  helper:
                      'ჩაკეცილი ათავისუფლებს ~160 px-ს. არჩევა გადაწონის '
                      'ხელით ჩაკეცვას მთავარ ეკრანზე.',
                  child: _OptionGroup<PosSidebarDefault>(
                    value: displaySettings.sidebarDefault,
                    options: const [
                      _OptionItem(PosSidebarDefault.automatic, 'ავტომატური'),
                      _OptionItem(PosSidebarDefault.expanded, 'გაშლილი'),
                      _OptionItem(PosSidebarDefault.collapsed, 'ჩაკეცილი'),
                    ],
                    onChanged: (value) => onDisplaySettingsChanged(
                      displaySettings.copyWith(sidebarDefault: value),
                    ),
                  ),
                ),
                _DisplayControlBlock(
                  title: 'მაგიდის ფილის ზომა',
                  helper:
                      'დიდი ფილები სენსორულ ეკრანზე უფრო მოსახერხებელია. '
                      'ავტომატური ზომას ფანჯარას უსადაგებს.',
                  child: _OptionGroup<PosTableTileSize>(
                    value: displaySettings.tableTileSize,
                    options: const [
                      _OptionItem(PosTableTileSize.automatic, 'ავტომატური'),
                      _OptionItem(PosTableTileSize.small, 'პატარა'),
                      _OptionItem(PosTableTileSize.medium, 'საშუალო'),
                      _OptionItem(PosTableTileSize.large, 'დიდი'),
                    ],
                    onChanged: (value) => onDisplaySettingsChanged(
                      displaySettings.copyWith(tableTileSize: value),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _SwitchBlock(
                  icon: Icons.fullscreen_outlined,
                  title: 'სრულეკრანიანი POS',
                  subtitle:
                      'მალავს ცვლისა და ლოკაციის დეტალებს და ითხოვს '
                      'სრულ ეკრანს.',
                  value: displaySettings.fullscreenPosMode,
                  onChanged: (value) => onDisplaySettingsChanged(
                    displaySettings.copyWith(fullscreenPosMode: value),
                  ),
                ),
                const SizedBox(height: 20),
                AdminActionRow(
                  children: [
                    SizedBox(
                      width: 280,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : onSave,
                        style: AdminFormButtons.primary(),
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: Text(isSaving ? 'ინახება...' : 'შენახვა'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'ცვლილებები მაშინვე ჩანს ეკრანზე; შენახვა მათ ტერმინალზე '
                  'ინახავს გადატვირთვის შემდეგაც.',
                  style: TextStyle(fontSize: 11.5, color: _textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _densityLabel(PosUiDensity density) {
    return density == PosUiDensity.comfortable ? 'თავისუფალი' : 'კომპაქტური';
  }
}

class _SwitchBlock extends StatelessWidget {
  const _SwitchBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: VynicColors.textMuted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: VynicColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DisplaySummaryTile extends StatelessWidget {
  const _DisplaySummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6E3DE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: VynicColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayControlBlock extends StatelessWidget {
  const _DisplayControlBlock({
    required this.title,
    required this.helper,
    required this.child,
  });

  final String title;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: VynicColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                helper,
                style: const TextStyle(
                  color: VynicColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 10), child],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              Flexible(flex: 2, child: child),
            ],
          );
        },
      ),
    );
  }
}

class _OptionItem<T> {
  const _OptionItem(this.value, this.label);

  final T value;
  final String label;
}

class _OptionGroup<T> extends StatelessWidget {
  const _OptionGroup({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_OptionItem<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final option in options)
          _OptionPill<T>(
            option: option,
            selected: option.value == value,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _OptionPill<T> extends StatelessWidget {
  const _OptionPill({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _OptionItem<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? VynicColors.accent : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? VynicColors.accent : VynicColors.border,
            ),
          ),
          child: Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : VynicColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
