import 'dart:async';

import 'package:flutter/widgets.dart';

import '../card/card_flow.dart';
import '../logger.dart';
import '../strings.dart';
import 'presenter.dart';
import 'sheet.dart';

/// Presents the 3-D Secure sheet for [session] on [navigator] (the root
/// navigator): the card flow's and the wallet flows' [ThreeDsSheetOpener].
/// `null` when it cannot be shown.
ThreeDsSheet? presentThreeDsSheet(
  BuildContext context,
  NavigatorState navigator,
  bool material,
  PayriffSheetStrings strings,
  SdkLogger logger,
  ThreeDsSession session,
) {
  if (!navigator.mounted) return null;
  final SheetPresenter presenter = SheetPresenter(
    navigator: navigator,
    material: material,
    strings: strings,
  );
  try {
    final Route<void> route = presenter.buildSheetRoute(
      context,
      (BuildContext context) => PayriffThreeDsSheet(
        session: session,
        presenter: presenter,
        logger: logger,
      ),
    );
    unawaited(
      navigator.push<void>(route).whenComplete(session.onSheetDismissed),
    );
  } on Object catch (e) {
    logger.error('Could not present the 3-D Secure sheet: ${redactError(e)}');
    return null;
  }
  return _PresentedThreeDsSheet(presenter);
}

final class _PresentedThreeDsSheet implements ThreeDsSheet {
  _PresentedThreeDsSheet(this._presenter);

  final SheetPresenter _presenter;

  @override
  void close() => _presenter.closeSheet();
}
