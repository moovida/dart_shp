part of dart_shp;

/// The reader returns only one Record instance in its lifetime. The record contains the current
/// record information.
class Record {
  int length;

  int offset; // Relative to the whole file

  int start = 0; // Relative to the current loaded buffer

  /// The minimum X value. */
  double minX;

  /// The minimum Y value. */
  double minY;

  /// The maximum X value. */
  double maxX;

  /// The maximum Y value. */
  double maxY;

  ShapeType type;

  // int end = 0; // Relative to the whole file

  dynamic shape;

  GeometryFactory geometryFactory;
  ShapeHandler handler;
  bool flatGeometry;
  LByteBuffer buffer;

  Record(this.buffer, this.geometryFactory, this.handler, this.flatGeometry);

  /// Fetch the shape stored in this record. */
  dynamic getShape() {
    if (shape == null) {
      buffer.position = start;
      buffer.endian = Endian.little;
      if (type == ShapeType.NULL) {
        shape = null;
      } else {
        shape = handler.read(buffer, type, flatGeometry);
      }
    }
    return shape;
  }

  /// A summary of the record. */
  @override
  String toString() {
    return "Length $length, bounds $minX,$minY $maxX,$maxY";
  }

  Envelope envelope() {
    return Envelope(minX, maxX, minY, maxY);
  }

  Object getSimplifiedShape() {
    CoordinateSequenceFactory csf =
        geometryFactory.getCoordinateSequenceFactory();
    if (type.isPointType()) {
      CoordinateSequence cs = Shapeutils.createCS(csf, 1, 2);
      cs.setOrdinate(0, 0, (minX + maxX) / 2);
      cs.setOrdinate(0, 1, (minY + maxY) / 2);
      return geometryFactory
          .createMultiPoint([geometryFactory.createPointSeq(cs)]);
    } else if (type.isLineType()) {
      CoordinateSequence cs = Shapeutils.createCS(csf, 2, 2);
      cs.setOrdinate(0, 0, minX);
      cs.setOrdinate(0, 1, minY);
      cs.setOrdinate(1, 0, maxX);
      cs.setOrdinate(1, 1, maxY);
      return geometryFactory
          .createMultiLineString([geometryFactory.createLineStringSeq(cs)]);
    } else if (type.isPolygonType()) {
      CoordinateSequence cs = Shapeutils.createCS(csf, 5, 2);
      cs.setOrdinate(0, 0, minX);
      cs.setOrdinate(0, 1, minY);
      cs.setOrdinate(1, 0, minX);
      cs.setOrdinate(1, 1, maxY);
      cs.setOrdinate(2, 0, maxX);
      cs.setOrdinate(2, 1, maxY);
      cs.setOrdinate(3, 0, maxX);
      cs.setOrdinate(3, 1, minY);
      cs.setOrdinate(4, 0, minX);
      cs.setOrdinate(4, 1, minY);
      LinearRing ring = geometryFactory.createLinearRingSeq(cs);
      return geometryFactory
          .createMultiPolygon([geometryFactory.createPolygon(ring, null)]);
    } else {
      return getShape();
    }
  }

  //  Object getSimplifiedShape(ScreenMap sm) {
  //     if (type.isPointType()) {
  //         return shape();
  //     }

  //     Class<? extends Geometry> geomType = Geometry.class;
  //     if (type.isLineType()) {
  //         geomType = MultiLineString.class;
  //     } else if (type.isMultiPointType()) {
  //         geomType = MultiPoint.class;
  //     } else if (type.isPolygonType()) {
  //         geomType = MultiPolygon.class;
  //     }
  //     return sm.getSimplifiedShape(minX, minY, maxX, maxY, geometryFactory, geomType);
  // }
}

/// The general use of this class is: <CODE><PRE>
///
/// FileChannel in = new FileInputStream(&quot;thefile.dbf&quot;).getChannel();
/// ShapefileReader r = new ShapefileReader( in ) while (r.hasNext()) { Geometry
/// shape = (Geometry) r.nextRecord().shape() // do stuff } r.close();
///
/// </PRE></CODE> You don't have to immediately ask for the shape from the record. The record will
/// contain the bounds of the shape and will only read the shape when the shape() method is called.
/// This ShapefileReader.Record is the same object every time, so if you need data from the Record,
/// be sure to copy it.
///
/// @author jamesm
/// @author aaime
/// @author Ian Schneider
class ShapefileReader {
  /// Used to mark the current shape is not known, either because someone moved the reader to a
  /// specific byte offset manually, or because the .shx could not be opened
  static final int UNKNOWN = -9223372036854775807;

  ShapeHandler handler;

  ShapefileHeader header;

  AFileReader channel;
  AFileReader shxChannel;

  LByteBuffer buffer;

  ShapeType fileShapeType = ShapeType.UNDEFINED;

  LByteBuffer headerTransfer;

  Record record;
  int recordEnd = 0;
  int recordNumber = 0;

  bool randomAccessEnabled;

  int currentOffset = 0;

  int currentShape = 0;

  IndexFile shxReader;
  GeometryFactory geometryFactory;

  bool flatGeometry;

  bool onlyRandomAccess;

  bool strict;

  /// Creates a new instance of ShapeFile.
  ///
  /// @param shapefileFiles The ReadableByteChannel this reader will use.
  /// @param strict True to make the header parsing throw Exceptions if the version or magic number
  ///     are incorrect.
  /// @param gf The geometry factory used to build the geometries
  /// @param onlyRandomAccess When true sets up the reader to do exclusively read driven by goTo(x)
  ///     and thus avoids opening the .shx file
  /// @ If problems arise.
  /// @throws ShapefileException If for some reason the file contains invalid records.
  ShapefileReader(this.channel, this.shxChannel,
      {this.strict = false,
      this.geometryFactory,
      this.onlyRandomAccess = false});

  Future<void> open() async {
    randomAccessEnabled = shxChannel != null && shxChannel is FileReaderRandom;
    if (!onlyRandomAccess) {
      try {
        shxReader = IndexFile(shxChannel);
        await shxReader.open();
      } catch (e) {
        LOGGER.w(
            "Could not open the .shx file, continuing "
            "assuming the .shp file is not sparse",
            e);
        currentShape = UNKNOWN;
      }
    }
    geometryFactory ??= GeometryFactory.defaultPrecision();
    await init(strict, geometryFactory);
  }

  /// Disables .shx file usage. By doing so you drop support for sparse shapefiles, the .shp will
  /// have to be without holes, all the valid shapefile records will have to be contiguous.
  void disableShxUsage() {
    if (shxReader != null) {
      shxReader.close();
      shxReader = null;
    }
    currentShape = UNKNOWN;
  }

  // ensure the capacity of the buffer is of size by doubling the original
  // capacity until it is big enough
  // this may be naiive and result in out of MemoryError as implemented...
  LByteBuffer ensureCapacity(LByteBuffer buffer, int size) {
    // This sucks if you accidentally pass is a MemoryMappedBuffer of size
    // 80M
    // like I did while messing around, within moments I had 1 gig of
    // swap...
    // TODO check this
    // if (((Buffer) buffer).isReadOnly() ) {
    //     return buffer;
    // }

    int limit = buffer.limit;
    while (limit < size) {
      limit *= 2;
    }
    if (limit != buffer.limit) {
      // clean up the old buffer and allocate a new one
      buffer = LByteBuffer(limit);
    }
    return buffer;
  }

  // for filling a ReadableByteChannel
  static Future<int> fill(LByteBuffer buffer, AFileReader channel) async {
    int r = buffer.remaining;
    // channel reads return -1 when EOF or other error
    // because they a non-blocking reads, 0 is a valid return value!!
    while (buffer.remaining > 0 && r != -1) {
      r = await channel.readIntoBuffer(buffer);
    }
    buffer.limit = buffer.position;
    return r;
  }

  Future<void> init(bool strict, GeometryFactory gf) async {
    geometryFactory = gf;

    // start small
    buffer = LByteBuffer(1024);
    await fill(buffer, channel);
    buffer.flip();
    currentOffset = 0;

    header = ShapefileHeader();
    header.read(buffer, strict);
    fileShapeType = header.shapeType;
    handler = fileShapeType.getShapeHandler(gf);
    if (handler == null) {
      throw IOException("Unsuported shape type: $fileShapeType");
    }

    headerTransfer = LByteBuffer(8);
    headerTransfer.endian = Endian.big;

    // make sure the record end is set now...
    recordEnd = toFileOffset(buffer.position);
  }

  /// Get the header. Its parsed in the constructor.
  ///
  /// @return The header that is associated with this file.
  ShapefileHeader getHeader() {
    return header;
  }

  // do important cleanup stuff.
  // Closes channel !
  /// Clean up any resources. Closes the channel.
  ///
  /// @ If errors occur while closing the channel.
  void close() {
    // don't throw NPE on double close
    if (channel == null) return;
    try {
      if (channel.isOpen) {
        channel.close();
      }
    } finally {
      if (shxReader != null) shxReader.close();
    }
    shxReader = null;
    channel = null;
    header = null;
  }

  bool supportsRandomAccess() {
    return randomAccessEnabled;
  }

  /// If there exists another record. Currently checks the stream for the presence of 8 more bytes,
  /// the length of a record. If this is true and the record indicates the next logical record
  /// number, there exists more records.
  ///
  /// @return True if has next record, false otherwise.
  Future<bool> hasNext() async {
    return await hasNextCheck(true);
  }

  /// If there exists another record. Currently checks the stream for the presence of 8 more bytes,
  /// the length of a record. If this is true and the record indicates the next logical record
  /// number (if checkRecord == true), there exists more records.
  ///
  /// @param checkRecno If true then record number is checked
  /// @return True if has next record, false otherwise.
  Future<bool> hasNextCheck(bool checkRecno) async {
    // don't read past the end of the file (provided currentShape accurately
    // represents the current position)
    if (currentShape > UNKNOWN &&
        currentShape > shxReader.getRecordCount() - 1) {
      return false;
    }

    // ensure the proper position, regardless of read or handler behavior
    var nextOffset = await getNextOffset();
    positionBufferForOffset(buffer, nextOffset);

    // no more data left
    if (buffer.remaining < 8) {
      return false;
    }

    // mark current position
    int position = buffer.position;

    // looks good
    bool hasNext = true;
    if (checkRecno) {
      // record headers in big endian
      buffer.endian = Endian.big;
      int declaredRecNo = buffer.getInt32();
      hasNext = declaredRecNo == recordNumber + 1;
    }

    // reset things to as they were
    buffer.position = position;

    return hasNext;
  }

  Future<int> getNextOffset() async {
    if (currentShape >= 0) {
      return await shxReader.getOffsetInBytes(currentShape);
    } else {
      return recordEnd;
    }
  }

  /// Transfer (by bytes) the data at the current record to the ShapefileWriter.
  ///
  /// @param bounds double array of length four for transfering the bounds into
  /// @return The length of the record transfered in bytes
  //  int transferTo(ShapefileWriter writer, int recordNum, double[] bounds)
  //          {

  //     ((Buffer) buffer).position(this.toBufferOffset(record.end));
  //     buffer.order(ByteOrder.BIG_ENDIAN);

  //     buffer.getInt(); // record number
  //     int rl = buffer.getInt();
  //     int mark = ((Buffer) buffer).position();
  //     int len = rl * 2;

  //     buffer.order(ByteOrder.LITTLE_ENDIAN);
  //     ShapeType recordType = ShapeType.forID(buffer.getInt());

  //     if (recordType.isMultiPoint()) {
  //         for (int i = 0; i < 4; i++) {
  //             bounds[i] = buffer.getDouble();
  //         }
  //     } else if (recordType != ShapeType.NULL) {
  //         bounds[0] = bounds[1] = buffer.getDouble();
  //         bounds[2] = bounds[3] = buffer.getDouble();
  //     }

  //     // write header to shp and shx
  //     headerTransfer.position(0);
  //     headerTransfer.putInt(recordNum).putInt(rl).position(0);
  //     writer.shpChannel.write(headerTransfer);
  //     headerTransfer.putInt(0, writer.offset).position(0);
  //     writer.offset += rl + 4;
  //     writer.shxChannel.write(headerTransfer);

  //     // reset to mark and limit at end of record, then write
  //     int oldLimit = ((Buffer) buffer).limit();
  //     ((Buffer) buffer).position(mark).limit(mark + len);
  //     writer.shpChannel.write(buffer);
  //     ((Buffer) buffer).limit(oldLimit);

  //     record.end = this.toFileOffset(((Buffer) buffer).position());
  //     record.number++;

  //     return len;
  // }

  void positionBufferForOffset(LByteBuffer buffer, int offset) {
    // Check to see if requested offset is already loaded; ensure that record header is in the
    // buffer
    if (currentOffset <= offset && currentOffset + buffer.limit >= offset + 8) {
      buffer.position = toBufferOffset(offset);
    } else {
      if (!randomAccessEnabled) {
        throw StateError("Random Access not enabled");
      }
      var fc = channel as FileReaderRandom;

      fc.setPosition(offset);
      currentOffset = offset;
      buffer.position = 0;
      buffer.limit = buffer.capacity;
      fill(buffer, fc);
      buffer.flip();
    }
  }

  /// Fetch the next record information.
  ///
  /// @return The record instance associated with this reader.
  Future<Record> nextRecord() async {
    // need to update position
    positionBufferForOffset(buffer, await getNextOffset());
    if (currentShape != UNKNOWN) currentShape++;

    // record header is big endian
    buffer.endian = Endian.big;

    // read shape record header
    int recordNumberTmp = buffer.getInt32();
    // silly ESRI say contentLength is in 2-byte words
    // and ByteByffer uses bytes.
    // track the record location
    int recordLength = buffer.getInt32() * 2;

    if (!buffer.isReadOnly) {
      // capacity is less than required for the record
      // copy the old into the newly allocated
      if (buffer.capacity < recordLength + 8) {
        currentOffset += buffer.position;
        LByteBuffer old = buffer;
        // ensure enough capacity for one more record header
        buffer = ensureCapacity(buffer, recordLength + 8);
        buffer.put(old);
        await fill(buffer, channel);
        buffer.position = 0;
      } else
      // remaining is less than record length
      // compact the remaining data and read again,
      // allowing enough room for one more record header
      if (buffer.remaining < recordLength + 8) {
        currentOffset += buffer.position;
        buffer.compact();
        await fill(buffer, channel);
        buffer.position = 0;
      }
    }

    // shape record is all little endian
    buffer.endian = Endian.little;

    // read the type, handlers don't need it
    ShapeType recordType = ShapeType.forID(buffer.getInt32());

    // this usually happens if the handler logic is bunk,
    // but bad files could exist as well...
    if (recordType != ShapeType.NULL && recordType != fileShapeType) {
      throw StateError(
          "ShapeType changed illegally from $fileShapeType to $recordType");
    }

    // peek at bounds, then reset for handler
    // many handler's may ignore bounds reading, but we don't want to
    // second guess them...
    buffer.mark();
    record = Record(buffer, geometryFactory, handler, flatGeometry);
    if (recordType.isMultiPoint()) {
      record.minX = buffer.getDouble64();
      record.minY = buffer.getDouble64();
      record.maxX = buffer.getDouble64();
      record.maxY = buffer.getDouble64();
    } else if (recordType != ShapeType.NULL) {
      record.minX = record.maxX = buffer.getDouble64();
      record.minY = record.maxY = buffer.getDouble64();
    }
    buffer.reset();

    record.offset = recordEnd;
    // update all the record info.
    record.length = recordLength;
    record.type = recordType;
    recordNumber = recordNumberTmp;
    // remember, we read one int already...
    recordEnd = toFileOffset(buffer.position) + recordLength - 4;
    // mark this position for the reader
    record.start = buffer.position;
    // clear any cached shape
    record.shape = null;

    return record;
  }

  /// Moves the reader to the specified byte offset in the file. Mind that:
  ///
  /// <ul>
  ///   <li>it's your responsibility to ensure the offset corresponds to the actual beginning of a
  ///       shape struct
  ///   <li>once you call this, reading with hasNext/next on sparse shapefiles will be broken (we
  ///       don't know anymore at which shape we are)
  /// </ul>
  Future<void> goTo(int offset) async {
    disableShxUsage();
    if (randomAccessEnabled) {
      positionBufferForOffset(buffer, offset);

      int oldRecordOffset = recordEnd;
      recordEnd = offset;
      try {
        await hasNextCheck(
            false); // don't check for next logical record equality
      } catch (ioe) {
        recordEnd = oldRecordOffset;
        rethrow;
      }
    } else {
      throw StateError("Random Access not enabled");
    }
  }

  /// Returns the shape at the specified byte distance from the beginning of the file. Mind that:
  ///
  /// <ul>
  ///   <li>it's your responsibility to ensure the offset corresponds to the actual beginning of a
  ///       shape struct
  ///   <li>once you call this, reading with hasNext/next on sparse shapefiles will be broken (we
  ///       don't know anymore at which shape we are)
  /// </ul>
  dynamic shapeAt(int offset) async {
    disableShxUsage();
    if (randomAccessEnabled) {
      await goTo(offset);
      var rec = await nextRecord();
      return rec.shape();
    }
    throw StateError("Random Access not enabled");
  }

  /// Sets the current location of the byteStream to offset and returns the next record. Usually
  /// used in conjuctions with the shx file or some other index file. Mind that:
  ///
  /// <ul>
  ///   <li>it's your responsibility to ensure the offset corresponds to the actual beginning of a
  ///       shape struct
  ///   <li>once you call this, reading with hasNext/next on sparse shapefiles will be broken (we
  ///       don't know anymore at which shape we are)
  /// </ul>
  ///
  /// @param offset If using an shx file the offset would be: 2 * (index.getOffset(i))
  /// @return The record after the offset location in the bytestream
  /// @ thrown in a read error occurs
  /// @throws UnsupportedOperationException thrown if not a random access file
  Future<Record> recordAt(int offset) async {
    if (randomAccessEnabled) {
      await goTo(offset);
      return await nextRecord();
    }
    throw StateError("Random Access not enabled");
  }

  /// Converts file offset to buffer offset
  ///
  /// @param offset The offset relative to the whole file
  /// @return The offset relative to the current loaded portion of the file
  int toBufferOffset(int offset) {
    return offset - currentOffset;
  }

  /// Converts buffer offset to file offset
  ///
  /// @param offset The offset relative to the buffer
  /// @return The offset relative to the whole file
  int toFileOffset(int offset) {
    return currentOffset + offset;
  }

  /// Parses the shpfile counting the records.
  ///
  /// @return the number of non-null records in the shapefile
  Future<int> getCount(int count) async {
    try {
      if (channel == null) return -1;
      count = 0;
      int offset = currentOffset;
      try {
        await goTo(100);
      } catch (e) {
        return -1;
      }
      while (await hasNext()) {
        count++;
        await nextRecord();
      }

      await goTo(offset);
    } catch (ioe) {
      count = -1;
      // What now? This seems arbitrarily appropriate !
      throw ArgumentError("Problem reading shapefile record: $ioe");
    }
    return count;
  }

  /// @param handler The handler to set. */
  void setHandler(ShapeHandler handler) {
    this.handler = handler;
  }

  String id() {
    return runtimeType.toString();
  }

  void setFlatGeometry(bool flatGeometry) {
    this.flatGeometry = flatGeometry;
  }
}
