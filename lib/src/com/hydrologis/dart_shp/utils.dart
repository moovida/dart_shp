part of dart_shp;

const NULL_CHAR = '\x00';
final NULL_CHARACTERS = Characters(NULL_CHAR);

// TODO NOT YET IMPLEMENTED
class TimeZones {
  String? _timeZoneName;

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

/// A very simple Logger singleton class without external logger dependencies.
///
/// Logs to console and a database on the device.
class ShpLogger {
  static final ShpLogger _instance = ShpLogger._internal();

  dynamic _extLogger;
  bool doConsoleLogging = true;

  factory ShpLogger() => _instance;

  ShpLogger._internal();

  /// Set an external logger to use.
  ///
  /// In that case console logging is disabled.
  set externalLogger(dynamic logger) {
    _extLogger = logger;
    doConsoleLogging = false;
  }

  void v(dynamic message) {
    _extLogger?.v(message);
    if (doConsoleLogging) {
      print("vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv");
      print("v: ${message.toString()}");
      print("vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv");
    }
  }

  void d(dynamic message) {
    _extLogger?.d(message);
    if (doConsoleLogging) {
      print("ddddddddddddddddddddddddddddddddddd");
      print("d: ${message.toString()}");
      print("ddddddddddddddddddddddddddddddddddd");
    }
  }

  void i(dynamic message) {
    _extLogger?.i(message);
    if (doConsoleLogging) {
      print("iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii");
      print("i: ${message.toString()}");
      print("iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii");
    }
  }

  void w(dynamic message) {
    _extLogger?.w(message);
    if (doConsoleLogging) {
      print("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww");
      print("w: ${message.toString()}");
      print("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww");
    }
  }

  void e(dynamic message, StackTrace stackTrace) {
    _extLogger?.e(message, stackTrace);
    if (doConsoleLogging) {
      print("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
      print("e: ${message.toString()}");
      print("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
    }
  }
}
