import 'package:flutter/material.dart';

import 'src/home_page.dart';

void main() => runApp(const PayriffExampleApp());

/// The Payriff example: enter an order your backend created, then pay it with
/// the SDK's PayriffPaymentView in a page, a bottom sheet or a popup.
class PayriffExampleApp extends StatelessWidget {
  const PayriffExampleApp({super.key, this.home});

  /// The first screen; tests pass one with their own settings.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF4DBDC6);
    return MaterialApp(
      title: 'Payriff Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: home ?? const HomePage(),
    );
  }
}
