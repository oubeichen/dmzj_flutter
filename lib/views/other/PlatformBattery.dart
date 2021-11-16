

import 'dart:io';

import 'package:battery/battery.dart';

class PlatformBattery extends Battery {

  final isMobilePlatform = Platform.isAndroid || Platform.isIOS;

  @override
  Future<int> get batteryLevel => isMobilePlatform ? super.batteryLevel : Future.value(100);

  @override
  Stream<BatteryState> get onBatteryStateChanged =>
      isMobilePlatform ? super.onBatteryStateChanged : Stream.value(BatteryState.full);


}