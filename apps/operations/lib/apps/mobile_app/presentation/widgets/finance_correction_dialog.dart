import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/finance_correction_request.dart';

class FinanceCorrectionDialog extends StatefulWidget {
  const FinanceCorrectionDialog({
    super.key,
    required this.path,
    required this.original,
    required this.scope,
    required this.requireSession,
    required this.send,
  });
  final String path, scope;
  final Map<String, dynamic> original;
  final void Function() requireSession;
  final FinanceCorrectionSend send;
  @override
  State<FinanceCorrectionDialog> createState() =>
      _FinanceCorrectionDialogState();
}

class _FinanceCorrectionDialogState extends State<FinanceCorrectionDialog> {
  final _reason = TextEditingController();
  bool _ready = false, _sending = false, _frozen = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      widget.requireSession();
      await FinanceCorrectionRequests.init();
      widget.requireSession();
      final saved = FinanceCorrectionRequests.read(widget.scope, widget.path);
      if (!mounted) return;
      setState(() {
        if (saved != null) {
          _reason.text = saved['reason'] as String;
          _frozen = true;
        }
        _ready = true;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (!_ready || _sending) return;
    if (_reason.text.trim().isEmpty || _reason.text.trim().length > 1000) {
      setState(() => _error = 'მიზეზი აუცილებელია (მაქს. 1000 სიმბოლო)');
      return;
    }
    setState(() {
      _sending = true;
      _frozen = true;
      _error = null;
    });
    try {
      await FinanceCorrectionRequests.submit(
        scope: widget.scope,
        path: widget.path,
        reason: _reason.text,
        original: widget.original,
        send: widget.send,
        requireSession: widget.requireSession,
      );
      widget.requireSession();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              '$error\nშედეგი არ დადასტურებულა. თავიდან ცდა იმავე მოთხოვნას გაიმეორებს.',
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: const Text('ჩანაწერის კორექტირება'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'საწყისი თანხა: ${widget.original['amount']} ₾\nსამუშაო თარიღი: ${widget.original['businessDate']}',
              ),
              if (widget.original['paymentDate'] != null)
                Text('გადახდის თარიღი: ${widget.original['paymentDate']}'),
              const SizedBox(height: 12),
              const Text(
                'საწყისი ჩანაწერი დარჩება ისტორიაში. დაემატება მისი სრული უარყოფითი კორექტირება და მიზეზი. ეს ასწორებს აღრიცხვას; რეალურ თანხას არ აბრუნებს.',
              ),
              const SizedBox(height: 16),
              if (!_ready && _error == null) const LinearProgressIndicator(),
              TextField(
                controller: _reason,
                enabled: _ready && !_frozen && !_sending,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'კორექტირების მიზეზი',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_frozen)
                const Text(
                  'განმეორებისას მიზეზი და მოთხოვნის იდენტიფიკატორი უცვლელია.',
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('დახურვა'),
        ),
        if (!_ready && _error != null)
          TextButton(
            onPressed: _restore,
            child: const Text('საცავის თავიდან ცდა'),
          ),
        FilledButton(
          onPressed: _ready && !_sending ? _save : null,
          child: Text(
            _sending
                ? 'ინახება…'
                : _frozen
                ? 'იგივე მოთხოვნის გამეორება'
                : 'კორექტირების შენახვა',
          ),
        ),
      ],
    ),
  );
}
