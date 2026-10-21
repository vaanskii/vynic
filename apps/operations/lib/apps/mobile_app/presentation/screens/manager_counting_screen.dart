import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import '../widgets/manager_design_components.dart';
import 'mobile_calculator_screen.dart';
import 'mobile_counted_menus_screen.dart';

/// One navigation destination for creating and managing counted menus.
/// Existing calculation, save, edit, reservation and print workflows own data.
class ManagerCountingScreen extends StatefulWidget {
  const ManagerCountingScreen({super.key, required this.user});
  final User user;
  @override
  State<ManagerCountingScreen> createState() => _ManagerCountingState();
}

class _ManagerCountingState extends State<ManagerCountingScreen> {
  int _tab = 0, _calculation = 0, _saved = 0;
  void _select(int value) => setState(() {
    if (value == 1 && _tab != 1) _saved++;
    _tab = value;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('დათვლა')),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ManagerSegments(
                labels: const ['ახალი დათვლა', 'შენახული დათვლები'],
                keys: const [
                  ValueKey('count-tab-new'),
                  ValueKey('count-tab-saved'),
                ],
                selected: _tab,
                onSelect: _select,
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                MobileCalculatorScreen(
                  key: ValueKey('new-count-$_calculation'),
                  isCountMode: true,
                  embedded: true,
                  onSaved: () => setState(() {
                    _calculation++;
                    _saved++;
                    _tab = 1;
                  }),
                ),
                MobileCountedMenusScreen(
                  key: ValueKey('saved-count-$_saved'),
                  user: widget.user,
                  embedded: true,
                  onNew: () => _select(0),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
