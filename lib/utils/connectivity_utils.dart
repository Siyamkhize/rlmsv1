import 'package:connectivity_plus/connectivity_plus.dart';

/// connectivity_plus 6.x returns List<ConnectivityResult>.
bool isDeviceOnline(ConnectivityResult result) {
  return result != ConnectivityResult.none;
}

Future<bool> hasNetworkConnectivity() async {
  final result = await Connectivity().checkConnectivity();
  return !result.contains(ConnectivityResult.none);
}
