import 'package:connectivity_plus/connectivity_plus.dart';

/// connectivity_plus 6.x returns [List<ConnectivityResult>], not a single value.
bool isDeviceOnline(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  return results.any((r) => r != ConnectivityResult.none);
}

Future<bool> hasNetworkConnectivity() async {
  final results = await Connectivity().checkConnectivity();
  return isDeviceOnline(results);
}
