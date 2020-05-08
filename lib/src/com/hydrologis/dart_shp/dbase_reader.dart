part of dart_shp;

/// This file has been ported from the geotools.org project.

class Row {
  bool deleted = false;

  var fieldOffsets;

  var header;

  var readObject;

  Row(this.fieldOffsets, this.header, this.readObject);

  dynamic read(final int column) {
    final int offset = fieldOffsets[column];
    return readObject(offset, column);
  }

  @override
  String toString() {
    final ret = StringBuffer('DBF Row - ');
    for (var i = 0; i < header.getNumFields(); i++) {
      ret.write(header.getFieldName(i));
      ret.write(': \'');
      try {
        ret.write(read(i));
      } catch (ioe) {
        ret.write(ioe.getMessage());
      }
      ret.write('\' ');
    }
    return ret.toString();
  }

  bool isDeleted() {
    return deleted;
  }
}

/// A DbaseFileReader is used to read a dbase III format file. <br>
/// The general use of this class is: <CODE><PRE>
///
/// FileChannel in = FileInputStream(&quot;thefile.dbf&quot;).getChannel();
/// DbaseFileReader r = DbaseFileReader( in ) Object[] fields = new
/// Object[r.getHeader().getNumFields()]; while (r.hasNext()) {
/// r.readEntry(fields); // do stuff } r.close();
///
/// </PRE></CODE> For consumers who wish to be a bit more selective with their reading of rows, the
/// Row object has been added. The semantics are the same as using the readEntry method, but remember
/// that the Row object is always the same. The values are parsed as they are read, so it pays to
/// copy them out (as each call to Row.read() will result in an expensive String parse). <br>
/// <b>EACH CALL TO readEntry OR readRow ADVANCES THE FILE!</b><br>
/// An example of using the Row method of reading: <CODE><PRE>
///
/// FileChannel in = FileInputStream(&quot;thefile.dbf&quot;).getChannel();
/// DbaseFileReader r = DbaseFileReader( in ) int fields =
/// r.getHeader().getNumFields(); while (r.hasNext()) { DbaseFileReader.Row row =
/// r.readRow(); for (int i = 0; i &lt; fields; i++) { // do stuff Foo.bar(
/// row.read(i) ); } } r.close();
///
/// </PRE></CODE>
///
/// @author Ian Schneider, Andrea Aaime
class DbaseFileReader {
  DbaseFileHeader header;

  List<int> bytes;

  List<int> fieldTypes;

  List<int> fieldLengths;

  List<int> fieldOffsets;

  int cnt = 1;

  Endian endian = Endian.little;

  Row row;

  int currentOffset = 0;

  bool oneBytePerChar;

  final int MILLISECS_PER_DAY = 24 * 60 * 60 * 1000;

  FileReader fileReader;
  Charset stringCharset;
  TimeZones timeZone;

  DbaseFileReader(this.fileReader, [this.stringCharset, this.timeZone]);

  Future<void> open() async {
    stringCharset = stringCharset ?? Charset.defaultCharset();
    // TimeZone calTimeZone = timeZone == null ? TimeZone.UTC : timeZone;

    header = DbaseFileHeader();
    await header.readHeaderWithCharset(fileReader, stringCharset);
    currentOffset = header.getHeaderLength();

    // Set up some buffers and lookups for efficiency
    fieldTypes = List(header.getNumFields());
    fieldLengths = List(header.getNumFields());
    fieldOffsets = List(header.getNumFields());
    for (var i = 0, ii = header.getNumFields(); i < ii; i++) {
      fieldTypes[i] = header.getFieldType(i);
      fieldLengths[i] = header.getFieldLength(i);
      if (i > 0) {
        fieldOffsets[i] = fieldOffsets[i - 1] + header.getFieldLength(i - 1);
      } else {
        fieldOffsets[i] = 0;
      }
    }
    bytes = null; //List(header.getRecordLength() - 1);

    // check if we working with a latin-1 char Charset
    final cname = stringCharset.charsetName;
    oneBytePerChar = 'ISO-8859-1' == cname || 'US-ASCII' == cname;

    row = Row(fieldOffsets, header, readObject);
  }

  /// Get the header from this file. The header is read upon instantiation.
  ///
  /// @return The header associated with this file or null if an error occurred.
  DbaseFileHeader getHeader() {
    return header;
  }

  /// Clean up all resources associated with this reader.<B>Highly recomended.</B>
  ///
  /// @ If an error occurs.
  void close() {
    if (fileReader != null && fileReader.isOpen) {
      fileReader.close();
    }

    fileReader = null;
    bytes = null;
    header = null;
    row = null;
  }

  /// Query the reader as to whether there is another record.
  ///
  /// @return True if more records exist, false otherwise.
  bool hasNext() {
    return cnt < header.getNumRecords() + 1;
  }

  /// Get the next record (entry). Will return a array of values.
  ///
  /// @ If an error occurs.
  /// @return A array of values.
  Future<List<dynamic>> readEntry() async {
    return await readEntryInto(List<dynamic>(header.getNumFields()));
  }

  Future<Row> readRow() async {
    await read();
    return row;
  }

  /// Skip the next record.
  ///
  /// @ If an error occurs.
  //  void skip()  {
  //     bool foundRecord = false;
  //     while (!foundRecord) {

  //         // bufferCheck();

  //         // read the deleted flag
  //         final String tempDeleted = (char) buffer.get();

  //         // skip the next bytes
  //         buffer.position(buffer.position() + header.getRecordLength() - 1); // the
  //         // 1 is
  //         // for
  //         // the
  //         // deleted
  //         // flag
  //         // just
  //         // read.

  //         // add the row if it is not deleted.
  //         if (tempDeleted != '*') {
  //             foundRecord = true;
  //         }
  //     }
  //     cnt++;
  // }

  /// Copy the next record into the array starting at offset.
  ///
  /// @param entry Th array to copy into.
  /// @param offset The offset to start at
  /// @ If an error occurs.
  /// @return The same array passed in.
  Future<List<dynamic>> readEntryWithOffset(
      final List<dynamic> entry, final int offset) async {
    if (entry.length - offset < header.getNumFields()) {
      throw IndexError(offset, entry);
    }

    await read();
    if (row.deleted) {
      return null;
    }

    // retrieve the record length
    final numFields = header.getNumFields();

    for (var j = 0; j < numFields; j++) {
      var object = readObject(fieldOffsets[j], j);
      entry[j + offset] = object;
    }

    return entry;
  }

  /// Reads a single field from the current record and returns it. Remember to call {@link #read()}
  /// before starting to read fields from the dbf, and call it every time you need to move to the
  /// next record.
  ///
  /// @param fieldNum The field number to be read (zero based)
  /// @ If an error occurs.
  /// @return The value of the field
  Object readField(final int fieldNum) {
    return readObject(fieldOffsets[fieldNum], fieldNum);
  }

  // /** Transfer, by bytes, the next record to the writer. */
  //  void transferTo(final DbaseFileWriter writer)  {
  //     bufferCheck();
  //     buffer.limit(buffer.position() + header.getRecordLength());
  //     writer.channel.write(buffer);
  //     buffer.limit(buffer.capacity());

  //     cnt++;
  // }

  /// Reads the next record into memory. You need to use this directly when reading only a subset
  /// of the fields using {@link #readField(int)}.
  Future read() async {
    var foundRecord = false;
    while (!foundRecord) {
      // bufferCheck();

      // read the deleted flag
      final deleted = String.fromCharCode(
          await fileReader.getByte()); //   (    char) buffer.get();
      row.deleted = deleted == '*';

      bytes = await fileReader.get(header.getRecordLength() - 1);
      // buffer.limit(buffer.position() + header.getRecordLength() - 1);
      // buffer.get(bytes); // SK: There is a side-effect here!!!
      // buffer.limit(buffer.capacity());

      foundRecord = true;
    }

    cnt++;
  }

  /// Copy the next entry into the array.
  ///
  /// @param entry The array to copy into.
  /// @ If an error occurs.
  /// @return The same array passed in.
  Future<List<dynamic>> readEntryInto(final List<dynamic> entry) async {
    return await readEntryWithOffset(entry, 0);
  }

  dynamic readObject(final int fieldOffset, final int fieldNum) {
    final type = fieldTypes[fieldNum];
    final fieldLen = fieldLengths[fieldNum];
    dynamic object;
    if (fieldLen > 0) {
      switch (String.fromCharCode(type)) {
        // (L)logical (T,t,F,f,Y,y,N,n)
        case 'l':
        case 'L':
          final c = String.fromCharCode(bytes[fieldOffset]);
          switch (c) {
            case 't':
            case 'T':
            case 'Y':
            case 'y':
              object = true;
              break;
            case 'f':
            case 'F':
            case 'N':
            case 'n':
              object = false;
              break;
            default:
              // 0x20 should be interpreted as null, but we're going to be a bit more
              // lax
              object = null;
          }
          break;
        // (C)character (String)
        case 'c':
        case 'C':
          if (bytes[fieldOffset] != NULL_CHAR.codeUnitAt(0)) {
            // var str = String.fromCharCode(bytes[fieldOffset]);
            // if (str != '\0') {
            // remember we need to skip trailing and leading spaces
            if (oneBytePerChar) {
              object = fastParse(bytes, fieldOffset, fieldLen).trim();
            } else {
              var sublist = bytes.sublist(fieldOffset, fieldOffset + fieldLen);
              var string = stringCharset.encode(sublist).trim();
              var characters = Characters(string);

              if (characters.endsWith(NULL_CHARACTERS)) {
                string = Characters(string)
                    .skipLastWhile((c) => c == NULL_CHARACTERS.toString())
                    .toString();
              }
              object = string;
              // String(bytes, fieldOffset, fieldLen, stringCharset.name())
              //         .trim();
            }
          }
          // }
          break;
        // (D)date (Date)
        case 'd':
        case 'D':
          // If the first 8 characters are '0', this is a null date
          for (var i = 0; i < 8; i++) {
            if (String.fromCharCode(bytes[fieldOffset + i]) != '0') {
              try {
                var tempString = fastParse(bytes, fieldOffset, 4);
                final tempYear = int.parse(tempString);
                tempString = fastParse(bytes, fieldOffset + 4, 2);
                final tempMonth = int.parse(tempString);
                tempString = fastParse(bytes, fieldOffset + 6, 2);
                final tempDay = int.parse(tempString);
                object = DateTime.utc(tempYear, tempMonth, tempDay);
              } catch (nfe) {
                // todo: use progresslistener, this isn't a grave error.
              }
              break;
            }
          }
          break;
        // (@) Timestamp (Date)
        case '@':
          try {
            var timestampBytes = [
              // Time in millis, after reverse.
              bytes[fieldOffset + 7], bytes[fieldOffset + 6],
              bytes[fieldOffset + 5],
              bytes[fieldOffset + 4]
            ];

            var daysBytes = [
              // Days, after reverse.
              bytes[fieldOffset + 3], bytes[fieldOffset + 2],
              bytes[fieldOffset + 1],
              bytes[fieldOffset]
            ];

            var data = Uint8List.fromList(timestampBytes);
            var time = ByteConversionUtilities.getInt32(data, endian);
            data = Uint8List.fromList(daysBytes);
            var days = ByteConversionUtilities.getInt32(data, endian);

            object = DateTime.fromMillisecondsSinceEpoch(
                days * MILLISECS_PER_DAY +
                    DbaseFileHeader.MILLIS_SINCE_4713 +
                    time);
          } catch (nfe) {
            // todo: use progresslistener, this isn't a grave error.
          }
          break;
        // (N)umeric (Integer, Long or Fallthrough to Double)
        case 'n':
        case 'N':
          // numbers that begin with '*' are considered null
          if (String.fromCharCode(bytes[fieldOffset]) == '*') {
            break;
          } else {
            final string = fastParse(bytes, fieldOffset, fieldLen).trim();
            var clazz = header.getFieldClass(fieldNum);
            if (clazz == int) {
              try {
                object = int.parse(string);
                break;
              } catch (e) {
                // fall through to the floating point number

              }
            }
          }
          // do not break, fall through to the 'f' case
          object = handleFloat(fieldOffset, object, fieldLen);
          break;
        // (F)loating point number
        case 'f':
        case 'F':
          object = handleFloat(fieldOffset, object, fieldLen);
          break;
        default:
          throw ArgumentError('Invalid field type : $type');
      }
    }
    return object;
  }

  dynamic handleFloat(int fieldOffset, object, int fieldLen) {
    if (String.fromCharCode(bytes[fieldOffset]) != '*') {
      try {
        object = double.parse(fastParse(bytes, fieldOffset, fieldLen));
      } catch (e) {
        // okay, now whatever we got was truly indigestible.
        object = null;
      }
    }
    return object;
  }

  /// Performs a faster byte[] to String conversion under the assumption the content is represented
  /// with one byte per char
  String fastParse(
      final List<int> bytes, final int fieldOffset, final int fieldLen) {
    // faster reading path, the decoder is for some reason slower,
    // probably because it has to make extra checks to support multibyte chars
    final chars = List<int>(fieldLen);
    for (var i = 0; i < fieldLen; i++) {
      // force the byte to a positive integer interpretation before casting to char
      chars[i] = (0x00FF & bytes[fieldOffset + i]);
    }
    return String.fromCharCodes(chars);
  }

  String id() {
    return runtimeType.toString();
  }
}
