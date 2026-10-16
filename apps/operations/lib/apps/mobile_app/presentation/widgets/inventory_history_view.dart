import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vynic/core/models/inventory_history_page.dart';
import 'package:vynic/core/services/manager_app/inventory_history_export.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';

class InventoryHistoryView extends StatefulWidget {
  const InventoryHistoryView({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.filters,
    this.saveCsv,
    this.emptyLabel = 'ჩანაწერები ვერ მოიძებნა',
  });
  final InventoryHistoryLoader load;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  final Map<String, dynamic> filters;
  final Future<void> Function(String)? saveCsv;
  final String emptyLabel;
  @override
  State<InventoryHistoryView> createState() => _InventoryHistoryViewState();
}

class _InventoryHistoryViewState extends State<InventoryHistoryView> {
  final _rows = <Map<String, dynamic>>[];
  String? _cursor;
  bool _loading = false, _exporting = false, _completeSource = true;
  Object? _error;
  Map<String, dynamic>? _window;
  int _generation = 0;
  String get _session =>
      '${ApiConfig.baseUrl}:${AuthTokenService.token}:${AuthTokenService.username}:${AuthTokenService.venueCode}';
  late final String _originSession = _session;

  void _requireSession() {
    if (_originSession == _session) return;
    _rows.clear();
    _cursor = null;
    _window = null;
    throw StateError('Manager session changed; reopen history');
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant InventoryHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.filters) != jsonEncode(widget.filters))
      _fetch(refresh: true);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (_loading && !refresh) return;
    if (refresh) {
      _generation++;
      _rows.clear();
      _cursor = null;
      _window = null;
    }
    final generation = _generation;
    final session = _session;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _requireSession();
      final page = await widget.load(_cursor);
      if (!mounted || generation != _generation) return;
      _requireSession();
      if (session != _session) throw StateError('Manager session changed');
      if (_window != null && jsonEncode(_window) != jsonEncode(page.window))
        throw StateError('History window changed');
      final ids = _rows.map((r) => r['id']).toSet();
      for (final r in page.items) {
        if (r['id'] is! String || !ids.add(r['id']))
          throw StateError('Invalid history identity');
      }
      if (page.nextCursor != null &&
          (page.nextCursor == _cursor || page.items.isEmpty))
        throw StateError('Invalid history cursor');
      setState(() {
        _rows.addAll(page.items);
        _cursor = page.nextCursor;
        _window = page.window;
        _completeSource = page.completeSource;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _export(BuildContext anchor) async {
    final generation = _generation;
    final session = _session;
    final box = anchor.findRenderObject() as RenderBox?;
    final rect = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() => _exporting = true);
    try {
      void current() {
        if (!mounted || generation != _generation || session != _session)
          throw StateError('History view changed');
        _requireSession();
      }

      final csv = await inventoryHistoryCsv(
        widget.load,
        filters: widget.filters,
        requireCurrent: current,
      );
      current();
      if (widget.saveCsv != null) {
        await widget.saveCsv!(csv);
      } else {
        final file = XFile.fromData(
          utf8.encode(csv),
          mimeType: 'text/csv',
          name: 'inventory-history.csv',
        );
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          final location = await getSaveLocation(
            suggestedName: 'inventory-history.csv',
            acceptedTypeGroups: const [
              XTypeGroup(label: 'CSV', extensions: ['csv']),
            ],
          );
          current();
          if (location != null) await file.saveTo(location.path);
        } else {
          await Share.shareXFiles(
            [file],
            fileNameOverrides: ['inventory-history.csv'],
            sharePositionOrigin: rect,
          );
        }
      }
    } catch (e) {
      if (mounted && generation == _generation)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'სრული ისტორიის ექსპორტი ვერ დასრულდა. სცადეთ თავიდან.',
            ),
          ),
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'ჩატვირთულია: ${_rows.length}${_cursor != null ? ' · გაგრძელება ქვემოთ' : ''}',
            ),
            TextButton(
              onPressed: _exporting ? null : () => _fetch(refresh: true),
              child: const Text('განახლება'),
            ),
            if (_completeSource)
              Builder(
                builder: (anchor) => TextButton.icon(
                  onPressed: _exporting || _loading
                      ? null
                      : () => _export(anchor),
                  icon: const Icon(Icons.download),
                  label: Text(_exporting ? 'ექსპორტი…' : 'სრული CSV ექსპორტი'),
                ),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'ახალი ჩანაწერები გამოჩნდება განახლების შემდეგ. აღდგენის მდგომარეობა მოწმდება თითოეული მოთხოვნისას.',
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _rows.length + 1,
          itemBuilder: (context, i) {
            if (i < _rows.length) return widget.itemBuilder(_rows[i]);
            return Column(
              children: [
                if (_error != null) ...[
                  const Text('ისტორია ვერ ჩაიტვირთა'),
                  TextButton(
                    onPressed: _loading ? null : _fetch,
                    child: const Text('ხელახლა ცდა'),
                  ),
                ] else if (_loading)
                  const CircularProgressIndicator()
                else if (_cursor != null)
                  TextButton(
                    onPressed: _fetch,
                    child: const Text('მეტის ჩატვირთვა'),
                  )
                else if (_rows.isEmpty)
                  Text(widget.emptyLabel),
              ],
            );
          },
        ),
      ),
    ],
  );
}
