part of dart_shp;

final LOGGER = Logger(level: Level.verbose);

class TimeZones {
  String _timeZoneName;

  static void init() {
    tz.initializeTimeZones();
  }

  void setZone(String timeZoneName) {
    _timeZoneName = timeZoneName;
  }

  static TimeZones getDefault() {
    return TimeZones()..setZone('en_US');
  }
}

class Charset {
  final String charsetName;

  const Charset._(this.charsetName);
  static const UTF8 = Charset._('UTF-8');

  static Charset defaultCharset() {
    return Charset.UTF8;
  }

  String encode(List<int> bytes) {
    if (this == UTF8) {
      return String.fromCharCodes(bytes);
      // TODO verify
      // return conv.utf8.encode(bytes);
    }
    throw ArgumentError('Charset not supported.');
  }

  List<int> decode(String string) {
    if (this == UTF8) {
      return string.codeUnits;
      // TODO verify
      // return conv.utf8.decode(string);
    }
    throw ArgumentError('Charset not supported.');
  }
}
