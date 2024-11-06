part of dart_shp;

class SkipGeometry extends JTS.Point {
  SkipGeometry() : super(Coordinate.empty2D(), PrecisionModel(), 0);

  @override
  String toString() {
    return "SKIP";
  }
}

class ShapefileFeatureReader {
  static final Geometry SKIP = SkipGeometry();

  late ShapefileReader shp;

  DbaseFileReader? dbf;

  // List<int> dbfindexes;

  Feature? nextFeature;

  Envelope? targetBBox;

  // StringBuffer idxBuffer;

  // int idxBaseLen;
  DbaseFileHeader? header;
  int numFields = 0;

  ShapefileFeatureReader(File shpFile, {Charset? charset}) {
    String nameNoExt = FileUtilities.nameFromFile(shpFile.path, false);

    String parentFolder = FileUtilities.parentFolderFromFile(shpFile.path);

    String dbfName = nameNoExt + ".dbf";
    String shxName = nameNoExt + ".shx";

    String dbfPath = FileUtilities.joinPaths(parentFolder, dbfName);
    String shxPath = FileUtilities.joinPaths(parentFolder, shxName);

    File shxFile = File(shxPath);
    var shxReader;
    if (shxFile.existsSync()) {
      shxReader = FileReaderRandom(shxFile);
    }

    charset ??= Charset();
    shp = ShapefileReader(FileReaderRandom(shpFile), shxReader);

    var file = File(dbfPath);
    if (file.existsSync()) {
      dbf = DbaseFileReader(FileReaderRandom(file), charset);
    }
  }

  /// Constructor to support raw bytes.
  ShapefileFeatureReader.fromBytes({
    required Uint8List shpBytes,
    Uint8List? dbfBytes,
    Uint8List? shxBytes,
  }) {

    ByteReader? shxWebFileReader = shxBytes == null
        ? null
        : ByteReader(fileBytes: shxBytes);

    ByteReader shpWebFileReader =
        ByteReader(fileBytes: shpBytes);

    shp = ShapefileReader(shpWebFileReader, shxWebFileReader);

    ByteReader? dbfWebFileReader = dbfBytes == null
        ? null
        : ByteReader(fileBytes: dbfBytes);

    dbf = dbfWebFileReader == null ? null : DbaseFileReader(dbfWebFileReader);
  }

  Future<void> open() async {
    await dbf?.open();
    await shp.open();

    header = dbf?.getHeader();
    if (header != null) {
      numFields = header!.getNumFields();
    }
    // idxBuffer = StringBuffer(schema.getTypeName());
    // idxBuffer.write('.');
    // idxBaseLen = idxBuffer.length;

    // if (dbf != null) {
    //     // build the list of dbf indexes we have to read taking into consideration the
    //     // duplicated dbf field names issue
    //     List<AttributeDescriptor> atts = schema.getAttributeDescriptors();
    //     dbfindexes = new int[atts.size()];
    //     DbaseFileHeader head = dbf.getHeader();
    //     for (int i = 0; i < atts.size(); i++) {
    //         AttributeDescriptor att = atts.get(i);
    //         if (att is GeometryDescriptor) {
    //             dbfindexes[i] = -1;
    //         } else {
    //             String attName = att.getLocalName();
    //             int count = 0;
    //             Map<Object, Object> userData = att.getUserData();
    //             if (userData[ShapefileDataStore.ORIGINAL_FIELD_NAME] != null) {
    //                 attName = userData[ShapefileDataStore.ORIGINAL_FIELD_NAME] as String;
    //                 count =

    //                                 userData
    //                                         [ShapefileDataStore.ORIGINAL_FIELD_DUPLICITY_COUNT] as int;
    //             }

    //             bool found = false;
    //             for (int j = 0; j < head.getNumFields(); j++) {
    //                 if (head.getFieldName(j)== attName && count-- <= 0) {
    //                     dbfindexes[i] = j;
    //                     found = true;
    //                     break;
    //                 }
    //             }
    //             if (!found) {
    //                 throw IOException(
    //                         "Could not find attribute " + attName + " (mul count: $count");
    //             }
    //         }
    //     }
    // }
  }

  Future<Feature> next() async {
    if (await hasNext()) {
      Feature result = nextFeature!;
      nextFeature = null;
      return result;
    } else {
      throw StateError("hasNext() returned false");
    }
  }

  /// Returns true if the lower level readers, shp and dbf, have one more record to read */
  Future<bool> filesHaveMore() async {
    if (dbf == null) {
      return await shp.hasNext();
    } else {
      bool dbfHasNext = dbf!.hasNext();
      bool shpHasNext = await shp.hasNext();
      if (dbfHasNext && shpHasNext) {
        return true;
      } else if (dbfHasNext || shpHasNext) {
        throw StateError(((shpHasNext) ? "Shp" : "Dbf") + " has extra record");
      } else {
        return false;
      }
    }
  }

  Future<bool> hasNext() async {
    while (nextFeature == null && await filesHaveMore()) {
      Record? record = await shp.nextRecord();
      Geometry geometry = getGeometry(record!, shp.buffer);
      if (geometry != SKIP) {
        // also grab the dbf row
        Row? row;
        // if (dbf != null) {
        row = await dbf?.readRow();
        if (row != null && row.isDeleted()) {
          continue;
        }
        // } else {
        //   row = null;
        // }

        nextFeature = await buildFeature(
            shp.recordNumber, geometry, row, record.envelope());
      } else {
        // if (dbf != null) {
        dbf!.skip();
        // }
      }
    }

    return nextFeature != null;
  }

  /// Reads the geometry, it will return {@link #SKIP} if the records is to be skipped because of
  /// the screenmap or because it does not match the target bbox
  Geometry getGeometry(Record record, LByteBuffer buffer) {
    // read the geometry, so that we can decide if this row is to be skipped or not
    Envelope envelope = record.envelope();
    Geometry geometry;
    // if (schema.getGeometryDescriptor() != null) {
    // ... if geometry is out of the target bbox, skip both geom and row
    if (targetBBox != null &&
        !targetBBox!.isNull() &&
        !targetBBox!.intersectsEnvelope(envelope)) {
      geometry = SKIP;
      // ... if the geometry is awfully small avoid reading it (unless it's a point)
      // } else if (simplificationDistance > 0
      //         && envelope.getWidth() < simplificationDistance
      //         && envelope.getHeight() < simplificationDistance) {
      //     try {
      //         // if we have the screenmap, we either have no filter, and we
      //         // can directly alter the screenmap, or we have a filter, in that
      //         // case we just check if the screenmap is already busy
      //         if (screenMap != null && screenMap.get(envelope)) {
      //             geometry = SKIP;
      //         } else {
      //             // if we are using the screenmap better provide a slightly modified
      //             // version of the geometry bounds or we'll end up with many holes
      //             // in the rendering
      //             geometry = (Geometry) record.getSimplifiedShape(screenMap);
      //         }
      //     } catch (Exception e) {
      //         geometry = (Geometry) record.getSimplifiedShape();
      //     }
      //     // ... otherwise business as usual
    } else {
      geometry = record.getShape(buffer) as Geometry;
    }
    // }
    return geometry;
  }

  Future<Feature> buildFeature(
      int number, Geometry geometry, Row? row, Envelope envelope) async {
    // if (dbfindexes != null) {
    //     for (int i = 0; i < dbfindexes.length; i++) {
    //         if (dbfindexes[i] == -1) {
    //             builder.add(geometry);
    //         } else {
    //             builder.add(row.read(dbfindexes[i]));
    //         }
    //     }
    // } else if (geometry != null) {
    //     builder.add(geometry);
    // }
    // // build the feature id
    // String featureId = buildFeatureId(number);
    // SimpleFeature feature = builder.buildFeature(featureId);

    Feature f = Feature()
      ..fid = number
      ..geometry = geometry;

    if (row != null) {
      for (var i = 0; i < numFields; i++) {
        var read = await row.read(i);
        f.attributes[header!.getFieldName(i)] = read;
      }
    }
    return f;
  }

  String buildFeatureId(int number) {
    return number.toString();
    // if (fidReader == null) {
    //     idxBuffer.delete(idxBaseLen, idxBuffer.length());
    //     idxBuffer.append(number);
    //     return idxBuffer.toString();
    // } else {
    //     fidReader.goTo(number - 1);
    //     return fidReader.next();
    // }
  }

  void close() {
    try {
      // if (shp != null) {
      shp.close();
      // }
    } finally {
      try {
        // if (dbf != null) {
        dbf?.close();
        // }
      } finally {
        // try {
        //     if (fidReader != null) {
        //         fidReader.close();
        //     }
        // } finally {
        // shp = null;
        // dbf = null;
        // }
      }
    }
  }

  /// Sets the target bbox, will be used to skip over features we do not need */
  void setTargetBBox(Envelope targetBBox) {
    this.targetBBox = targetBBox;
  }

  void disableShxUsage() {
    shp.disableShxUsage();
  }

  ShapeType getShapeType() {
    return shp.getHeader().shapeType;
  }
}

/// Implementation of [AFileReader] to support raw bytes.
class ByteReader extends AFileReader {
  /// Bytes for the file.
  final List<int> fileBytes;

  /// Used to house the file bytes as a mock of an actual [io.File].
  late LByteBuffer channel;

  ByteReader({required this.fileBytes}) {
    channel = LByteBuffer.fromData(fileBytes);
  }

  @override
  Future<int> getByte() async {
    return channel.getByte();
  }

  @override
  Future<List<int>> get(int bytesCount) async {
    return channel.get(bytesCount);
  }

  @override
  Future<int> readIntoBuffer(LByteBuffer buffer) async {
    int read = min(buffer.remaining, channel.remaining);
    buffer.put(LByteBuffer.fromData(channel.get(read)));

    if (read <= 0) {
      return -1;
    }

    return read;
  }

  @override
  Future<LByteBuffer> getBuffer(int bytesCount) async {
    return LByteBuffer.fromData(channel.get(bytesCount));
  }

  @override
  Future<int> getInt32([Endian endian = Endian.big]) async {
    var data = Uint8List.fromList(channel.get(4));
    return ByteConversionUtilities.getInt32(data, endian);
  }

  @override
  Future<double> getDouble64([Endian endian = Endian.big]) async {
    var data = Uint8List.fromList(channel.get(8));
    return ByteConversionUtilities.getDouble64(data, endian);
  }

  @override
  Future<double> getDouble32([Endian endian = Endian.big]) async {
    var data = Uint8List.fromList(channel.get(4));
    return ByteConversionUtilities.getDouble32(data, endian);
  }

  @override
  Future skip(int bytesToSkip) async {
    channel.get(bytesToSkip);
  }

  @override
  bool get isOpen => true;

  Future<void> setPosition(int newPosition) async {
    channel.skip(newPosition - channel.position);
  }

  Future<int> position() async {
    return channel.position;
  }

  @override
  void close() {
    // Do nothing.
  }
}
