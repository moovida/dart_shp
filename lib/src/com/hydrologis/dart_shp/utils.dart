part of dart_shp;

final LOGGER = Logger(level: Level.verbose);

const NULL_CHAR = '\x00';
final NULL_CHARACTERS = Characters(NULL_CHAR);

// TODO NOT YET IMPLEMENTED
class TimeZones {
  String _timeZoneName;

  static void init() {
    // tz.initializeTimeZones();
  }

  void setZone(String timeZoneName) {
    _timeZoneName = timeZoneName;
  }

  static TimeZones getDefault() {
    return TimeZones()..setZone('en_US');
  }

  static TimeZones getTimeZone(String timeZoneName) {
    return TimeZones()..setZone(timeZoneName);
  }
}


