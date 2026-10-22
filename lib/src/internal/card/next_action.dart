/// CONTRACT §16.7 step 4 (`card_next_action.json`): what a `/pay` or
/// `/three-ds` payload asks the SDK to do next. Pure.
library;

import '../url_policy.dart';

/// The SDK's next step after `/pay` or `/three-ds`.
sealed class NextAction {
  const NextAction();
}

/// Open the 3DS sheet and POST [form] to [url].
final class ChallengeAction extends NextAction {
  /// Creates a challenge step.
  const ChallengeAction({required this.url, required this.form});

  /// The bank's ACS page (absolute https).
  final String url;

  /// The form pairs (`creq`, …), in order. Never logged.
  final List<(String, String)> form;

  @override
  String toString() => 'ChallengeAction(<redacted>)';
}

/// Run the 3-D Secure Method in hidden WebViews, then poll `/three-ds`.
final class MethodAction extends NextAction {
  /// Creates a method step.
  const MethodAction({this.methodUrl, this.methodData, this.methodUrlServer});

  /// Where to POST `threeDSMethodData` (step 1), when set.
  final String? methodUrl;

  /// The `threeDSMethodData` value. Never logged.
  final String? methodData;

  /// Where to send an empty POST (step 2), when set.
  final String? methodUrlServer;

  @override
  String toString() => 'MethodAction(<redacted>)';
}

/// Wait 1 s, then poll `/three-ds`.
final class WaitAction extends NextAction {
  /// Creates a wait step.
  const WaitAction();
}

/// Open the 3DS sheet with [url] (GET).
final class RedirectAction extends NextAction {
  /// Creates a redirect step.
  const RedirectAction(this.url);

  /// The page to open (absolute https).
  final String url;

  @override
  String toString() => 'RedirectAction(<redacted>)';
}

/// Poll the order status.
final class CheckStatusAction extends NextAction {
  /// Creates a status step.
  const CheckStatusAction();
}

/// The payload could not be understood.
final class InvalidAction extends NextAction {
  /// Creates an invalid step.
  const InvalidAction();
}

/// Classifies [payload]. Every URL must be absolute https, otherwise the
/// step is [InvalidAction]. `clientRequest` keeps only entries whose key is
/// a string and whose value is a string or `null` (`null` becomes `""`).
NextAction classifyNextAction(Object? payload) {
  if (payload is! Map) return const InvalidAction();
  switch (payload['nextAction']) {
    case 'THREE_DS':
      final List<(String, String)> pairs = _clientRequest(
        payload['clientRequest'],
      );
      final Object? accessUrl = payload['accessUrl'];
      if (accessUrl != null && accessUrl != '') {
        if (accessUrl is! String || !isAbsoluteHttpsUrl(accessUrl)) {
          return const InvalidAction();
        }
        return ChallengeAction(url: accessUrl, form: pairs);
      }
      final Map<String, String> values = <String, String>{
        for (final (String key, String value) in pairs) key: value,
      };
      String? present(String key) {
        final String? value = values[key];
        return value == null || value.isEmpty ? null : value;
      }

      final String? methodUrl = present('threeDSMethodUrl');
      final String? methodUrlServer = present('threeDSMethodUrlServer');
      if ((methodUrl != null && !isAbsoluteHttpsUrl(methodUrl)) ||
          (methodUrlServer != null && !isAbsoluteHttpsUrl(methodUrlServer))) {
        return const InvalidAction();
      }
      return MethodAction(
        methodUrl: methodUrl,
        methodData: present('threeDSMethodData'),
        methodUrlServer: methodUrlServer,
      );
    case 'WAIT':
      return const WaitAction();
    case 'REDIRECT':
      final Object? url = payload['redirectUrl'];
      if (url is! String || !isAbsoluteHttpsUrl(url)) {
        return const InvalidAction();
      }
      return RedirectAction(url);
    case 'CHECK_STATUS':
      return const CheckStatusAction();
  }
  return const InvalidAction();
}

List<(String, String)> _clientRequest(Object? raw) {
  if (raw is! List) return const <(String, String)>[];
  return <(String, String)>[
    for (final Object? entry in raw)
      if (entry is Map &&
          entry['key'] is String &&
          (entry['value'] == null || entry['value'] is String))
        (entry['key']! as String, (entry['value'] as String?) ?? ''),
  ];
}

/// The `application/x-www-form-urlencoded` body of [pairs].
String formUrlEncode(List<(String, String)> pairs) => pairs
    .map(
      ((String, String) p) =>
          '${Uri.encodeQueryComponent(p.$1)}=${Uri.encodeQueryComponent(p.$2)}',
    )
    .join('&');
