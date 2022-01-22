import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filter_plugin/filter_plugin.dart';

void main() {
  const MethodChannel channel = MethodChannel('filter_plugin');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await FilterPlugin.platformVersion, '42');
  });
}
