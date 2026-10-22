import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../card/card_flow.dart';
import '../card/three_ds_policy.dart';
import '../card/three_ds_website_data.dart';
import '../logger.dart';
import '../native_bridge.dart';
import '../strings.dart';
import 'glyphs.dart';
import 'presenter.dart';
import 'style.dart';

part 'three_ds_sheet.dart';

/// Key of the sheet's close (✕) button.
const Key closeButtonKey = ValueKey<String>('payriff.close');

/// Key of the header, which drags the sheet.
const Key headerKey = ValueKey<String>('payriff.header');

/// Key of every "Try again" button.
const Key retryButtonKey = ValueKey<String>('payriff.retry');

/// Key of the "Close" button of the page-load error.
const Key doneButtonKey = ValueKey<String>('payriff.done');

/// The most JavaScript dialogs (`alert`, `confirm`, `prompt`) the 3-D Secure
/// sheet shows on iOS; later ones are answered without showing them, so a
/// page cannot trap the customer in a dialog loop.
const int maxDialogsPerPage = 3;

class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.style,
    required this.title,
    required this.closeLabel,
    required this.closeEnabled,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final SheetStyle style;
  final String title;
  final String closeLabel;
  final bool closeEnabled;
  final VoidCallback onClose;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      onVerticalDragCancel: onDragCancel,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: style.grabber,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            ConstrainedBox(
              // Grows with large accessibility text sizes.
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                children: <Widget>[
                  // Balances the close button, so the title stays centred.
                  const SizedBox(width: 12 + 44),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: style.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  _CloseButton(
                    style: style,
                    label: closeLabel,
                    enabled: closeEnabled,
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.style,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final SheetStyle style;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: closeButtonKey,
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.4,
          duration: const Duration(milliseconds: 150),
          child: _RoundButton(style: style, glyph: Glyph.close),
        ),
      ),
    );
  }
}

/// A round toolbar button. iOS: the iOS 26 "glass" button, a 44 pt circle
/// with a frosted fill, a hairline rim and a soft shadow. Android: a filled
/// 36 dp circle.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.style, required this.glyph});

  final SheetStyle style;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    if (style.material) {
      return SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.fill,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: GlyphIcon(glyph, color: style.label, size: 18),
          ),
        ),
      );
    }
    final bool dark = style.background.computeLuminance() < 0.5;
    return SizedBox.square(
      dimension: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(
                0xFF000000,
              ).withValues(alpha: dark ? 0.4 : 0.1),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x66464650) : const Color(0xCCFFFFFF),
                border: Border.all(
                  color: dark
                      ? const Color(0x33FFFFFF)
                      : const Color(0x1F000000),
                  width: 0.5,
                ),
              ),
              child: Center(
                child: GlyphIcon(glyph, color: style.label, size: 17),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips the sheet: iOS 26 continuous corners (38 pt at the top, following
/// the display corners at the bottom), or Material's 28 dp top corners.
class _SheetClip extends StatelessWidget {
  const _SheetClip({
    required this.material,
    required this.roundBottom,
    required this.child,
  });

  final bool material;
  final bool roundBottom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (material) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: child,
      );
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(38),
        bottom: Radius.circular(roundBottom ? 44 : 0),
      ),
      child: child,
    );
  }
}

/// Covers the WebView with a native loader until the bank page has loaded,
/// so the customer never sees a blank or half-drawn web page.
class _LoadingVeil extends StatelessWidget {
  const _LoadingVeil({required this.style});

  final SheetStyle style;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: style.background,
      child: Center(child: style.spinner()),
    );
  }
}

/// An opaque panel with a spinner and a message.
class _BusyPanel extends StatelessWidget {
  const _BusyPanel({required this.style, required this.message});

  final SheetStyle style;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: style.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            style.spinner(),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(message, style: style.body),
            ),
          ],
        ),
      ),
    );
  }
}

/// An opaque panel with an icon, text and one or two buttons.
class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.style,
    required this.glyph,
    required this.tint,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final SheetStyle style;
  final Glyph glyph;
  final Color tint;
  final String? title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final String? title = this.title;
    final String? secondaryLabel = this.secondaryLabel;
    final VoidCallback? onSecondary = this.onSecondary;
    return ColoredBox(
      color: style.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  // spaceBetween instead of Spacers: the column lives in a
                  // scroll view, so its height is unbounded.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const SizedBox.shrink(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            GlyphBadge(glyph, color: tint),
                            const SizedBox(height: 20),
                            if (title != null) ...<Widget>[
                              Semantics(
                                header: true,
                                liveRegion: true,
                                child: Text(
                                  title,
                                  style: style.heading,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              message,
                              style: style.body,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            style.primaryButton(
                              key: retryButtonKey,
                              label: primaryLabel,
                              onPressed: onPrimary,
                            ),
                            if (secondaryLabel != null &&
                                onSecondary != null) ...<Widget>[
                              const SizedBox(height: 4),
                              style.secondaryButton(
                                key: doneButtonKey,
                                label: secondaryLabel,
                                onPressed: onSecondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
