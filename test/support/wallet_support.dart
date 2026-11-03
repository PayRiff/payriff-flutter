import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `test/vectors/wallet.json` (CONTRACT §17).
Map<String, Object?> walletVectors() =>
    jsonDecode(File('test/vectors/wallet.json').readAsStringSync())
        as Map<String, Object?>;

/// One platform view the framework asked the platform to create.
typedef CreatedPlatformView = ({
  int id,
  String viewType,
  Map<Object?, Object?> params,
});

/// The platform side of platform views in widget tests: records each
/// `create` with its decoded creation parameters, and plays the native
/// button's tap on the view's own channel.
class FakePlatformViews {
  /// The views created so far.
  final List<CreatedPlatformView> created = <CreatedPlatformView>[];

  /// The ids of the views disposed so far.
  final List<int> disposed = <int>[];

  /// The views of [viewType] that are not disposed.
  List<CreatedPlatformView> live(String viewType) => created
      .where(
        (CreatedPlatformView v) =>
            v.viewType == viewType && !disposed.contains(v.id),
      )
      .toList();

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (
          MethodCall call,
        ) async {
          final Object? arguments = call.arguments;
          switch (call.method) {
            case 'create':
              final Map<Object?, Object?> args =
                  arguments! as Map<Object?, Object?>;
              final Object? params = args['params'];
              created.add((
                id: args['id']! as int,
                viewType: args['viewType']! as String,
                params: params is Uint8List
                    ? const StandardMessageCodec().decodeMessage(
                            ByteData.sublistView(params),
                          )
                          as Map<Object?, Object?>
                    : const <Object?, Object?>{},
              ));
              // Android's texture views answer with a texture id.
              return args.containsKey('width') ? 1 : null;
            case 'resize':
              final Map<Object?, Object?> args =
                  arguments! as Map<Object?, Object?>;
              return <String, Object?>{
                'width': args['width'],
                'height': args['height'],
              };
            case 'dispose':
              final Object? id = arguments is Map ? arguments['id'] : arguments;
              if (id is int) disposed.add(id);
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null),
    );
  }

  /// The native button of [view] reports a tap, as the plugin does.
  Future<void> tap(CreatedPlatformView view) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            '${view.viewType}/${view.id}',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('tap'),
            ),
            (ByteData? reply) {},
          );
}
