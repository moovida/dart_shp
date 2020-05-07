part of dart_shp;

/// This file has been ported from the geotools.org project.
///

/** Thrown when an error relating to the shapefile occurs. */
class DbaseFileException implements Exception {
  String msg;
  Exception cause;

  DbaseFileException(this.msg);

  DbaseFileException.withCause(this.msg, this.cause);

  @override
  String toString() => 'DbaseFileException: ' + msg;
}

/** Class for holding the information associated with a record. */
class DbaseField {
  // Field Name
  String fieldName;

  // Field Type (C N L D @ or M)
  int fieldType; // char

  // Field Data Address offset from the start of the record.
  int fieldDataAddress;

  // Length of the data in bytes
  int fieldLength;

  // Field decimal count in Binary, indicating where the decimal is
  int decimalCount;
}

/** Class to represent the header of a Dbase III file. Creation date: (5/15/2001 5:15:30 PM) */
class DbaseFileHeader {
  // Constant for the size of a record
  static final int FILE_DESCRIPTOR_SIZE = 32;

  // type of the file, must be 03h
  static final int MAGIC = 0x03;

  static final int MINIMUM_HEADER = 33;

  // Date the file was last updated.
  DateTime date = DateTime.now();

  int recordCnt = 0;

  int fieldCnt = 0;

  // set this to a default length of 1, which is enough for one "space"
  // character which signifies an empty record
  int recordLength = 1;

  // set this to a flagged value so if no fields are added before the write,
  // we know to adjust the headerLength to MINIMUM_HEADER
  int headerLength = -1;

  int largestFieldSize = 0;

  /**
     * Returns the number of millis at January 1st 4713 BC
     *
     * <p>Calendar refCal = (Calendar) new GregorianCalendar(TimeZone.getTimeZone("UTC"));
     * refCal.set(Calendar.ERA, GregorianCalendar.BC); refCal.set(Calendar.YEAR, 4713);
     * refCal.set(Calendar.MONTH, Calendar.JANUARY); refCal.set(Calendar.DAY_OF_MONTH, 1);
     * refCal.set(Calendar.HOUR, 12); refCal.set(Calendar.MINUTE, 0); refCal.set(Calendar.SECOND,
     * 0); refCal.set(Calendar.MILLISECOND, 0); MILLIS_SINCE_4713 = refCal.getTimeInMillis() -
     * 43200000L; //(43200000L: 12 hour correction factor taken from DBFViewer2000)
     */
  static int MILLIS_SINCE_4713 = -210866803200000;

  // Collection of header records.
  // lets start out with a zero-length array, just in case
  List<DbaseField> fields = [];

  /**
     * Determine the most appropriate Java Class for representing the data in the field.
     *
     * <PRE>
     * All packages are java.lang unless otherwise specified.
     * C (Character) -&gt; String
     * N (Numeric)   -&gt; Integer or Long or Double (depends on field's decimal count and fieldLength)
     * F (Floating)  -&gt; Double
     * L (Logical)   -&gt; Boolean
     * D (Date)      -&gt; java.util.Date (Without time)
     * @ (Timestamp) -&gt; java.sql.Timestamp (With time)
     * Unknown       -&gt; String
     * </PRE>
     *
     * @param i The index of the field, from 0 to <CODE>getNumFields() - 1</CODE> .
     * @return A Class which closely represents the dbase field type.
     */
  Type getFieldClass(int i) {
    Type typeClass;

    var fieldType = fields[i].fieldType;
    var code = String.fromCharCode(fieldType);
    switch (code) {
      case 'C':
        typeClass = String;
        break;

      case 'N':
        if (fields[i].decimalCount == 0) {
          if (fields[i].fieldLength < 10) {
            typeClass = int;
          } else {
            typeClass = int;
          }
        } else {
          typeClass = double;
        }
        break;

      case 'F':
        typeClass = double;
        break;

      case 'L':
        typeClass = bool;
        break;

      case 'D':
        typeClass = DateTime;
        break;

      case '@':
        typeClass = DateTime;
        break;

      default:
        typeClass = String;
        break;
    }

    return typeClass;
  }

  void addColumnWithIntType(String inFieldName, int inFieldTypeInt,
      int inFieldLength, int inDecimalCount) {
    addColumn(inFieldName, String.fromCharCode(inFieldTypeInt), inFieldLength,
        inDecimalCount);
  }

  /**
     * Add a column to this DbaseFileHeader. The type is one of (C N L or D) character, number,
     * logical(true/false), or date. The Field length is the total length in bytes reserved for this
     * column. The decimal count only applies to numbers(N), and floating point values (F), and
     * refers to the number of characters to reserve after the decimal point. <B>Don't expect
     * miracles from this...</B>
     *
     * <PRE>
     * Field Type MaxLength
     * ---------- ---------
     * C          254
     * D          8
     * @          8
     * F          20
     * N          18
     * </PRE>
     *
     * @param inFieldName The name of the new field, must be less than 10 characters or it gets
     *     truncated.
     * @param inFieldType A character representing the dBase field, ( see above ). Case insensitive.
     * @param inFieldLength The length of the field, in bytes ( see above )
     * @param inDecimalCount For numeric fields, the number of decimal places to track.
     * @throws DbaseFileException If the type is not recognized.
     */
  void addColumn(String inFieldName, String inFieldType, int inFieldLength,
      int inDecimalCount) {
    if (inFieldLength <= 0) {
      throw new DbaseFileException("field length <= 0");
    }
    fields ??= [];

    int tempLength = 1; // the length is used for the offset, and there is a
    // * for deleted as the first byte
    List<DbaseField> tempFieldDescriptors = List(fields.length + 1);
    for (int i = 0; i < fields.length; i++) {
      fields[i].fieldDataAddress = tempLength;
      tempLength = tempLength + fields[i].fieldLength;
      tempFieldDescriptors[i] = fields[i];
    }
    tempFieldDescriptors[fields.length] = DbaseField();
    tempFieldDescriptors[fields.length].fieldLength = inFieldLength;
    tempFieldDescriptors[fields.length].decimalCount = inDecimalCount;
    tempFieldDescriptors[fields.length].fieldDataAddress = tempLength;

    // set the field name
    String tempFieldName = inFieldName;
    if (tempFieldName == null) {
      tempFieldName = "NoName";
    }
    // Fix for GEOT-42, ArcExplorer will not handle field names > 10 chars
    // Sorry folks.
    if (tempFieldName.length > 10) {
      tempFieldName = tempFieldName.substring(0, 10);
      LOGGER.w("FieldName " +
          inFieldName +
          " is longer than 10 characters, truncating to " +
          tempFieldName);
    }
    tempFieldDescriptors[fields.length].fieldName = tempFieldName;

    // the field type
    if ((inFieldType == 'C') || (inFieldType == 'c')) {
      tempFieldDescriptors[fields.length].fieldType = 'C'.codeUnitAt(0);
      if (inFieldLength > 254) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Which is longer than 254, not consistent with dbase III");
      }
    } else if ((inFieldType == 'S') || (inFieldType == 's')) {
      tempFieldDescriptors[fields.length].fieldType = 'C'.codeUnitAt(0);
      LOGGER.w("Field type for " +
          inFieldName +
          " set to S which is flat out wrong people!, I am setting this to C, in the hopes you meant character.");
      if (inFieldLength > 254) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Which is longer than 254, not consistent with dbase III");
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if ((inFieldType == 'D') || (inFieldType == 'd')) {
      tempFieldDescriptors[fields.length].fieldType = 'D'.codeUnitAt(0);
      if (inFieldLength != 8) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Setting to 8 digits YYYYMMDD");
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if (inFieldType == '@') {
      tempFieldDescriptors[fields.length].fieldType = '@'.codeUnitAt(0);
      if (inFieldLength != 8) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Setting to 8 digits - two longs," +
            "one long for date and one long for time");
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if ((inFieldType == 'F') || (inFieldType == 'f')) {
      tempFieldDescriptors[fields.length].fieldType = 'F'.codeUnitAt(0);
      if (inFieldLength > 20) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Preserving length, but should be set to Max of 20 not valid for dbase IV, and UP specification, not present in dbaseIII.");
      }
    } else if ((inFieldType == 'N') || (inFieldType == 'n')) {
      tempFieldDescriptors[fields.length].fieldType = 'N'.codeUnitAt(0);
      if (inFieldLength > 18) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Preserving length, but should be set to Max of 18 for dbase III specification.");
      }
      if (inDecimalCount < 0) {
        LOGGER.v("Field Decimal Position for " +
            inFieldName +
            " set to $inDecimalCount Setting to 0 no decimal data will be saved.");
        tempFieldDescriptors[fields.length].decimalCount = 0;
      }
      if (inDecimalCount > inFieldLength - 1) {
        LOGGER.w("Field Decimal Position for " +
            inFieldName +
            " set to $inDecimalCount Setting to ${inFieldLength - 1} no non decimal data will be saved.");
        tempFieldDescriptors[fields.length].decimalCount = inFieldLength - 1;
      }
    } else if ((inFieldType == 'L') || (inFieldType == 'l')) {
      tempFieldDescriptors[fields.length].fieldType = 'L'.codeUnitAt(0);
      if (inFieldLength != 1) {
        LOGGER.v("Field Length for " +
            inFieldName +
            " set to $inFieldLength Setting to length of 1 for logical fields.");
      }
      tempFieldDescriptors[fields.length].fieldLength = 1;
    } else {
      throw DbaseFileException(
          "Undefined field type " + inFieldType + " For column " + inFieldName);
    }
    // the length of a record
    tempLength = tempLength + tempFieldDescriptors[fields.length].fieldLength;

    // set the new fields.
    fields = tempFieldDescriptors;
    fieldCnt = fields.length;
    headerLength = MINIMUM_HEADER + 32 * fields.length;
    recordLength = tempLength;
  }

  /**
     * Remove a column from this DbaseFileHeader.
     *
     * @todo This is really ugly, don't know who wrote it, but it needs fixing...
     * @param inFieldName The name of the field, will ignore case and trim.
     * @return index of the removed column, -1 if no found
     */
  int removeColumn(String inFieldName) {
    int retCol = -1;
    var tempLength = 1;
    var tempFieldDescriptors = List<DbaseField>(fields.length - 1);
    for (var i = 0, j = 0; i < fields.length; i++) {
      if (!StringUtilities.equalsIgnoreCase(
          inFieldName, fields[i].fieldName.trim())) {
        // if this is the last field and we still haven't found the
        // named field
        if (i == j && i == fields.length - 1) {
          LOGGER.w(
              "Could not find a field named '" + inFieldName + "' for removal");
          return retCol;
        }
        tempFieldDescriptors[j] = fields[i];
        tempFieldDescriptors[j].fieldDataAddress = tempLength;
        tempLength += tempFieldDescriptors[j].fieldLength;
        // only increment j on non-matching fields
        j++;
      } else {
        retCol = i;
      }
    }

    // set the new fields.
    fields = tempFieldDescriptors;
    headerLength = 33 + 32 * fields.length;
    recordLength = tempLength;

    return retCol;
  }

  // Retrieve the length of the field at the given index
  /**
     * Returns the field length in bytes.
     *
     * @param inIndex The field index.
     * @return The length in bytes.
     */
  int getFieldLength(int inIndex) {
    return fields[inIndex].fieldLength;
  }

  // Retrieve the location of the decimal point within the field.
  /**
     * Get the decimal count of this field.
     *
     * @param inIndex The field index.
     * @return The decimal count.
     */
  int getFieldDecimalCount(int inIndex) {
    return fields[inIndex].decimalCount;
  }

  // Retrieve the Name of the field at the given index
  /**
     * Get the field name.
     *
     * @param inIndex The field index.
     * @return The name of the field.
     */
  String getFieldName(int inIndex) {
    return fields[inIndex].fieldName;
  }

  // Retrieve the type of field at the given index
  /**
     * Get the character class of the field.
     *
     * @param inIndex The field index.
     * @return The dbase character representing this field.
     */
  int getFieldType(int inIndex) {
    return fields[inIndex].fieldType;
  }

  /**
     * Get the date this file was last updated.
     *
     * @return The Date last modified.
     */
  DateTime getLastUpdateDate() {
    return date;
  }

  /**
     * Return the number of fields in the records.
     *
     * @return The number of fields in this table.
     */
  int getNumFields() {
    return fields.length;
  }

  /**
     * Return the number of records in the file
     *
     * @return The number of records in this table.
     */
  int getNumRecords() {
    return recordCnt;
  }

  /**
     * Get the length of the records in bytes.
     *
     * @return The number of bytes per record.
     */
  int getRecordLength() {
    return recordLength;
  }

  /**
     * Get the length of the header
     *
     * @return The length of the header in bytes.
     */
  int getHeaderLength() {
    return headerLength;
  }

  /**
     * Read the header data from the DBF file.
     *
     * @param channel A readable byte channel. If you have an InputStream you need to use, you can
     *     call java.nio.Channels.getChannel(InputStream in).
     * @ If errors occur while reading.
     */
  Future<void> readHeader(ChunkedStreamIterator channel) async {
    await readHeaderWithCharset(channel, Charset.defaultCharset());
  }

  /**
     * Read the header data from the DBF file.
     *
     * @param channel A readable byte channel. If you have an InputStream you need to use, you can
     *     call java.nio.Channels.getChannel(InputStream in).
     * @ If errors occur while reading.
     */
  Future<void> readHeaderWithCharset(
      ChunkedStreamIterator channel, Charset charset) async {
    // // do this or GO CRAZY
    // // ByteBuffers come preset to BIG_ENDIAN !
    // inBuf.order(ByteOrder.LITTLE_ENDIAN);
    Endian endian = Endian.little;
    // // only want to read first 10 bytes...
    // ((Buffer) inBuf).limit(10);

    // read(inBuf, channel);
    // inBuf.position(0);

    // type of file.
    int magic = (await channel.read(1))[0];
    if (magic != MAGIC) {
      throw ArgumentError("Unsupported DBF file Type $magic");
    }

    // parse the update date information.
    int tempUpdateYear = (await channel.read(1))[0];
    int tempUpdateMonth = (await channel.read(1))[0];
    int tempUpdateDay = (await channel.read(1))[0];
    // ouch Y2K uncompliant
    if (tempUpdateYear > 90) {
      tempUpdateYear = tempUpdateYear + 1900;
    } else {
      tempUpdateYear = tempUpdateYear + 2000;
    }
    // Calendar c = Calendar.getInstance();
    // c.set(Calendar.YEAR, tempUpdateYear);
    // c.set(Calendar.MONTH, tempUpdateMonth - 1);
    // c.set(Calendar.DATE, tempUpdateDay);
    // date = c.getTime();
    date = DateTime.utc(tempUpdateYear, tempUpdateMonth - 1, tempUpdateDay);

    // read the number of records.

    var data = Uint8List.fromList(await channel.read(4));
    recordCnt = ByteConversionUtilities.getInt32(data, endian);

    // read the length of the header structure.
    // ahhh.. unsigned little-endian shorts
    // mask out the byte and or it with shifted 2nd byte
    var list = await channel.read(2);
    headerLength = (list[0] & 0xff) | ((list[1] & 0xff) << 8);

    // read the length of a record
    // ahhh.. unsigned little-endian shorts
    list = await channel.read(2);
    recordLength = (list[0] & 0xff) | ((list[1] & 0xff) << 8);

    // skip the reserved bytes in the header.
    await channel.read(20);

    // calculate the number of Fields in the header
    fieldCnt =
        ((headerLength - FILE_DESCRIPTOR_SIZE - 1) / FILE_DESCRIPTOR_SIZE)
            .toInt();

    // read all of the header records
    List<DbaseField> lfields = [];
    for (var i = 0; i < fieldCnt; i++) {
      DbaseField field = DbaseField();

      // read the field name
      // List<int> buffer = List(11);
      // inBuf.get(buffer);
      List<int> buffer = (await channel.read(11));
      String name = charset.encode(buffer);
      int nullPoint = name.indexOf(String.fromCharCode(0));
      if (nullPoint != -1) {
        name = name.substring(0, nullPoint);
      }
      field.fieldName = name.trim();

      // read the field type
      field.fieldType = (await channel.read(1))[0];

      // read the field data address, offset from the start of the record.
      var data = Uint8List.fromList(await channel.read(4));
      field.fieldDataAddress = ByteConversionUtilities.getInt32(data, endian);

      // read the field length in bytes
      int length = (await channel.read(1))[0];
      if (length < 0) {
        length = length + 256;
      }
      field.fieldLength = length;

      if (length > largestFieldSize) {
        largestFieldSize = length;
      }

      // read the field decimal count in bytes
      field.decimalCount = (await channel.read(1))[0];

      // reserved bytes.
      // in.skipBytes(14);
      // inBuf.position(inBuf.position() + 14);
      await channel.read(14);

      // some broken shapefiles have 0-length attributes. The reference
      // implementation
      // (ArcExplorer 2.0, built with MapObjects) just ignores them.
      if (field.fieldLength > 0) {
        lfields.add(field);
      }
    }

    // Last byte is a marker for the end of the field definitions.
    // in.skipBytes(1);
    // inBuf.position(inBuf.position() + 1);
    await channel.read(1);

    // fields = DbaseField[lfields.size()];
    // fields = (DbaseField[]) lfields.toArray(fields);
    fields = lfields;
  }

  /**
     * Read the header data from the DBF file.
     *
     * @param in The ByteBuffer to read the header from
     * @ If errors occur while reading.
     */
  //  void readHeader(ByteBuffer in)  {
  //     // do this or GO CRAZY
  //     // ByteBuffers come preset to BIG_ENDIAN !
  //     in.order(ByteOrder.LITTLE_ENDIAN);

  //     // type of file.
  //     byte magic = in.get();
  //     if (magic != MAGIC) {
  //         throw new IOException("Unsupported DBF file Type " + Integer.toHexString(magic));
  //     }

  //     // parse the update date information.
  //     int tempUpdateYear = in.get();
  //     int tempUpdateMonth = in.get();
  //     int tempUpdateDay = in.get();
  //     // ouch Y2K uncompliant
  //     if (tempUpdateYear > 90) {
  //         tempUpdateYear = tempUpdateYear + 1900;
  //     } else {
  //         tempUpdateYear = tempUpdateYear + 2000;
  //     }
  //     Calendar c = Calendar.getInstance();
  //     c.set(Calendar.YEAR, tempUpdateYear);
  //     c.set(Calendar.MONTH, tempUpdateMonth - 1);
  //     c.set(Calendar.DATE, tempUpdateDay);
  //     date = c.getTime();

  //     // read the number of records.
  //     recordCnt = in.getInt();

  //     // read the length of the header structure.
  //     // ahhh.. unsigned little-endian shorts
  //     // mask out the byte and or it with shifted 2nd byte
  //     headerLength = (in.get() & 0xff) | ((in.get() & 0xff) << 8);

  //     // if the header is bigger than our 1K, reallocate
  //     if (headerLength > in.capacity()) {
  //         throw new IllegalArgumentException(
  //                 "The contract says the buffer should be long enough to fit all the header!");
  //     }

  //     // read the length of a record
  //     // ahhh.. unsigned little-endian shorts
  //     recordLength = (in.get() & 0xff) | ((in.get() & 0xff) << 8);

  //     // skip the reserved bytes in the header.
  //     in.position(in.position() + 20);

  //     // calculate the number of Fields in the header
  //     fieldCnt = (headerLength - FILE_DESCRIPTOR_SIZE - 1) / FILE_DESCRIPTOR_SIZE;

  //     // read all of the header records
  //     List<DbaseField> lfields = new ArrayList<>();
  //     for (int i = 0; i < fieldCnt; i++) {
  //         DbaseField field = new DbaseField();

  //         // read the field name
  //         byte[] buffer = new byte[11];
  //         in.get(buffer);
  //         String name = new String(buffer);
  //         int nullPoint = name.indexOf(0);
  //         if (nullPoint != -1) {
  //             name = name.substring(0, nullPoint);
  //         }
  //         field.fieldName = name.trim();

  //         // read the field type
  //         field.fieldType = (char) in.get();

  //         // read the field data address, offset from the start of the record.
  //         field.fieldDataAddress = in.getInt();

  //         // read the field length in bytes
  //         int length = (int) in.get();
  //         if (length < 0) {
  //             length = length + 256;
  //         }
  //         field.fieldLength = length;

  //         if (length > largestFieldSize) {
  //             largestFieldSize = length;
  //         }

  //         // read the field decimal count in bytes
  //         field.decimalCount = (int) in.get();

  //         // reserved bytes.
  //         // in.skipBytes(14);
  //         in.position(in.position() + 14);

  //         // some broken shapefiles have 0-length attributes. The reference
  //         // implementation
  //         // (ArcExplorer 2.0, built with MapObjects) just ignores them.
  //         if (field.fieldLength > 0) {
  //             lfields.add(field);
  //         }
  //     }

  //     // Last byte is a marker for the end of the field definitions.
  //     // in.skipBytes(1);
  //     in.position(in.position() + 1);

  //     fields = new DbaseField[lfields.size()];
  //     fields = (DbaseField[]) lfields.toArray(fields);
  // }

  /**
     * Get the largest field size of this table.
     *
     * @return The largest field size in bytes.
     */
  int getLargestFieldSize() {
    return largestFieldSize;
  }

  /**
     * Set the number of records in the file
     *
     * @param inNumRecords The number of records.
     */
  void setNumRecords(int inNumRecords) {
    recordCnt = inNumRecords;
  }

  /**
     * Write the header data to the DBF file.
     *
     * @param out A channel to write to. If you have an OutputStream you can obtain the correct
     *     channel by using java.nio.Channels.newChannel(OutputStream out).
     * @ If errors occur.
     */
  //  void writeHeader(WritableByteChannel out)  {
  //     // take care of the annoying case where no records have been added...
  //     if (headerLength == -1) {
  //         headerLength = MINIMUM_HEADER;
  //     }
  //     ByteBuffer buffer = NIOUtilities.allocate(headerLength);
  //     try {
  //         buffer.order(ByteOrder.LITTLE_ENDIAN);

  //         // write the output file type.
  //         buffer.put((byte) MAGIC);

  //         // write the date stuff
  //         Calendar c = Calendar.getInstance();
  //         c.setTime(new Date());
  //         buffer.put((byte) (c.get(Calendar.YEAR) % 100));
  //         buffer.put((byte) (c.get(Calendar.MONTH) + 1));
  //         buffer.put((byte) (c.get(Calendar.DAY_OF_MONTH)));

  //         // write the number of records in the datafile.
  //         buffer.putInt(recordCnt);

  //         // write the length of the header structure.
  //         buffer.putShort((short) headerLength);

  //         // write the length of a record
  //         buffer.putShort((short) recordLength);

  //         // // write the reserved bytes in the header
  //         // for (int i=0; i<20; i++) out.writeByteLE(0);
  //         buffer.position(buffer.position() + 20);

  //         // write all of the header records
  //         int tempOffset = 0;
  //         for (int i = 0; i < fields.length; i++) {

  //             // write the field name
  //             for (int j = 0; j < 11; j++) {
  //                 if (fields[i].fieldName.length() > j) {
  //                     buffer.put((byte) fields[i].fieldName.charAt(j));
  //                 } else {
  //                     buffer.put((byte) 0);
  //                 }
  //             }

  //             // write the field type
  //             buffer.put((byte) fields[i].fieldType);
  //             // // write the field data address, offset from the start of the
  //             // record.
  //             buffer.putInt(tempOffset);
  //             tempOffset += fields[i].fieldLength;

  //             // write the length of the field.
  //             buffer.put((byte) fields[i].fieldLength);

  //             // write the decimal count.
  //             buffer.put((byte) fields[i].decimalCount);

  //             // write the reserved bytes.
  //             // for (in j=0; jj<14; j++) out.writeByteLE(0);
  //             buffer.position(buffer.position() + 14);
  //         }

  //         // write the end of the field definitions marker
  //         buffer.put((byte) 0x0D);

  //         buffer.position(0);

  //         int r = buffer.remaining();
  //         while ((r -= out.write(buffer)) > 0) {; // do nothing
  //         }
  //     } finally {
  //         NIOUtilities.clean(buffer, false);
  //     }
  // }

  /**
     * Get a simple representation of this header.
     *
     * @return A String representing the state of the header.
     */
  String toString() {
    StringBuffer fs = new StringBuffer();
    for (int i = 0, ii = fields.length; i < ii; i++) {
      DbaseField f = fields[i];
      fs.write(f.fieldName +
          " ${f.fieldType} ${f.fieldLength} ${f.decimalCount} ${f.fieldDataAddress}\n");
    }

    return "DB3 Header\n" +
        "Date : " +
        date.toIso8601String() +
        "\n" +
        "Records : " +
        recordCnt.toString() +
        "\n" +
        "Fields : " +
        fieldCnt.toString() +
        "\n" +
        fs.toString();
  }

  /** Returns the expected file size for the given number of records in the file */
  int getLengthForRecords(int records) {
    return headerLength + records * recordLength;
  }
}

class Row {
  bool deleted = false;

  var fieldOffsets;

  var header;

  var readObject;

  Row(this.fieldOffsets, this.header, this.readObject);

  Object read(final int column) {
    final int offset = fieldOffsets[column];
    return readObject(offset, column);
  }

  String toString() {
    final ret = new StringBuffer("DBF Row - ");
    for (var i = 0; i < header.getNumFields(); i++) {
      ret.write(header.getFieldName(i));
      ret.write(": \"");
      try {
        ret.write(this.read(i));
      } catch (ioe) {
        ret.write(ioe.getMessage());
      }
      ret.write("\" ");
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
/// FileChannel in = new FileInputStream(&quot;thefile.dbf&quot;).getChannel();
/// DbaseFileReader r = new DbaseFileReader( in ) Object[] fields = new
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
/// FileChannel in = new FileInputStream(&quot;thefile.dbf&quot;).getChannel();
/// DbaseFileReader r = new DbaseFileReader( in ) int fields =
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
  static final NULL_CHAR = Characters('\x00');

  final int MILLISECS_PER_DAY = 24 * 60 * 60 * 1000;

  ChunkedStreamIterator<int> channel;
  Charset stringCharset;
  TimeZone timeZone;

  DbaseFileReader(File dbfFile,
      [final Charset charset, final TimeZone timeZone])
      : this.fromStream(
            ChunkedStreamIterator(dbfFile.openRead()), charset, timeZone);

  DbaseFileReader.fromStream(this.channel, this.stringCharset, this.timeZone);

  Future open() async {
    stringCharset = stringCharset ?? Charset.defaultCharset();
    // TimeZone calTimeZone = timeZone == null ? TimeZone.UTC : timeZone;

    header = DbaseFileHeader();

    // create the ByteBuffer
    // if we have a FileChannel, lets map it
    // if (channel instanceof FileChannel && this.useMemoryMappedBuffer) {
    //     final FileChannel fc = (FileChannel) channel;
    //     if ((fc.size() - fc.position()) < (long) Integer.MAX_VALUE) {
    //         buffer = fc.map(FileChannel.MapMode.READ_ONLY, 0, fc.size());
    //     } else {
    //         buffer = fc.map(FileChannel.MapMode.READ_ONLY, 0, Integer.MAX_VALUE);
    //     }
    //     buffer.position((int) fc.position());
    //     header.readHeader(buffer);

    //     this.currentOffset = 0;
    // } else {
    // Force useMemoryMappedBuffer to false
    await header.readHeaderWithCharset(channel, stringCharset);
    // // Some other type of channel
    // // size the buffer so that we can read 4 records at a time (and make the buffer
    // // cacheable)
    // // int size = (int) Math.pow(2, Math.ceil(Math.log(header.getRecordLength()) /
    // // Math.log(2)));
    // buffer = NIOUtilities.allocate(header.getRecordLength());
    // // fill it and reset
    // fill(buffer, channel);
    // buffer.flip();
    this.currentOffset = header.getHeaderLength();
    // }

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

  //  int fill(final ByteBuffer buffer, final ChunkedStreamIterator channel)
  //          {
  //     int r = buffer.remaining();
  //     // channel reads return -1 when EOF or other error
  //     // because they a non-blocking reads, 0 is a valid return value!!
  //     while (buffer.remaining() > 0 && r != -1) {
  //         r = channel.read(buffer);
  //     }
  //     if (r == -1) {
  //         buffer.limit(buffer.position());
  //     }
  //     return r;
  // }

  //  void bufferCheck()  {
  //     // remaining is less than record length
  //     // compact the remaining data and read again
  //         this.currentOffset += buffer.position();
  //         buffer.compact();
  //         fill(buffer, channel);
  //         buffer.position(0);
  // }

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
    if (channel != null
        // && channel.isOpen()
        ) {
      channel.cancel();
    }

    channel = null;
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

  /// Get the next record (entry). Will return a new array of values.
  ///
  /// @ If an error occurs.
  /// @return A new array of values.
  Future<List<dynamic>> readEntry() async {
    return await readEntryInto([header.getNumFields()]);
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

  /**
     * Reads the next record into memory. You need to use this directly when reading only a subset
     * of the fields using {@link #readField(int)}.
     */
  Future read() async {
    var foundRecord = false;
    while (!foundRecord) {
      // bufferCheck();

      // read the deleted flag
      final deleted = String.fromCharCode(
          (await channel.read(1))[0]); //   (    char) buffer.get();
      row.deleted = deleted == '*';

      bytes = await channel.read(header.getRecordLength() - 1);
      // buffer.limit(buffer.position() + header.getRecordLength() - 1);
      // buffer.get(bytes); // SK: There is a side-effect here!!!
      // buffer.limit(buffer.capacity());

      foundRecord = true;
    }

    cnt++;
  }

  /**
     * Copy the next entry into the array.
     *
     * @param entry The array to copy into.
     * @ If an error occurs.
     * @return The same array passed in.
     */
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
          // TODO CHECK: if the string begins with a null terminator, the value is null
          // var str = String.fromCharCode(bytes[fieldOffset]);
          // if (str != '\0') {
          // remember we need to skip trailing and leading spaces
          if (oneBytePerChar) {
            object = fastParse(bytes, fieldOffset, fieldLen).trim();
          } else {
            var sublist = bytes.sublist(fieldOffset, fieldOffset + fieldLen);
            var string = stringCharset.encode(sublist).trim();
            var characters = Characters(string);

            if (characters.endsWith(NULL_CHAR)) {
              string = Characters(string)
                  .skipLastWhile((c) => c == NULL_CHAR.toString())
                  .toString();
            }
            object = string;
            // new String(bytes, fieldOffset, fieldLen, stringCharset.name())
            //         .trim();
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
                final tempMonth = int.parse(tempString) - 1;
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
            // TODO: Find a smarter way to do this.
            // timestampBytes = bytes[fieldOffset:fieldOffset+7]
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
