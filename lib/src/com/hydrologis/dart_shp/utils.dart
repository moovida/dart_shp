part of dart_shp;

final LOGGER = Logger(level: Level.verbose);

class TimeZones {
  static void init() {
    tz.initializeTimeZones();
  }
}

class StringUtilities {
  static bool equalsIgnoreCase(String string1, String string2) {
    return string1?.toLowerCase() == string2?.toLowerCase();
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
      // return conv.utf8.decode(bytes);
    }
    throw ArgumentError('Charset not supported.');
  }
}

/// Class to handle int conversions.
class ByteConversionUtilities {
  /// Convert a 32 bit integer [number] to its int representation.
  static List<int> bytesFromInt32(int number, [Endian endian = Endian.big]) {
    var tmp = Uint8List.fromList([0, 0, 0, 0]);
    var bdata = ByteData.view(tmp.buffer);
    bdata.setInt32(0, number, endian);
    return tmp;
  }

  /// Convert a 16 bit integer [number] to its int representation.
  static List<int> bytesFromInt16(int number, [Endian endian = Endian.big]) {
    var tmp = Uint8List.fromList([0, 0]);
    var bdata = ByteData.view(tmp.buffer);
    bdata.setInt16(0, number, endian);
    return tmp;
  }

  /// Get an int from a list of 4 bytes.
  static int getInt32(Uint8List list, [Endian endian = Endian.big]) {
    var bdata = ByteData.view(list.buffer);
    return bdata.getInt32(0, endian);
  }

  /// Get an int from a list of 2 bytes.
  static int getInt16(Uint8List list, [Endian endian = Endian.big]) {
    var bdata = ByteData.view(list.buffer);
    return bdata.getInt16(0, endian);
  }

  /// Get an int from a list of 1 byte.
  static int getInt8(Uint8List list) {
    var bdata = ByteData.view(list.buffer);
    return bdata.getInt8(0);
  }

  /// Convert a 64 bit integer [number] to its int representation.
  static List<int> bytesFromInt64(int number, [Endian endian = Endian.big]) {
    var tmp = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);
    var bdata = ByteData.view(tmp.buffer);
    bdata.setInt64(0, number, endian);
    return tmp;
  }

  /// Convert a 64 bit double [number] to its int representation.
  static List<int> bytesFromDouble(double number,
      [Endian endian = Endian.big]) {
    var tmp = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);
    var bdata = ByteData.view(tmp.buffer);
    bdata.setFloat64(0, number, endian);
    return tmp;
  }

  /// Read a file from [path] into a bytes list.
  static Uint8List bytesFromFile(String path) {
    var outputFile = File(path);
    return outputFile.readAsBytesSync();
  }

  /// Write a list of [bytes] to file and return the written file [path].
  static String bytesToFile(String path, List<int> bytes) {
    var outputFile = File(path);
    outputFile.writeAsBytesSync(bytes);
    return outputFile.path;
  }

  /// Convert a [name] into a list of bytes.
  static List<int> bytesFromString(String fileName) {
    return fileName.codeUnits;
  }

  static void addPadding(List<int> data, int requiredSize) {
    if (data.length < requiredSize) {
      // add padding to complete the mtu
      var add = requiredSize - data.length;
      for (var i = 0; i < add; i++) {
        data.add(0);
      }
    }
  }
}

/// A reader class to wrap teh buffer method/package used.
class FileReader {
  File _file;
  bool _isOpen = false;
  ChunkedStreamIterator<int> channel;

  FileReader(this._file) {
    Stream<List<int>> stream = _file.openRead();
    channel = ChunkedStreamIterator(stream);
    _isOpen = true;
  }

  Future<int> getByte() async {
    return (await channel.read(1))[0];
  }

  Future<List<int>> get(int bytesCount) async {
    return await channel.read(bytesCount);
  }

  Future<int> getInt32([Endian endian = Endian.big]) async {
    var data = Uint8List.fromList(await channel.read(4));
    return ByteConversionUtilities.getInt32(data, endian);
  }

  Future skip(int bytesToSkip) async {
    await channel.read(bytesToSkip);
  }

  bool get isOpen => _isOpen;

  void close(){
    
  }
}
