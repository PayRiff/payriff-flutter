import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The inset around a bank page (3-D Secure and the like). Bank pages are
/// built for a desktop popup and run to the edges of a phone screen; the
/// inset gives them the margins of the rest of the app (CONTRACT §9.1).
const EdgeInsets bankPageInsets = EdgeInsets.fromLTRB(16, 12, 16, 12);

/// The colour around an inset bank page: the WebView's own backdrop.
const Color bankPageBackdrop = Color(0xFFFFFFFF);

/// Colors, text styles and controls of the 3-D Secure sheet.
///
/// The Cupertino variant resolves iOS system colors (so it follows light and
/// dark mode and the elevated sheet level); the Material variant uses the
/// host app's [ColorScheme] and [TextTheme].
@immutable
final class SheetStyle {
  const SheetStyle._({
    required this.material,
    required this.background,
    required this.label,
    required this.secondaryLabel,
    required this.grabber,
    required this.fill,
    required this.accent,
    required this.warning,
    required this.title,
    required this.body,
    required this.heading,
    required this.emphasis,
  });

  /// Resolves the style for [context].
  factory SheetStyle.of(BuildContext context, {required bool material}) =>
      material ? _material(context) : _cupertino(context);

  static SheetStyle _cupertino(BuildContext context) {
    Color resolve(Color color) => CupertinoDynamicColor.resolve(color, context);
    final CupertinoThemeData theme = CupertinoTheme.of(context);
    final TextStyle base = theme.textTheme.textStyle;
    final Color label = resolve(CupertinoColors.label);
    final Color secondary = resolve(CupertinoColors.secondaryLabel);
    return SheetStyle._(
      material: false,
      background: resolve(CupertinoColors.systemBackground),
      label: label,
      secondaryLabel: secondary,
      grabber: resolve(CupertinoColors.tertiaryLabel),
      fill: resolve(CupertinoColors.tertiarySystemFill),
      accent: resolve(theme.primaryColor),
      warning: resolve(CupertinoColors.systemOrange),
      title: base.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: label,
        letterSpacing: -0.4,
      ),
      body: base.copyWith(fontSize: 15, color: secondary, letterSpacing: -0.2),
      heading: base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: label,
        letterSpacing: 0.35,
      ),
      emphasis: base.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: label,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }

  static SheetStyle _material(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final bool dark = theme.brightness == Brightness.dark;
    return SheetStyle._(
      material: true,
      background: scheme.surfaceContainerLow,
      label: scheme.onSurface,
      secondaryLabel: scheme.onSurfaceVariant,
      grabber: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      fill: scheme.surfaceContainerHighest,
      accent: scheme.primary,
      warning: dark ? const Color(0xFFFDD663) : const Color(0xFFB06000),
      title: (text.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      body: (text.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
        color: scheme.onSurfaceVariant,
      ),
      heading: (text.titleLarge ?? const TextStyle(fontSize: 22)).copyWith(
        color: scheme.onSurface,
      ),
      emphasis: (text.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }

  /// Whether this is the Material (Android) variant.
  final bool material;

  /// The sheet background.
  final Color background;

  /// Primary text.
  final Color label;

  /// Secondary text.
  final Color secondaryLabel;

  /// The drag handle.
  final Color grabber;

  /// Subtle fills, such as the close button's circle.
  final Color fill;

  /// Buttons and activity indicators.
  final Color accent;

  /// The page-load error icon.
  final Color warning;

  /// The sheet title.
  final TextStyle title;

  /// Messages.
  final TextStyle body;

  /// Message titles.
  final TextStyle heading;

  /// Button titles.
  final TextStyle emphasis;

  /// A platform-appropriate activity indicator.
  Widget spinner({bool small = false}) => material
      ? SizedBox.square(
          dimension: small ? 18 : 28,
          child: CircularProgressIndicator(
            strokeWidth: small ? 2 : 3,
            color: accent,
          ),
        )
      : CupertinoActivityIndicator(radius: small ? 9 : 14);

  /// A platform-appropriate primary button.
  Widget primaryButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: material
        ? FilledButton(key: key, onPressed: onPressed, child: Text(label))
        : GlassButton(
            key: key,
            label: label,
            onPressed: onPressed,
            prominent: true,
            style: this,
          ),
  );

  /// A platform-appropriate secondary button.
  Widget secondaryButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: material
        ? TextButton(key: key, onPressed: onPressed, child: Text(label))
        : GlassButton(
            key: key,
            label: label,
            onPressed: onPressed,
            prominent: false,
            style: this,
          ),
  );
}

/// A capsule button in the iOS 26 Liquid Glass style (the sheet itself stays
/// opaque): prominent buttons are tinted glass in the accent color, the
/// others frosted glass.
class GlassButton extends StatelessWidget {
  /// Creates a glass button.
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.prominent,
    required this.style,
  });

  /// The button title.
  final String label;

  /// Called on tap.
  final VoidCallback onPressed;

  /// Whether this is the primary (tinted) button.
  final bool prominent;

  /// The sheet style.
  final SheetStyle style;

  @override
  Widget build(BuildContext context) {
    final bool dark = style.background.computeLuminance() < 0.5;
    final Color fill = prominent
        ? style.accent.withValues(alpha: 0.9)
        : (dark ? const Color(0x4D787880) : const Color(0x99FFFFFF));
    final Color rim = const Color(
      0xFFFFFFFF,
    ).withValues(alpha: prominent ? 0.28 : (dark ? 0.18 : 0.7));
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 50),
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: rim, width: 0.8),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: style.emphasis.copyWith(
                  color: prominent ? const Color(0xFFFFFFFF) : style.label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
