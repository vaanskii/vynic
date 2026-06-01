import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PinButton extends StatelessWidget {
  final String number;
  final VoidCallback onPressed;
  final bool isSpecial;

  const PinButton({
    super.key,
    required this.number,
    required this.onPressed,
    this.isSpecial = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final isSmallScreen = screenHeight <= 768 || screenWidth <= 1024;
    final buttonSize = isMobile ? 56.0 : (isSmallScreen ? 64.0 : 80.0);
    final fontSize = isMobile 
        ? (isSpecial ? 14 : 18)
        : (isSmallScreen ? (isSpecial ? 16 : 20) : (isSpecial ? 20 : 24));
    const primaryColor = Color(0xFF1E3A8A);
    final Color baseColor = isSpecial ? const Color(0xFFE2E8F0) : Colors.white;
    final Color textColor = isSpecial ? const Color(0xFF1E293B) : primaryColor;
    final BorderSide borderSide = BorderSide(
      color: isSpecial
          ? const Color(0xFFCBD5E1)
          : primaryColor.withValues(alpha: 0.35),
      width: 1.5,
    );

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: baseColor,
          foregroundColor: textColor,
          minimumSize: Size(buttonSize, buttonSize),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: borderSide,
          ),
          shadowColor: Colors.transparent,
        ),
        child: Text(
          number,
          style: TextStyle(
            fontSize: fontSize.toDouble(),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class PinPad extends StatelessWidget {
  final Function(String) onDigitPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onDeletePressed;
  final bool showDecimalButton;

  const PinPad({
    super.key,
    required this.onDigitPressed,
    required this.onClearPressed,
    required this.onDeletePressed,
    this.showDecimalButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final isSmallScreen = screenHeight <= 768 || screenWidth <= 1024;
    final spacing = isMobile ? 6.0 : (isSmallScreen ? 8.0 : 15.0);

    final maxWidth = showDecimalButton
        ? (isMobile ? 240.0 : (isSmallScreen ? 280.0 : 360.0))
        : (isMobile ? 200.0 : (isSmallScreen ? 240.0 : 300.0));

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        children: [
          // Row 1: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              PinButton(number: '1', onPressed: () => onDigitPressed('1')),
              PinButton(number: '2', onPressed: () => onDigitPressed('2')),
              PinButton(number: '3', onPressed: () => onDigitPressed('3')),
            ],
          ),
          SizedBox(height: spacing),

          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              PinButton(number: '4', onPressed: () => onDigitPressed('4')),
              PinButton(number: '5', onPressed: () => onDigitPressed('5')),
              PinButton(number: '6', onPressed: () => onDigitPressed('6')),
            ],
          ),
          SizedBox(height: spacing),

          // Row 3: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              PinButton(number: '7', onPressed: () => onDigitPressed('7')),
              PinButton(number: '8', onPressed: () => onDigitPressed('8')),
              PinButton(number: '9', onPressed: () => onDigitPressed('9')),
            ],
          ),
          SizedBox(height: spacing),

          // Row 4: C, 0, optional '.', ⌫
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              PinButton(
                number: 'C',
                onPressed: onClearPressed,
                isSpecial: true,
              ),
              PinButton(number: '0', onPressed: () => onDigitPressed('0')),
              if (showDecimalButton)
                PinButton(
                  number: '.',
                  onPressed: () => onDigitPressed('.'),
                  isSpecial: true,
                ),
              PinButton(
                number: '⬅',
                onPressed: onDeletePressed,
                isSpecial: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
