part of dart_shp;

/// IndexFile parser for .shx files.<br>
/// For now, the creation of index files is done in the ShapefileWriter. But this can be used to
/// access the index.<br>
/// For details on the index file, see <br>
/// <a href="http://www.esri.com/library/whitepapers/pdfs/shapefile.pdf"><b>"ESRI(r) Shapefile - A
/// Technical Description"</b><br>
/// * <i>'An ESRI White Paper . May 1997'</i></a>
///
/// @author Ian Schneider
class IndexFile {
  static final int RECS_IN_BUFFER = 2000;

  AFileReader afileReader;
  int channelOffset = 0;
  int lastIndex = -1;
  int recOffset = 0;
  int recLen = 0;
  late ShapefileHeader header;
  late List<int> content;
  late LByteBuffer buf;

  bool closed = false;

  IndexFile(this.afileReader);

  /// Load the index file from the given reader.
  Future<void> open() async {
    try {
      // ShpLogger().v("Loading all shx...");
      // await readHeader(afileReader);
      // await readRecords(afileReader);
      // afileReader.close();

      ShpLogger().v("Reading from file...");
      buf = LByteBuffer(8 * RECS_IN_BUFFER);
      await afileReader.readIntoBuffer(buf);
      buf.flip();
      channelOffset = 0;

      header = ShapefileHeader();
      header.read(buf, true);
    } catch (e) {
      // if (afileReader != null) {
      try {
        afileReader.close();
      } on Exception catch (ex) {}
      // }
      rethrow;
    }
  }

  /// Get the header of this index file.
  ///
  /// @return The header of the index file.
  ShapefileHeader getHeader() {
    return header;
  }

  void check() {
    if (closed) {
      throw StateError("Index file has been closed");
    }
  }

  Future<void> readHeader(AFileReader channel) async {
    header = ShapefileHeader();
    buf = LByteBuffer(100);
    while (buf.remaining > 0) {
      await channel.readIntoBuffer(buf);
    }
    buf.flip();
    header.read(buf, true);
  }

  Future<void> readRecords(AFileReader channel) async {
    check();
    int remaining = (header.fileLength * 2) - 100;
    LByteBuffer buffer = LByteBuffer(remaining);

    buffer.endian = Endian.big;
    while (buffer.remaining > 0) {
      await channel.readIntoBuffer(buffer);
    }
    buffer.flip();

    int records = remaining ~/ 4;

    content = [];
    for (var i = 0; i < records; i++) {
      var intValue = await buffer.getInt32();
      content.add(intValue);
    }

    // var bytesList = await channel.get(remaining);
    // content = List(records);
    // IntBuffer ints = buffer.asIntBuffer();
    // ints.get(content);
  }

  Future<void> readRecord(int index) async {
    check();
    int pos = 100 + index * 8;

    if (pos - channelOffset < 0 ||
        channelOffset + buf.limit <= pos ||
        lastIndex == -1) {
      ShpLogger().v("Filling buffer...");
      channelOffset = pos;
      await (afileReader as FileReaderRandom).setPosition(pos);
      buf.clear();
      await afileReader.readIntoBuffer(buf);
      buf.flip();
    }

    buf.position = pos - channelOffset;
    recOffset = buf.getInt32();
    recLen = buf.getInt32();
    lastIndex = index;
  }

  void close() {
    closed = true;
    if (/*afileReader != null && */ afileReader.isOpen) {
      afileReader.close();
    }
    // content = null;
    // afileReader = null;
    // buf = null;
  }

  void finalize() {
    close();
  }

  /// Get the number of records in this index.
  ///
  /// @return The number of records.
  int getRecordCount() {
    return (header.fileLength * 2 - 100) ~/ 8;
  }

  /// Get the offset of the record (in 16-bit words).
  ///
  /// @param index The index, from 0 to getRecordCount - 1
  /// @return The offset in 16-bit words.
  Future<int> getOffset(int index) async {
    int ret = -1;

    if (afileReader != null) {
      if (lastIndex != index) {
        await readRecord(index);
      }

      ret = recOffset;
    } else {
      ret = content[2 * index];
    }

    return ret;
  }

  /// Get the offset of the record (in real bytes, not 16-bit words).
  ///
  /// @param index The index, from 0 to getRecordCount - 1
  /// @return The offset in bytes.
  Future<int> getOffsetInBytes(int index) async {
    return await getOffset(index) * 2;
  }

  /// Get the content length of the given record in bytes, not 16 bit words.
  ///
  /// @param index The index, from 0 to getRecordCount - 1
  /// @return The lengh in bytes of the record.
  int getContentLength(int index) {
    int ret = -1;

    if (afileReader != null) {
      if (lastIndex != index) {
        readRecord(index);
      }

      ret = recLen;
    } else {
      ret = content[2 * index + 1];
    }

    return ret;
  }

  String id() {
    return runtimeType.toString();
  }
}
