import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_format.dart';
import 'otp_store.dart';
import 'signing_key.dart';
import 'token_signer.dart';

/// How long a token lasts, as the choices you actually make.
enum _Window {
  twoHours('2 hours', Duration(hours: 2)),
  eightHours('8 hours', Duration(hours: 8)),
  oneDay('24 hours', Duration(days: 1)),
  oneWeek('7 days', Duration(days: 7)),
  ninetyDays('90 days', Duration(days: 90));

  const _Window(this.label, this.duration);
  final String label;
  final Duration duration;
}

class DevToolHomePage extends StatefulWidget {
  const DevToolHomePage({super.key});

  @override
  State<DevToolHomePage> createState() => _DevToolHomePageState();
}

class _DevToolHomePageState extends State<DevToolHomePage> {
  final TextEditingController _terminalController = TextEditingController();

  SigningKey? _key;
  bool _isLoadingKey = true;
  String? _keyError;

  OtpSeed? _otpSeed;
  String? _oneTimeCode;

  /// The everyday path. A signed token is the fallback for a terminal whose
  /// chain has run out, or a session that has to outlive the support call.
  bool _useOneTimeCode = true;

  /// A master key opens any terminal, so it needs no ID — this is the mode for
  /// a machine you have not seen yet, which is most of them.
  bool _masterKey = true;
  _Window _window = _Window.ninetyDays;
  final Set<String> _scopes = {...TokenScope.all};

  SignedToken? _token;
  String? _savedTo;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    setState(() => _isLoadingKey = true);
    final key = await SigningKeyStore.loadRemembered();
    if (!mounted) return;
    setState(() {
      _key = key;
      _otpSeed = OtpStore.load(nearKeyPath: key?.sourcePath);
      _isLoadingKey = false;
      _keyError = key == null
          ? 'No signing key loaded. Pick secrets/developer_signing_key.json.'
          : null;
    });
  }

  /// Takes the next code off the chain.
  ///
  /// The counter is written before the code is shown, so a code that gets
  /// generated and then discarded is simply skipped — the terminal's
  /// acceptance window swallows the gap. Re-issuing one would be the real
  /// problem: whoever received it second would find it already spent.
  void _generateOneTimeCode() {
    final seed = _otpSeed;
    if (seed == null) return;

    final taken = OtpStore.take(seed);
    if (taken == null) {
      setState(
        () => _keyError =
            'The code chain is exhausted. Run `dart run tool/dev_key.dart '
            'otp-seed --force` and ship a new POS build.',
      );
      return;
    }

    setState(() {
      _oneTimeCode = encodeDeveloperCode(taken.link);
      _otpSeed = OtpSeed(
        seed: seed.seed,
        nextIndex: taken.index,
        chainLength: seed.chainLength,
        sourcePath: seed.sourcePath,
      );
    });
  }

  Future<void> _pickKey() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Signing key', extensions: ['json']),
      ],
    );
    if (file == null) return;

    try {
      final key = await SigningKeyStore.loadFrom(file.path);
      if (!mounted) return;
      setState(() {
        _key = key;
        _otpSeed = OtpStore.load(nearKeyPath: key.sourcePath);
        _keyError = null;
        _token = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _keyError = 'Could not read that key file: $e');
    }
  }

  Future<void> _generate() async {
    final key = _key;
    if (key == null) return;

    final terminal = _masterKey
        ? kAnyTerminal
        : _terminalController.text.trim();
    if (!_masterKey && terminal.isEmpty) {
      setState(
        () => _keyError = 'Paste the terminal ID, or switch to a master key.',
      );
      return;
    }

    final token = await TokenSigner.sign(
      key: key,
      terminal: terminal,
      validFor: _window.duration,
      scopes: TokenScope.all.where(_scopes.contains).toList(),
    );
    if (!mounted) return;
    setState(() {
      _token = token;
      _savedTo = null;
      _keyError = null;
    });
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Token copied')));
  }

  Future<void> _saveToFile() async {
    final token = _token;
    if (token == null) return;

    final location = await getSaveLocation(
      suggestedName: token.suggestedFileName,
    );
    if (location == null) return;

    await File(location.path).writeAsString(token.value);
    if (!mounted) return;
    setState(() => _savedTo = location.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/vynic_logo.png', width: 24, height: 24),
            const SizedBox(width: 10),
            const Text('Vynic Unlocker'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Load a different signing key',
            onPressed: _pickKey,
            icon: const Icon(Icons.key),
          ),
        ],
      ),
      body: _isLoadingKey
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildKeyCard(),
                    const SizedBox(height: 16),
                    _buildModeCard(),
                    const SizedBox(height: 16),
                    if (_useOneTimeCode) ...[
                      FilledButton.icon(
                        onPressed: _otpSeed == null
                            ? null
                            : _generateOneTimeCode,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.pin),
                        label: const Text('Generate one-time code'),
                      ),
                      if (_oneTimeCode != null) ...[
                        const SizedBox(height: 20),
                        _buildCodeCard(_oneTimeCode!),
                      ],
                    ] else ...[
                      _buildTargetCard(),
                      const SizedBox(height: 16),
                      _buildWindowCard(),
                      const SizedBox(height: 16),
                      _buildScopeCard(),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _key == null ? null : _generate,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.vpn_key),
                        label: const Text('Generate token'),
                      ),
                      if (_token != null) ...[
                        const SizedBox(height: 20),
                        _buildResultCard(_token!),
                      ],
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKeyCard() {
    final key = _key;
    final theme = Theme.of(context);

    if (key == null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No signing key',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _keyError ?? '',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _pickKey,
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick key file'),
              ),
            ],
          ),
        ),
      );
    }

    final matches = key.matchesShippedBuild;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              matches ? Icons.verified : Icons.warning_amber,
              color: matches
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    matches
                        ? 'Key matches the shipped POS build'
                        : 'This key does NOT match the shipped build',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    matches
                        ? key.sourcePath
                        : 'Tokens signed with it will be rejected by every '
                              'terminal running the current build.\n'
                              '${key.sourcePath}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terminal', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _masterKey,
              onChanged: (value) => setState(() => _masterKey = value),
              title: const Text('Master key — opens any terminal'),
              subtitle: const Text(
                'No terminal ID needed. Use for a machine you have not seen, '
                'or as the token you keep in your password manager.',
              ),
            ),
            if (!_masterKey) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _terminalController,
                decoration: const InputDecoration(
                  labelText: 'Terminal ID',
                  hintText: 'Paste the ID from the POS unlock dialog',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWindowCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Valid for', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _Window.values
                  .map(
                    (window) => ChoiceChip(
                      label: Text(window.label),
                      selected: _window == window,
                      onSelected: (_) => setState(() => _window = window),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Grants', style: theme.textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _scopes.addAll(TokenScope.all)),
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _scopes.removeAll(TokenScope.destructive)),
                  child: const Text('Read-only'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TokenScope.all.map((scope) {
                final destructive = TokenScope.destructive.contains(scope);
                return FilterChip(
                  label: Text(scope),
                  selected: _scopes.contains(scope),
                  avatar: destructive
                      ? Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: theme.colorScheme.error,
                        )
                      : null,
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _scopes.add(scope);
                    } else {
                      _scopes.remove(scope);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(SignedToken token) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    token.isMasterKey
                        ? 'Master token — opens any terminal'
                        : 'Token for ${token.terminal}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Expires ${token.expiresAt.toLocal()}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                token.value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _copy(token.value),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: _saveToFile,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save as file'),
                ),
              ],
            ),
            if (_savedTo != null) ...[
              const SizedBox(height: 10),
              Text('Saved to $_savedTo', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard() {
    final theme = Theme.of(context);
    final seed = _otpSeed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.pin),
                  label: Text('One-time code'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.vpn_key),
                  label: Text('Signed token'),
                ),
              ],
              selected: {_useOneTimeCode},
              onSelectionChanged: (selection) => setState(() {
                _useOneTimeCode = selection.first;
                _oneTimeCode = null;
                _token = null;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              _useOneTimeCode
                  ? 'Sixteen characters, works once, on any terminal. No ID '
                        'needed. Opens every tool for two hours.'
                  : 'A pasted token. Use this when you need a longer session, '
                        'a terminal bound to one venue, or the code chain has '
                        'run out.',
              style: theme.textTheme.bodySmall,
            ),
            if (_useOneTimeCode) ...[
              const SizedBox(height: 10),
              if (seed == null)
                Text(
                  'No code seed found. Run `dart run tool/dev_key.dart '
                  'otp-seed` in apps/operations.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              else
                Text(
                  '${seed.remaining} codes left of ${seed.chainLength}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCodeCard(String code) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Read this out', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Spent as soon as a terminal accepts it. If it is refused, '
              'generate the next one — skipped codes cost nothing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
