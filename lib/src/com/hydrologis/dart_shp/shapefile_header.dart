part of dart_shp;

/**
 * @author jamesm
 * @author Ian Schneider
 */
class ShapefileHeader {
  static final int MAGIC = 9994;

  static final int VERSION = 1000;

  int fileCode = -1;

  int fileLength = -1;

  int version = -1;

  ShapeType shapeType = ShapeType.UNDEFINED;

  double minX;

  double maxX;

  double minY;

  double maxY;

  void checkMagic(bool strict) {
    if (fileCode != MAGIC) {
      String message = "Wrong magic number, expected $MAGIC, got $fileCode";
      if (!strict) {
        LOGGER.i(message);
      } else {
        throw StateError(message);
      }
    }
  }

  void checkVersion(bool strict) {
    if (version != VERSION) {
      String message = "Wrong version, expected $VERSION, got $version";
      if (!strict) {
        LOGGER.i(message);
      } else {
        throw StateError(message);
      }
    }
  }

  Future<void> read(FileReaderRandom fileReader, bool strict) async {
    Endian endian = Endian.big;
    // file.order(ByteOrder.BIG_ENDIAN);
    fileCode = await fileReader.getInt32(endian);

    checkMagic(strict);

    // skip 5 ints...
    await fileReader.skip(20);

    fileLength = await fileReader.getInt32(endian);

    endian = Endian.big;
    // file.order(ByteOrder.LITTLE_ENDIAN);
    version = await fileReader.getInt32(endian);
    checkVersion(strict);
    shapeType = ShapeType.forID(await fileReader.getInt32(endian));

    minX = await fileReader.getDouble64(endian);
    minY = await fileReader.getDouble64(endian);
    maxX = await fileReader.getDouble64(endian);
    maxY = await fileReader.getDouble64(endian);

    // skip remaining unused bytes
    // file.order(ByteOrder.BIG_ENDIAN); // well they may not be unused
    // forever...
    await fileReader.skip(32);
  }

  Future<void> write(FileWriter fileWriter, ShapeType type, int numGeoms, int length,
      double minX, double minY, double maxX, double maxY) async {
    // file.order(ByteOrder.BIG_ENDIAN);
    Endian endian = Endian.big;

    await fileWriter.putInt32(MAGIC, endian);

    for (int i = 0; i < 5; i++) {
      await fileWriter.putInt32(0, endian); // Skip unused part of header
    }

    await fileWriter.putInt32(length, endian);

    endian = Endian.little;
    // file.order(ByteOrder.LITTLE_ENDIAN);

    await fileWriter.putInt32(VERSION, endian);
    await fileWriter.putInt32(type.id, endian);

    // write the bounding box
    await fileWriter.putDouble64(minX, endian);
    await fileWriter.putDouble64(minY, endian);
    await fileWriter.putDouble64(maxX, endian);
    await fileWriter.putDouble64(maxY, endian);

    // skip remaining unused bytes
    endian = Endian.big;
    // file.order(ByteOrder.BIG_ENDIAN);
    for (int i = 0; i < 8; i++) {
      await fileWriter.putInt32(0, endian); // Skip unused part of header
    }
  }

  @override
  String toString() {
    String res =
        """ShapeFileHeader[ 
              size $fileLength 
              version $version 
              shapeType $shapeType 
              bounds $minX, $minY, $maxX, $maxY 
           ]""";
    return res;
  }
}
