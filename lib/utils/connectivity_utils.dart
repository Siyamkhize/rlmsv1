import 'package:connectivity_plus/connectivity_plus.dart';

/// connectivity_plus 5.x returns single ConnectivityResult, not a list.
bool isDeviceOnline(ConnectivityResult result) {
  return result != ConnectivityResult.none;
}

Future<bool> hasNetworkConnectivity() async {
  final result = await Connectivity().checkConnectivity();
  return isDeviceOnline(result);
}
