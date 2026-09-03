import 'package:flutter/material.dart';

enum PosKeyboardKeyType {
  character,
  backspace,
  clear,
  shift,
  caps,
  space,
  enter,
}

class PosKeyboardKey {
  const PosKeyboardKey.character(this.value)
    : type = PosKeyboardKeyType.character,
      icon = null,
      flex = 1;

  const PosKeyboardKey.action({
    required this.type,
    required this.value,
    this.icon,
    this.flex = 1,
  });

  final PosKeyboardKeyType type;
  final String value;
  final IconData? icon;
  final int flex;
}
