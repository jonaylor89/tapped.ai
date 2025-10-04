abstract class RemoteConfigRepository {
  Future<bool> getDownForMaintenanceStatus();
  Future<double> getBookingFee();
}
