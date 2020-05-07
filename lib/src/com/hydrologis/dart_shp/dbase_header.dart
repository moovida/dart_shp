part of dart_shp;

/// This file has been ported from the geotools.org project.

/// Thrown when an error relating to the shapefile occurs. */
class DbaseFileException implements Exception {
  String msg;
  Exception cause;

  DbaseFileException(this.msg);

  DbaseFileException.withCause(this.msg, this.cause);

  @override
  String toString() => 'DbaseFileException: ' + msg;
}

/// Class for holding the information associated with a record. */
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

/// Class to represent the header of a Dbase III file. Creation date: (5/15/2001 5:15:30 PM) */
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

  // set this to a default length of 1, which is enough for one 'space'
  // character which signifies an empty record
  int recordLength = 1;

  // set this to a flagged value so if no fields are added before the write,
  // we know to adjust the headerLength to MINIMUM_HEADER
  int headerLength = -1;

  int largestFieldSize = 0;

  /// Returns the number of millis at January 1st 4713 BC
  ///
  /// <p>Calendar refCal = (Calendar) GregorianCalendar(TimeZone.getTimeZone('UTC'));
  /// refCal.set(Calendar.ERA, GregorianCalendar.BC); refCal.set(Calendar.YEAR, 4713);
  /// refCal.set(Calendar.MONTH, Calendar.JANUARY); refCal.set(Calendar.DAY_OF_MONTH, 1);
  /// refCal.set(Calendar.HOUR, 12); refCal.set(Calendar.MINUTE, 0); refCal.set(Calendar.SECOND,
  /// 0); refCal.set(Calendar.MILLISECOND, 0); MILLIS_SINCE_4713 = refCal.getTimeInMillis() -
  /// 43200000L; //(43200000L: 12 hour correction factor taken from DBFViewer2000)
  static int MILLIS_SINCE_4713 = -210866803200000;

  // Collection of header records.
  // lets start out with a zero-length array, just in case
  List<DbaseField> fields = [];

  /// Determine the most appropriate Java Class for representing the data in the field.
  ///
  /// <PRE>
  /// All packages are java.lang unless otherwise specified.
  /// C (Character) -&gt; String
  /// N (Numeric)   -&gt; Integer or Long or Double (depends on field's decimal count and fieldLength)
  /// F (Floating)  -&gt; Double
  /// L (Logical)   -&gt; Boolean
  /// D (Date)      -&gt; java.util.Date (Without time)
  /// @ (Timestamp) -&gt; java.sql.Timestamp (With time)
  /// Unknown       -&gt; String
  /// </PRE>
  ///
  /// @param i The index of the field, from 0 to <CODE>getNumFields() - 1</CODE> .
  /// @return A Class which closely represents the dbase field type.
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

  /// Add a column to this DbaseFileHeader. The type is one of (C N L or D) character, number,
  /// logical(true/false), or date. The Field length is the total length in bytes reserved for this
  /// column. The decimal count only applies to numbers(N), and floating point values (F), and
  /// refers to the number of characters to reserve after the decimal point. <B>Don't expect
  /// miracles from this...</B>
  ///
  /// <PRE>
  /// Field Type MaxLength
  /// ---------- ---------
  /// C          254
  /// D          8
  /// @          8
  /// F          20
  /// N          18
  /// </PRE>
  ///
  /// @param inFieldName The name of the field, must be less than 10 characters or it gets
  ///     truncated.
  /// @param inFieldType A character representing the dBase field, ( see above ). Case insensitive.
  /// @param inFieldLength The length of the field, in bytes ( see above )
  /// @param inDecimalCount For numeric fields, the number of decimal places to track.
  /// @throws DbaseFileException If the type is not recognized.
  void addColumn(String inFieldName, String inFieldType, int inFieldLength,
      int inDecimalCount) {
    if (inFieldLength <= 0) {
      throw DbaseFileException('field length <= 0');
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
      tempFieldName = 'NoName';
    }
    // Fix for GEOT-42, ArcExplorer will not handle field names > 10 chars
    // Sorry folks.
    if (tempFieldName.length > 10) {
      tempFieldName = tempFieldName.substring(0, 10);
      LOGGER.w('FieldName ' +
          inFieldName +
          ' is longer than 10 characters, truncating to ' +
          tempFieldName);
    }
    tempFieldDescriptors[fields.length].fieldName = tempFieldName;

    // the field type
    if ((inFieldType == 'C') || (inFieldType == 'c')) {
      tempFieldDescriptors[fields.length].fieldType = 'C'.codeUnitAt(0);
      if (inFieldLength > 254) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Which is longer than 254, not consistent with dbase III');
      }
    } else if ((inFieldType == 'S') || (inFieldType == 's')) {
      tempFieldDescriptors[fields.length].fieldType = 'C'.codeUnitAt(0);
      LOGGER.w('Field type for ' +
          inFieldName +
          ' set to S which is flat out wrong people!, I am setting this to C, in the hopes you meant character.');
      if (inFieldLength > 254) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Which is longer than 254, not consistent with dbase III');
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if ((inFieldType == 'D') || (inFieldType == 'd')) {
      tempFieldDescriptors[fields.length].fieldType = 'D'.codeUnitAt(0);
      if (inFieldLength != 8) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Setting to 8 digits YYYYMMDD');
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if (inFieldType == '@') {
      tempFieldDescriptors[fields.length].fieldType = '@'.codeUnitAt(0);
      if (inFieldLength != 8) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Setting to 8 digits - two longs,' +
            'one long for date and one long for time');
      }
      tempFieldDescriptors[fields.length].fieldLength = 8;
    } else if ((inFieldType == 'F') || (inFieldType == 'f')) {
      tempFieldDescriptors[fields.length].fieldType = 'F'.codeUnitAt(0);
      if (inFieldLength > 20) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Preserving length, but should be set to Max of 20 not valid for dbase IV, and UP specification, not present in dbaseIII.');
      }
    } else if ((inFieldType == 'N') || (inFieldType == 'n')) {
      tempFieldDescriptors[fields.length].fieldType = 'N'.codeUnitAt(0);
      if (inFieldLength > 18) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Preserving length, but should be set to Max of 18 for dbase III specification.');
      }
      if (inDecimalCount < 0) {
        LOGGER.v('Field Decimal Position for ' +
            inFieldName +
            ' set to $inDecimalCount Setting to 0 no decimal data will be saved.');
        tempFieldDescriptors[fields.length].decimalCount = 0;
      }
      if (inDecimalCount > inFieldLength - 1) {
        LOGGER.w('Field Decimal Position for ' +
            inFieldName +
            ' set to $inDecimalCount Setting to ${inFieldLength - 1} no non decimal data will be saved.');
        tempFieldDescriptors[fields.length].decimalCount = inFieldLength - 1;
      }
    } else if ((inFieldType == 'L') || (inFieldType == 'l')) {
      tempFieldDescriptors[fields.length].fieldType = 'L'.codeUnitAt(0);
      if (inFieldLength != 1) {
        LOGGER.v('Field Length for ' +
            inFieldName +
            ' set to $inFieldLength Setting to length of 1 for logical fields.');
      }
      tempFieldDescriptors[fields.length].fieldLength = 1;
    } else {
      throw DbaseFileException(
          'Undefined field type ' + inFieldType + ' For column ' + inFieldName);
    }
    // the length of a record
    tempLength = tempLength + tempFieldDescriptors[fields.length].fieldLength;

    // set the fields.
    fields = tempFieldDescriptors;
    fieldCnt = fields.length;
    headerLength = MINIMUM_HEADER + 32 * fields.length;
    recordLength = tempLength;
  }

  /// Remove a column from this DbaseFileHeader.
  ///
  /// @todo This is really ugly, don't know who wrote it, but it needs fixing...
  /// @param inFieldName The name of the field, will ignore case and trim.
  /// @return index of the removed column, -1 if no found
  int removeColumn(String inFieldName) {
    var retCol = -1;
    var tempLength = 1;
    var tempFieldDescriptors = List<DbaseField>(fields.length - 1);
    for (var i = 0, j = 0; i < fields.length; i++) {
      if (!StringUtilities.equalsIgnoreCase(
          inFieldName, fields[i].fieldName.trim())) {
        // if this is the last field and we still haven't found the
        // named field
        if (i == j && i == fields.length - 1) {
          LOGGER.w('Could not find a field named '
              ' + inFieldName + '
              ' for removal');
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

    // set the fields.
    fields = tempFieldDescriptors;
    headerLength = 33 + 32 * fields.length;
    recordLength = tempLength;

    return retCol;
  }

  /// Returns the field length in bytes.
  ///
  /// @param inIndex The field index.
  /// @return The length in bytes.
  int getFieldLength(int inIndex) {
    return fields[inIndex].fieldLength;
  }

  /// Get the decimal count of this field.
  ///
  /// @param inIndex The field index.
  /// @return The decimal count.
  int getFieldDecimalCount(int inIndex) {
    return fields[inIndex].decimalCount;
  }

  /// Get the field name.
  ///
  /// @param inIndex The field index.
  /// @return The name of the field.
  String getFieldName(int inIndex) {
    return fields[inIndex].fieldName;
  }

  /// Get the character class of the field.
  ///
  /// @param inIndex The field index.
  /// @return The dbase character representing this field.
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
  Future<void> readHeader(FileReader channel) async {
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
      FileReader channel, Charset charset) async {
    Endian endian = Endian.little;

    // type of file.
    int magic = await channel.getByte();
    if (magic != MAGIC) {
      throw ArgumentError('Unsupported DBF file Type $magic');
    }

    // parse the update date information.
    int tempUpdateYear = await channel.getByte();
    int tempUpdateMonth = await channel.getByte();
    int tempUpdateDay = await channel.getByte();
    // ouch Y2K uncompliant
    if (tempUpdateYear > 90) {
      tempUpdateYear = tempUpdateYear + 1900;
    } else {
      tempUpdateYear = tempUpdateYear + 2000;
    }
    date = DateTime.utc(tempUpdateYear, tempUpdateMonth - 1, tempUpdateDay);

    // read the number of records.

    recordCnt = await channel.getInt32(endian);

    // read the length of the header structure.
    // ahhh.. unsigned little-endian shorts
    // mask out the byte and or it with shifted 2nd byte
    var list = await channel.get(2);
    headerLength = (list[0] & 0xff) | ((list[1] & 0xff) << 8);

    // read the length of a record
    // ahhh.. unsigned little-endian shorts
    list = await channel.get(2);
    recordLength = (list[0] & 0xff) | ((list[1] & 0xff) << 8);

    // skip the reserved bytes in the header.
    await channel.skip(20);

    // calculate the number of Fields in the header
    fieldCnt =
        ((headerLength - FILE_DESCRIPTOR_SIZE - 1) / FILE_DESCRIPTOR_SIZE)
            .toInt();

    // read all of the header records
    List<DbaseField> lfields = [];
    for (var i = 0; i < fieldCnt; i++) {
      DbaseField field = DbaseField();

      List<int> buffer = (await channel.get(11));
      String name = charset.encode(buffer);
      int nullPoint = name.indexOf(String.fromCharCode(0));
      if (nullPoint != -1) {
        name = name.substring(0, nullPoint);
      }
      field.fieldName = name.trim();

      // read the field type
      field.fieldType = await channel.getByte();

      // read the field data address, offset from the start of the record.
      field.fieldDataAddress = await channel.getInt32(endian);

      // read the field length in bytes
      int length = await channel.getByte();
      if (length < 0) {
        length = length + 256;
      }
      field.fieldLength = length;

      if (length > largestFieldSize) {
        largestFieldSize = length;
      }

      // read the field decimal count in bytes
      field.decimalCount = await channel.getByte();

      // reserved bytes.
      await channel.skip(14);

      // some broken shapefiles have 0-length attributes. The reference
      // implementation
      // (ArcExplorer 2.0, built with MapObjects) just ignores them.
      if (field.fieldLength > 0) {
        lfields.add(field);
      }
    }

    // Last byte is a marker for the end of the field definitions.
    await channel.skip(1);

    fields = lfields;
  }

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
  //         c.setTime(Date());
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
    StringBuffer fs = StringBuffer();
    for (int i = 0, ii = fields.length; i < ii; i++) {
      DbaseField f = fields[i];
      fs.write(f.fieldName +
          ' ${f.fieldType} ${f.fieldLength} ${f.decimalCount} ${f.fieldDataAddress}\n');
    }

    return 'DB3 Header\n' +
        'Date : ' +
        date.toIso8601String() +
        '\n' +
        'Records : ' +
        recordCnt.toString() +
        '\n' +
        'Fields : ' +
        fieldCnt.toString() +
        '\n' +
        fs.toString();
  }

  /** Returns the expected file size for the given number of records in the file */
  int getLengthForRecords(int records) {
    return headerLength + records * recordLength;
  }
}
