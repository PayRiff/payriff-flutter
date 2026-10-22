import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:payriff/payriff.dart';

import 'output.dart';
import 'presentations.dart';
import 'settings.dart';

/// Reads `{"orderId", "clientSecret"}`, the JSON your server returns for a new
/// order, or the two values separated by white space.
({String orderId, String clientSecret})? parseOrder(String text) {
  String? id;
  String? secret;
  try {
    final Object? json = jsonDecode(text);
    if (json is Map<String, Object?>) {
      final Object? rawId = json['orderId'];
      final Object? rawSecret = json['clientSecret'];
      if (rawId is String) id = rawId.trim();
      if (rawSecret is String) secret = rawSecret.trim();
    }
  } on FormatException {
    final List<String> parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length == 2) (id, secret) = (parts[0], parts[1]);
  }
  if (id == null || id.isEmpty || secret == null || secret.isEmpty) {
    return null;
  }
  return (orderId: id, clientSecret: secret);
}

/// The only screen: the order your backend created, and three ways to show
/// the SDK's payment view.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.settings});

  /// Build-time settings; tests pass their own.
  final ExampleSettings? settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ExampleSettings _settings =
      widget.settings ?? ExampleSettings.fromEnvironment();
  final TextEditingController _orderId = TextEditingController();
  final TextEditingController _clientSecret = TextEditingController();
  String? _pasteError;

  @override
  void initState() {
    super.initState();
    Payriff.configure(_settings.toConfig());
    _orderId.addListener(_changed);
    _clientSecret.addListener(_changed);
  }

  @override
  void dispose() {
    _orderId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _ready =>
      _settings.hasPublishableKey &&
      _orderId.text.trim().isNotEmpty &&
      _clientSecret.text.trim().isNotEmpty;

  Future<void> _paste() async {
    final String text =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final ({String orderId, String clientSecret})? order = parseOrder(text);
    setState(() {
      _pasteError = order == null
          ? 'The clipboard has no order. Copy {"orderId", '
                '"clientSecret"} from your server first.'
          : null;
    });
    if (order == null) return;
    _orderId.text = order.orderId;
    _clientSecret.text = order.clientSecret;
  }

  Future<void> _pay(PaymentPresentation presentation) async {
    FocusScope.of(context).unfocus();
    final PayriffResult? result = await presentPayment(context, presentation, (
      orderId: _orderId.text.trim(),
      clientSecret: _clientSecret.text.trim(),
    ));
    if (result == null || !mounted) return;
    // An order is paid once; a failure before the card was sent keeps it.
    if (result is! PayriffResultFailed) {
      _orderId.clear();
      _clientSecret.clear();
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey<String>('result-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ResultView(result: result),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Payriff')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (!_settings.hasPublishableKey) ...<Widget>[
              Text(
                'Add PAYRIFF_PUBLISHABLE_KEY to example/config.json and run '
                'with --dart-define-from-file=config.json.',
                key: const ValueKey<String>('no-publishable-key'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const ValueKey<String>('order-id'),
              controller: _orderId,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'orderId',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('client-secret'),
              controller: _clientSecret,
              // The order's secret: never shown on screen.
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'clientSecret',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey<String>('paste-order'),
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste'),
              ),
            ),
            if (_pasteError != null)
              Text(
                _pasteError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 16),
            for (final PaymentPresentation presentation
                in PaymentPresentation.values) ...<Widget>[
              FilledButton(
                key: ValueKey<String>('pay-${presentation.name}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _ready ? () => _pay(presentation) : null,
                child: Text(presentation.title),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
