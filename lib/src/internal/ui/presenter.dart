import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../strings.dart';

/// Key of the confirmation dialog's "continue payment" action.
const Key confirmNoKey = ValueKey<String>('payriff.confirm.no');

/// Key of the confirmation dialog's "cancel payment" action.
const Key confirmYesKey = ValueKey<String>('payriff.confirm.yes');

/// Key of the OK button of a JavaScript dialog (`dialog_ok`).
const Key jsDialogOkKey = ValueKey<String>('payriff.js.ok');

/// Key of the Cancel button of a JavaScript dialog (`dialog_cancel`).
const Key jsDialogCancelKey = ValueKey<String>('payriff.js.cancel');

/// Key of the text field of a JavaScript `prompt()` dialog.
const Key jsPromptFieldKey = ValueKey<String>('payriff.js.prompt');

/// The title of a JavaScript dialog opened by the frame at [frameUrl]: its
/// host, lower-cased, for an `http(s)` URL; otherwise `null` (no title). Like
/// a browser, the dialog names the site that opened it, so a page cannot pass
/// its prompt off as one of the app's own.
String? dialogOrigin(String frameUrl) {
  final Uri? uri = Uri.tryParse(frameUrl);
  if (uri == null || uri.host.isEmpty) return null;
  final String scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri.host.toLowerCase();
}

/// Pushes and removes the routes of one payment: the sheet and any dialog it
/// opens, all on the root navigator (CONTRACT §9.1).
final class SheetPresenter {
  /// Creates a presenter for [navigator].
  SheetPresenter({
    required this.navigator,
    required this.material,
    required this.strings,
  });

  /// Whether the Material bottom sheet should be used for [context]: on
  /// platforms other than iOS and macOS, when the app provides
  /// [MaterialLocalizations] (a `CupertinoApp` does not, and the Material
  /// sheet asserts that they exist).
  static bool prefersMaterial(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return false;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return Localizations.of<MaterialLocalizations>(
              context,
              MaterialLocalizations,
            ) !=
            null;
    }
  }

  /// The root navigator.
  final NavigatorState navigator;

  /// Whether Material routes and dialogs are used.
  final bool material;

  /// The UI strings.
  final PayriffStrings strings;

  Route<void>? _sheetRoute;
  final List<Route<Object?>> _dialogs = <Route<Object?>>[];

  /// Builds the sheet route around [builder].
  ///
  /// iOS gets a [PayriffSheetRoute] (the iOS 26 sheet look); Android a
  /// `ModalBottomSheetRoute` at about 94 % height. Neither drags by itself:
  /// the sheet's header handles drags and runs the close path, like an iOS
  /// sheet with `isModalInPresentation`.
  Route<void> buildSheetRoute(BuildContext context, WidgetBuilder builder) {
    final Route<void> route;
    if (material) {
      route = ModalBottomSheetRoute<void>(
        builder: (BuildContext context) =>
            FractionallySizedBox(heightFactor: 0.94, child: builder(context)),
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: const Color(0x00000000),
        elevation: 0,
        constraints: const BoxConstraints(maxWidth: 640),
        barrierLabel: strings[PayriffStringKey.close],
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
      );
    } else {
      route = PayriffSheetRoute<void>(
        builder: builder,
        barrierLabel: strings[PayriffStringKey.close],
      );
    }
    _sheetRoute = route;
    return route;
  }

  /// Shows the cancel confirmation (CONTRACT §9.2). Completes with `true`
  /// when the customer confirms; `false` when they continue or the dialog
  /// is dismissed.
  Future<bool> confirmCancel(BuildContext context) async {
    final String title = strings[PayriffStringKey.cancelConfirmTitle];
    final String message = strings[PayriffStringKey.cancelConfirmMessage];
    final String yes = strings[PayriffStringKey.cancelConfirmYes];
    final String no = strings[PayriffStringKey.cancelConfirmNo];
    final Route<bool> route = material
        ? DialogRoute<bool>(
            context: context,
            barrierLabel: strings[PayriffStringKey.close],
            themes: InheritedTheme.capture(
              from: context,
              to: navigator.context,
            ),
            builder: (BuildContext dialogContext) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: <Widget>[
                TextButton(
                  key: confirmNoKey,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(no),
                ),
                TextButton(
                  key: confirmYesKey,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(yes),
                ),
              ],
            ),
          )
        : CupertinoDialogRoute<bool>(
            context: context,
            // iOS alerts are not dismissed by tapping outside them.
            barrierDismissible: false,
            barrierLabel: strings[PayriffStringKey.close],
            builder: (BuildContext dialogContext) =>
                _withCupertinoLocalizations(
                  dialogContext,
                  CupertinoAlertDialog(
                    title: Text(title),
                    content: Text(message),
                    actions: <Widget>[
                      CupertinoDialogAction(
                        key: confirmNoKey,
                        isDefaultAction: true,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(no),
                      ),
                      CupertinoDialogAction(
                        key: confirmYesKey,
                        isDestructiveAction: true,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(yes),
                      ),
                    ],
                  ),
                ),
          );
    return await _pushDialog(route) ?? false;
  }

  /// Shows a JavaScript `alert()` from the page with one `dialog_ok` button
  /// (CONTRACT §10). WKWebView drops page dialogs unless the app shows them.
  /// [origin] (the page's host, see [dialogOrigin]) is the title.
  Future<void> alert(
    BuildContext context,
    String message, {
    String? origin,
  }) async {
    final Route<void> route = CupertinoDialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: strings[PayriffStringKey.dialogOk],
      builder: (BuildContext dialogContext) => _withCupertinoLocalizations(
        dialogContext,
        CupertinoAlertDialog(
          title: origin == null ? null : Text(origin),
          content: Text(message),
          actions: <Widget>[
            CupertinoDialogAction(
              key: jsDialogOkKey,
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings[PayriffStringKey.dialogOk]),
            ),
          ],
        ),
      ),
    );
    await _pushDialog(route);
  }

  /// Shows a JavaScript `confirm()` from the page with `dialog_cancel` and
  /// `dialog_ok` buttons (CONTRACT §10). Completes with `true` for OK and
  /// `false` for Cancel or when the dialog is removed. [origin] is the title.
  Future<bool> confirm(
    BuildContext context,
    String message, {
    String? origin,
  }) async {
    final Route<bool> route = CupertinoDialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: strings[PayriffStringKey.dialogCancel],
      builder: (BuildContext dialogContext) => _withCupertinoLocalizations(
        dialogContext,
        CupertinoAlertDialog(
          title: origin == null ? null : Text(origin),
          content: Text(message),
          actions: <Widget>[
            CupertinoDialogAction(
              key: jsDialogCancelKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings[PayriffStringKey.dialogCancel]),
            ),
            CupertinoDialogAction(
              key: jsDialogOkKey,
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings[PayriffStringKey.dialogOk]),
            ),
          ],
        ),
      ),
    );
    return await _pushDialog(route) ?? false;
  }

  /// Shows a JavaScript `prompt()` from the page: [message], a text field
  /// filled with [defaultText], and `dialog_cancel` and `dialog_ok` buttons
  /// (CONTRACT §10). Completes with the entered text for OK, and `null` for
  /// Cancel or when the dialog is removed. [origin] is the title.
  Future<String?> prompt(
    BuildContext context,
    String message, {
    String? defaultText,
    String? origin,
  }) {
    final Route<String> route = CupertinoDialogRoute<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: strings[PayriffStringKey.dialogCancel],
      builder: (BuildContext dialogContext) => _withCupertinoLocalizations(
        dialogContext,
        _PromptDialog(
          origin: origin,
          message: message,
          defaultText: defaultText ?? '',
          okLabel: strings[PayriffStringKey.dialogOk],
          cancelLabel: strings[PayriffStringKey.dialogCancel],
        ),
      ),
    );
    return _pushDialog(route);
  }

  Future<T?> _pushDialog<T>(Route<T> route) async {
    if (!navigator.mounted) return null;
    _dialogs.add(route);
    try {
      return await navigator.push(route);
    } finally {
      _dialogs.remove(route);
    }
  }

  /// Removes every dialog this presenter opened.
  void dismissDialogs() {
    if (!navigator.mounted) return;
    for (final Route<Object?> route in List<Route<Object?>>.of(_dialogs)) {
      if (route.isActive) navigator.removeRoute(route);
    }
  }

  /// Closes the sheet (and its dialogs) if it is still shown.
  void closeSheet() {
    dismissDialogs();
    final Route<void>? route = _sheetRoute;
    if (route == null || !route.isActive || !navigator.mounted) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  static Widget _withCupertinoLocalizations(
    BuildContext context,
    Widget child,
  ) {
    if (Localizations.of<CupertinoLocalizations>(
          context,
          CupertinoLocalizations,
        ) !=
        null) {
      return child;
    }
    return Localizations(
      locale: const Locale('en'),
      delegates: const <LocalizationsDelegate<Object?>>[
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      child: child,
    );
  }
}

/// The body of a JavaScript `prompt()` dialog; owns its text controller.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.origin,
    required this.message,
    required this.defaultText,
    required this.okLabel,
    required this.cancelLabel,
  });

  final String? origin;
  final String message;
  final String defaultText;
  final String okLabel;
  final String cancelLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.defaultText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: widget.origin == null ? null : Text(widget.origin!),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.message),
        const SizedBox(height: 12),
        CupertinoTextField(
          key: jsPromptFieldKey,
          controller: _text,
          autofocus: true,
        ),
      ],
    ),
    actions: <Widget>[
      CupertinoDialogAction(
        key: jsDialogCancelKey,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.cancelLabel),
      ),
      CupertinoDialogAction(
        key: jsDialogOkKey,
        isDefaultAction: true,
        onPressed: () => Navigator.of(context).pop(_text.text),
        child: Text(widget.okLabel),
      ),
    ],
  );
}

/// The iOS sheet route, styled after the iOS 26 system sheet at its large
/// detent: the sheet rises from the bottom over a dimmed page, leaves the
/// status bar uncovered and leaves the page behind in place (no stacked-card
/// scaling). The sheet widget draws its own rounded corners.
class PayriffSheetRoute<T> extends PopupRoute<T> {
  /// Creates the route around [builder].
  PayriffSheetRoute({required this.builder, required this.barrierLabel});

  /// Builds the sheet.
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  /// The gap between the status bar and the top of the sheet.
  static const double topGap = 10;

  @override
  Color get barrierColor => const Color(0x40000000);

  // The close path decides: a tap outside never dismisses the payment.
  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final double top = MediaQuery.paddingOf(context).top + topGap;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<Offset> position =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.fastEaseInToSlowEaseOut,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    return SlideTransition(position: position, child: child);
  }
}
