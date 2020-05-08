part of dart_shp;

/// A DbaseFileWriter is used to write a dbase III format file. The general use of this class is:
/// <CODE><PRE>
/// DbaseFileHeader header = ...
/// WritableFileChannel out = new FileOutputStream(&quot;thefile.dbf&quot;).getChannel();
/// DbaseFileWriter w = new DbaseFileWriter(header,out);
/// while ( moreRecords ) {
///   w.write( getMyRecord() );
/// }
/// w.close();
/// </PRE></CODE> You must supply the <CODE>moreRecords</CODE> and <CODE>getMyRecord()</CODE>
/// logic...
///
/// @author Ian Schneider
class DbaseFileWriter {
  DbaseFileHeader header;
  FieldFormatter formatter;
  FileWriter channel;

  /// The null values to use for each column. This will be accessed only when null values are
  /// actually encountered, but it is allocated in the ctor to save time and memory.
  List<List<int>> nullValues;

  Charset charset;
  TimeZones timeZone;

  bool reportFieldSizeErrors =
      true; // ("org.geotools.shapefile.reportFieldSizeErrors");

  /// Create a DbaseFileWriter using the specified header and writing to the given channel.
  ///
  /// @param header The DbaseFileHeader to write.
  /// @param out The Channel to write to.
  /// @param charset The charset the dbf is (will be) encoded in
  /// @throws IOException If errors occur while initializing.
  DbaseFileWriter(this.header, this.channel, [this.charset, this.timeZone]);

  Future<void> open() async {
    await header.writeHeader(channel);
    charset = charset ??= Charset.defaultCharset();
    timeZone = timeZone ??= TimeZones.getDefault();
    formatter = FieldFormatter(charset, timeZone, !reportFieldSizeErrors);

    // As the 'shapelib' osgeo project does, we use specific values for
    // null cells. We can set up these values for each column once, in
    // the constructor, to save time and memory.
    nullValues = List(header.getNumFields());
    for (int i = 0; i < nullValues.length; i++) {
      String nullChar;
      var fieldType = String.fromCharCode(header.getFieldType(i));
      switch (fieldType) {
        case 'C':
        case 'c':
        case 'M':
        case 'G':
          nullChar = NULL_CHAR;
          break;
        case 'L':
        case 'l':
          nullChar = '?';
          break;
        case 'N':
        case 'n':
        case 'F':
        case 'f':
          nullChar = '*';
          break;
        case 'D':
        case 'd':
          nullChar = '0';
          break;
        case '@':
          // becomes day 0 time 0.
          nullChar = NULL_CHAR;
          break;
        default:
          // catches at least 'D', and 'd'
          nullChar = '0';
          break;
      }
      nullValues[i] =
          List.filled(header.getFieldLength(i), nullChar.codeUnitAt(0));
    }
  }

  Future<void> write(List<int> buffer) async {
    await channel.put(buffer);

    // buffer.position(0);
    // int r = buffer.remaining();
    // while ((r -= channel.write(buffer)) > 0) {; // do nothing
    // }
  }

  /// Write a single dbase record.
  ///
  /// @param record The entries to write.
  /// @throws IOException If IO error occurs.
  /// @throws DbaseFileException If the entry doesn't comply to the header.
  Future<void> writeRecord(List<dynamic> record) async {
    if (record.length != header.getNumFields()) {
      throw DbaseFileException(
          'Wrong number of fields ${record.length} expected ${header.getNumFields()}');
    }

    List<int> buffer = [];
    // put the 'not-deleted' marker
    buffer.add(' '.codeUnitAt(0));

    for (int i = 0; i < header.getNumFields(); i++) {
      // convert this column to bytes
      List<int> bytes;
      if (record[i] == null) {
        bytes = nullValues[i];
      } else {
        bytes = fieldBytes(record[i], i);
        // if the returned array is not the proper length
        // write a null instead; this will only happen
        // when the formatter handles a value improperly.
        if (bytes.length != nullValues[i].length) {
          bytes = nullValues[i];
        }
      }
      buffer.addAll(bytes);
    }

    await write(buffer);
  }

  /// Called to convert the given object to bytes.
  ///
  /// @param obj The value to convert; never null.
  /// @param col The column this object will be encoded into.
  /// @return The bytes of a string representation of the given object in the current character
  ///     encoding.
  /// @throws UnsupportedEncodingException Thrown if the current charset is unsupported.
  List<int> fieldBytes(Object obj, final int col) {
    String o;
    final int fieldLen = header.getFieldLength(col);
    var fieldType = header.getFieldType(col);
    switch (String.fromCharCode(fieldType)) {
      case 'C':
      case 'c':
        o = formatter.getFieldString(fieldLen, obj.toString());
        break;
      case 'L':
      case 'l':
        if (obj is bool) {
          o = obj ? 'T' : 'F';
        } else {
          o = '?';
        }
        break;
      case 'M':
      case 'G':
        o = formatter.getFieldString(fieldLen, obj.toString());
        break;
      case 'N':
      case 'n':
        // int?
        if (header.getFieldDecimalCount(col) == 0) {
          o = formatter.getFieldStringWithDec(fieldLen, 0, obj as num);
          break;
        }
        // else fall into float mode
        o = formatter.getFieldStringWithDec(
            fieldLen, header.getFieldDecimalCount(col), obj as num);
        break;
      case 'F':
      case 'f':
        o = formatter.getFieldStringWithDec(
            fieldLen, header.getFieldDecimalCount(col), obj as num);
        break;
      case 'D':
      case 'd':
        if (obj is DateTime) {
          o = formatter.getFieldStringDate(obj);
        }
        break;
      case '@':
        o = formatter.getFieldStringDate(obj);
        // TODO check back on this
        // if (bool.getbool("org.geotools.shapefile.datetime")) {
        //     // Adding the charset to getBytes causes the output to
        //     // get altered for the '@: Timestamp' field.
        //     // And using String.getBytes returns a different array
        //     // in 64-bit platforms so we get chars and cast to byte
        //     // one element at a time.
        //     char[] carr = o.toCharArray();
        //     byte[] barr = new byte[carr.length];
        //     for (int i = 0; i < carr.length; i++) {
        //         barr[i] = (byte) carr[i];
        //     }
        //     return barr;
        // }
        break;
      default:
        throw ArgumentError(
            'Unknown type ' + header.getFieldType(col).toString());
    }

    // convert the string to bytes with the given charset.
    return charset.decode(o);
  }

  /// Release resources associated with this writer. <B>Highly recommended</B>
  ///
  /// @throws IOException If errors occur.
  void close() {
    // IANS - GEOT 193, bogus 0x00 written. According to dbf spec, optional
    // eof 0x1a marker is, well, optional. Since the original code wrote a
    // 0x00 (which is wrong anyway) lets just do away with this :)
    // - produced dbf works in OpenOffice and ArcExplorer java, so it must
    // be okay.
    // buffer.position(0);
    // buffer.put((byte) 0).position(0).limit(1);
    // write();
    if (channel != null && channel.isOpen) {
      channel.close();
    }
    channel = null;
    formatter = null;
  }

  bool getReportFieldSizeErrors() {
    return reportFieldSizeErrors;
  }

  void setReportFieldSizeErrors(bool reportFieldSizeErrors) {
    this.reportFieldSizeErrors = reportFieldSizeErrors;
  }

  DbaseFileHeader getHeader() {
    return header;
  }
}

/// Utility for formatting Dbase fields. */
class FieldFormatter {
  //  StringBuffer buffer = StringBuffer(255);
  NumberFormat numFormat = NumberFormat.decimalPattern('en_US');
  final int MILLISECS_PER_DAY = 24 * 60 * 60 * 1000;

  String emptyString;
  static final int MAXCHARS = 255;
  Charset charset;

  bool swallowFieldSizeErrors = false;

  FieldFormatter(
      Charset charset, TimeZones timeZone, bool swallowFieldSizeErrors) {
    // Avoid grouping on number format
    numFormat.turnOffGrouping(); // setGroupingUsed(false);
    // build a 255 white spaces string
    emptyString = createEmptyString();

    this.charset = charset;

    timeZone.setZone('en_US');
    // this.calendar = Calendar.getInstance(timeZone, Locale.US);

    this.swallowFieldSizeErrors = swallowFieldSizeErrors;
  }

  String createEmptyString() {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < MAXCHARS; i++) {
      sb.write(' ');
    }
    return sb.toString();
  }

  String getFieldString(int size, String s) {
    try {
      String buffer = createEmptyString();
      // buffer.replace(0, size, emptyString);
      // buffer.setLength(size);
      if (buffer.length > size) {
        buffer = buffer.substring(0, size);
      }

      // international characters must be accounted for so size != length.
      int maxSize = size;
      if (s != null) {
        buffer = buffer.replaceRange(0, size, s);
        // TODO here Characters might be used
        var subStr = s.substring(0, math.min(size, s.length));
        int currentBytes = charset.decode(subStr).length;
        // int currentBytes =
        //         subStr
        //                 .getBytes(charset.name())
        //                 .length;
        if (currentBytes > size) {
          // char[] c = new char[1];
          // for (int index = size - 1; currentBytes > size; index--) {
          //     c[0] = buffer.charAt(index);
          //     String string = new String(c);
          //     buffer.deleteCharAt(index);
          //     currentBytes -= string.getBytes().length;
          //     maxSize--;
          // }
          buffer = buffer.substring(0, size);
        } else {
          if (s.length < size) {
            maxSize = size - (currentBytes - s.length);
            for (int i = s.length; i < size; i++) {
              buffer += ' ';
            }
          }
        }
      }

      // buffer.setLength(maxSize);
      if (buffer.length > maxSize) {
        buffer = buffer.substring(0, maxSize);
      }
      return buffer.toString();
    } catch (e) {
      print('ERROR: This error should never occurr');
      rethrow;
    }
  }

  String getFieldStringDate(DateTime d) {
    StringBuffer buffer = StringBuffer();
    if (d != null) {
      int year = d.year; //calendar.get(Calendar.YEAR);
      int month = d.month; // calendar.get(Calendar.MONTH) + 1;
      int day = d.day; // calendar.get(Calendar.DAY_OF_MONTH);

      if (year < 1000) {
        if (year >= 100) {
          buffer.write('0');
        } else if (year >= 10) {
          buffer.write('00');
        } else {
          buffer.write('000');
        }
      }
      buffer.write(year);

      if (month < 10) {
        buffer.write('0');
      }
      buffer.write(month);

      if (day < 10) {
        buffer.write('0');
      }
      buffer.write(day);
    } else {
      buffer.write('        '); // 8 spaces
    }
    return buffer.toString();
  }

  String getFieldStringDateTime(DateTime d) {
    // Sanity check
    if (d == null) return null;

    final int difference =
        d.millisecondsSinceEpoch - DbaseFileHeader.MILLIS_SINCE_4713;

    final int days = (difference ~/ MILLISECS_PER_DAY);
    final int time = (difference % MILLISECS_PER_DAY);

    List<int> outBytes = [
      ...ByteConversionUtilities.bytesFromInt32(days),
      ...ByteConversionUtilities.bytesFromInt32(time),
    ];
    return String.fromCharCodes(outBytes);
    // try (ByteArrayOutputStream o_bytes = new ByteArrayOutputStream();
    //         DataOutputStream o_stream =
    //                 new DataOutputStream(new BufferedOutputStream(o_bytes))) {
    //                   B

    //     o_stream.writeInt(days);
    //     o_stream.writeInt(time);
    //     o_stream.flush();
    //     byte[] bytes = o_bytes.toByteArray();
    //     // Cast the byte values to char as a workaround for erroneous byte
    //     // array retrieval in 64-bit machines
    //     char[] out = {
    //         // Days, after reverse.
    //         (char) bytes[3], (char) bytes[2], (char) bytes[1], (char) bytes[0],
    //         // Time in millis, after reverse.
    //         (char) bytes[7], (char) bytes[6], (char) bytes[5], (char) bytes[4],
    //     };

    //     return new String(out);
    // } catch ( e) {
    //     // This is always just a int serialization,
    //     // there is no way to recover from here.
    //     return null;
    // }
  }

  String getFieldStringWithDec(int size, int decimalPlaces, num n) {
    StringBuffer buffer = StringBuffer();

    if (n != null) {
      double dval = n.toDouble();

      /* DecimalFormat documentation:
                 * NaN is formatted as a string, which typically has a single character \uFFFD.
                 * This string is determined by the DecimalFormatSymbols object.
                 * This is the only value for which the prefixes and suffixes are not used.
                 *
                 * Infinity is formatted as a string, which typically has a single character \u221E,
                 * with the positive or negative prefixes and suffixes applied.
                 * The infinity string is determined by the DecimalFormatSymbols object.
                 */
      /* However, the Double.toString method returns an ascii string, which is more ESRI-friendly */
      if (dval.isNaN || dval.isInfinite) {
        buffer.write(n.toString());
        /* Should we use toString for integral numbers as well? */
      } else {
        var maxDig = decimalPlaces > 16 ? 16 : decimalPlaces;
        var toAdd = decimalPlaces - 16;

        numFormat.maximumFractionDigits = maxDig;
        numFormat.minimumFractionDigits = decimalPlaces;
        // FieldPosition fp = new FieldPosition(NumberFormat.FRACTION_FIELD);
        // numFormat.format(n, buffer, fp);
        String numStr = numFormat.format(n);
        for (var i = 0; i < toAdd; i++) {
          numStr += '0';
        }
        buffer.write(numStr);

        // large-magnitude numbers may overflow the field size in non-exponent notation,
        // so do a safety check and fall back to native representation to preserve value
        // TODO check the impact of this, hope for testcase
        // if (fp.getBeginIndex() >= size) {
        //     buffer.delete(0, buffer.length());
        //     buffer.append(n.toString());
        //     if (buffer.length() > size) {
        //         // we have a grevious problem -- the value does not fit in the required
        //         // size.
        //         LOGGER.w(
        //                 'Writing DBF data, value $n cannot be represented in size $size');
        //         if (!swallowFieldSizeErrors) {
        //             // rather than truncate, and corrupt the data, we throw a Runtime
        //             throw  ArgumentError(
        //                     'Value $n cannot be represented in size $size');
        //         }
        //     }
        // }
      }
    }

    String outBuf = buffer.toString();
    int diff = size - buffer.length;
    if (diff > 0) {
      for (var i = 0; i < diff; i++) {
        outBuf = ' ' + outBuf;
      }
      // buffer.insert(0, emptyString.substring(0, diff));
    } else if (diff < 0) {
      outBuf = outBuf.substring(0, size);
      // buffer.setLength(size);
    }
    return outBuf;
  }
}
