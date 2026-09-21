import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';

/// Catalog-backed POS copy; depends on locale even inside a const dialog.
class PosText extends StatelessWidget {
  const PosText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.semanticsLabel,
    this.strutStyle,
    this.textDirection,
    this.textScaler,
    this.values = const {},
  });
  final String data;
  final Map<String, String> values;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final String? semanticsLabel;
  final StrutStyle? strutStyle;
  final TextDirection? textDirection;
  final TextScaler? textScaler;
  String _message(BuildContext context) {
    var text = PosLocale.tr(context, data)!;
    for (final value in values.entries) {
      text = text.replaceAll('{${value.key}}', value.value);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) => Text(
    _message(context),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    semanticsLabel: semanticsLabel,
    strutStyle: strutStyle,
    textDirection: textDirection,
    textScaler: textScaler,
  );
}
