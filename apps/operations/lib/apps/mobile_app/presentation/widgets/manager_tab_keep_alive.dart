import 'package:flutter/material.dart';

/// Keeps a main shell tab mounted while swiping in [PageView].
class ManagerTabKeepAlive extends StatefulWidget {
  const ManagerTabKeepAlive({super.key, required this.child, this.storageKey});

  final Widget child;
  final PageStorageKey<String>? storageKey;

  @override
  State<ManagerTabKeepAlive> createState() => _ManagerTabKeepAliveState();
}

class _ManagerTabKeepAliveState extends State<ManagerTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(key: widget.storageKey, child: widget.child);
  }
}
