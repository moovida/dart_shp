part of dart_shp;

/// The default JTS handler for shapefile. Currently uses the default JTS GeometryFactory, since it
/// doesn't seem to matter.
class MultiLineHandler implements ShapeHandler {
  late ShapeType shapeType;

  late GeometryFactory geometryFactory;

  // List<double> xy;

  // List<double> z;

  /// Create a MultiLineHandler for ShapeType.ARC */
  MultiLineHandler(GeometryFactory gf) {
    shapeType = ShapeType.ARC;
    geometryFactory = gf;
  }

  /// Create a MultiLineHandler for one of: <br>
  /// ShapeType.ARC,ShapeType.ARCM,ShapeType.ARCZ
  ///
  /// @param type The ShapeType to use.
  /// @throws ShapefileException If the ShapeType is not correct (see constructor).
  MultiLineHandler.withType(ShapeType type, GeometryFactory gf) {
    if (!type.isLineType()) {
      throw ShapefileException(
          "MultiLineHandler constructor - expected type to be 3,13 or 23");
    }

    shapeType = type;
    geometryFactory = gf;
  }

  /// Get the type of shape stored (ShapeType.ARC,ShapeType.ARCM,ShapeType.ARCZ) */
  @override
  ShapeType getShapeType() {
    return shapeType;
  }

  @override
  int getLength(dynamic geometry) {
    MultiLineString multi = geometry as MultiLineString;

    int numlines;
    int numpoints;
    int length;

    numlines = multi.getNumGeometries();
    numpoints = multi.getNumPoints();

    if (shapeType == ShapeType.ARC) {
      length = 44 + (4 * numlines) + (numpoints * 16);
    } else if (shapeType == ShapeType.ARCM) {
      length = 44 + (4 * numlines) + (numpoints * 16) + 8 + 8 + (8 * numpoints);
    } else if (shapeType == ShapeType.ARCZ) {
      length = 44 +
          (4 * numlines) +
          (numpoints * 16) +
          8 +
          8 +
          (8 * numpoints) +
          8 +
          8 +
          (8 * numpoints);
    } else {
      throw StateError("Expected ShapeType of Arc, got $shapeType");
    }

    return length;
  }

  dynamic createNull() {
    return geometryFactory.createMultiLineString(null);
  }

  @override
  dynamic read(LByteBuffer buffer, ShapeType? type, bool flatGeometry) {
    if (type == ShapeType.NULL) {
      return createNull();
    }
    int dimensions =
        ((shapeType == ShapeType.ARCZ || shapeType == ShapeType.ARCM) &&
                !flatGeometry)
            ? 3
            : 2;
    // read bounding box (not needed)
    buffer.position = buffer.position + 4 * 8;

    int numParts = buffer.getInt32();
    int numPoints = buffer.getInt32(); // total number of points

    List<int> partOffsets = List.filled(numParts, 0);

    // points = new Coordinate[numPoints];
    for (int i = 0; i < numParts; i++) {
      partOffsets[i] = buffer.getInt32();
    }
    // read the first two coordinates and start building the coordinate
    // sequences
    List<CoordinateSequence> lines = []; //List(numParts);
    int finish, start = 0;
    int length = 0;
    bool clonePoint = false;
    // final DoubleBuffer doubleBuffer = buffer.asDoubleBuffer();
    for (int part = 0; part < numParts; part++) {
      start = partOffsets[part];

      if (part == (numParts - 1)) {
        finish = numPoints;
      } else {
        finish = partOffsets[part + 1];
      }

      length = finish - start;
      int xyLength = length;
      if (length == 1) {
        length = 2;
        clonePoint = true;
      } else {
        clonePoint = false;
      }

      CoordinateSequence cs;
      int measure = flatGeometry ? 0 : 1;
      if (shapeType == ShapeType.ARCM) {
        cs = Shapeutils.createCSMeas(
            geometryFactory.getCoordinateSequenceFactory(),
            length,
            dimensions + measure,
            measure);
      } else if (shapeType == ShapeType.ARCZ) {
        cs = Shapeutils.createCSMeas(
            geometryFactory.getCoordinateSequenceFactory(),
            length,
            dimensions + measure,
            measure);
      } else {
        cs = Shapeutils.createCS(
            geometryFactory.getCoordinateSequenceFactory(), length, dimensions);
      }
      // List<double> xy = new double[xyLength * 2];
      // doubleBuffer.get(xy);
      List<double> xy = List.filled(xyLength * 2, 0.0);
      for (var i = 0; i < xy.length; i++) {
        xy[i] = buffer.getDouble64();
      }

      for (int i = 0; i < xyLength; i++) {
        cs.setOrdinate(i, CoordinateSequence.X, xy[i * 2]);
        cs.setOrdinate(i, CoordinateSequence.Y, xy[i * 2 + 1]);
      }

      if (clonePoint) {
        cs.setOrdinate(
            1, CoordinateSequence.X, cs.getOrdinate(0, CoordinateSequence.X));
        cs.setOrdinate(
            1, CoordinateSequence.Y, cs.getOrdinate(0, CoordinateSequence.Y));
      }

      lines.add(cs);
      // lines[part] = cs;
    }

    // if we have another coordinate, read and add to the coordinate
    // sequences
    if (shapeType == ShapeType.ARCZ && !flatGeometry) {
      // z min, max
      // buffer.position(buffer.position() + 2 * 8);
      // doubleBuffer.position(doubleBuffer.position() + 2);
      buffer.position = buffer.position + 2 * 8;
      for (int part = 0; part < numParts; part++) {
        start = partOffsets[part];

        if (part == (numParts - 1)) {
          finish = numPoints;
        } else {
          finish = partOffsets[part + 1];
        }

        length = finish - start;
        if (length == 1) {
          length = 2;
          clonePoint = true;
        } else {
          clonePoint = false;
        }

        // List<double> z = new double[length];
        // doubleBuffer.get(z);
        List<double> z = List.filled(length, 0.0);
        for (var i = 0; i < z.length; i++) {
          z[i] = buffer.getDouble64();
        }

        for (int i = 0; i < length; i++) {
          lines[part].setOrdinate(i, CoordinateSequence.Z, z[i]);
        }
      }
    }
    if ((shapeType == ShapeType.ARCZ || shapeType == ShapeType.ARCM) &&
        !flatGeometry) {
      // M min, max
      // buffer.position(buffer.position() + 2 * 8);
      // doubleBuffer.position(doubleBuffer.position() + 2);
      buffer.position = buffer.position + 2 * 8;
      for (int part = 0; part < numParts; part++) {
        start = partOffsets[part];

        if (part == (numParts - 1)) {
          finish = numPoints;
        } else {
          finish = partOffsets[part + 1];
        }

        length = finish - start;
        if (length == 1) {
          length = 2;
          clonePoint = true;
        } else {
          clonePoint = false;
        }

        // List<double> m = new double[length];
        // doubleBuffer.get(m);
        List<double> m = List.filled(length, 0.0);
        for (var i = 0; i < m.length; i++) {
          m[i] = buffer.getDouble64();
        }
        for (int i = 0; i < length; i++) {
          lines[part].setOrdinate(i, CoordinateSequence.M, m[i]);
        }
      }
    }

    // Prepare line strings and return the multilinestring
    List<LineString> lineStrings = []; // List(numParts);
    for (int part = 0; part < numParts; part++) {
      lineStrings.add(geometryFactory.createLineStringSeq(lines[part]));
      // lineStrings[part] = geometryFactory.createLineStringSeq(lines[part]);
    }

    return geometryFactory.createMultiLineString(lineStrings);
  }

  @override
  void write(LByteBuffer buffer, dynamic geometry) {
    MultiLineString multi = geometry as MultiLineString;

    Envelope box = multi.getEnvelopeInternal();
    buffer.putDouble64(box.getMinX());
    buffer.putDouble64(box.getMinY());
    buffer.putDouble64(box.getMaxX());
    buffer.putDouble64(box.getMaxY());

    final int numParts = multi.getNumGeometries();
    final List<CoordinateSequence> lines = [];
    final List<double> zExtreame = [double.nan, double.nan];
    final int npoints = multi.getNumPoints();

    buffer.putInt32(numParts);
    buffer.putInt32(npoints);

    {
      int idx = 0;
      for (int i = 0; i < numParts; i++) {
        lines[i] =
            (multi.getGeometryN(i) as LineString).getCoordinateSequence();
        buffer.putInt32(idx);
        idx = idx + lines[i].size();
      }
    }

    for (int lineN = 0; lineN < lines.length; lineN++) {
      CoordinateSequence coords = lines[lineN];
      if (shapeType == ShapeType.ARCZ) {
        Shapeutils.zMinMax(coords, zExtreame);
      }
      final int ncoords = coords.size();

      for (int t = 0; t < ncoords; t++) {
        buffer.putDouble64(coords.getX(t));
        buffer.putDouble64(coords.getY(t));
      }
    }

    if (shapeType == ShapeType.ARCZ) {
      if (zExtreame[0].isNaN) {
        buffer.putDouble64(0.0);
        buffer.putDouble64(0.0);
      } else {
        buffer.putDouble64(zExtreame[0]);
        buffer.putDouble64(zExtreame[1]);
      }

      for (int lineN = 0; lineN < lines.length; lineN++) {
        final CoordinateSequence coords = lines[lineN];
        final int ncoords = coords.size();
        double z;
        for (int t = 0; t < ncoords; t++) {
          z = coords.getOrdinate(t, 2);
          if (z.isNaN) {
            buffer.putDouble64(0.0);
          } else {
            buffer.putDouble64(z);
          }
        }
      }
    }

    // if there are M coordinates
    if (shapeType == ShapeType.ARCZ || shapeType == ShapeType.ARCM) {
      // get M values list
      List<double> mvalues = [];
      for (int t = 0, tt = multi.getNumGeometries(); t < tt; t++) {
        LineString line = multi.getGeometryN(t) as LineString;
        CoordinateSequence seq = line.getCoordinateSequence();
        for (int i = 0; i < seq.size(); i++) {
          mvalues.add(line.getCoordinateSequence().getM(i));
        }
      }

      // min, max
      double min = mvalues.reduce(math.min);
      double max = mvalues.reduce(math.max);
      buffer.putDouble64(min);
      buffer.putDouble64(max);
      // encode all M values
      mvalues.forEach((x) {
        buffer.putDouble64(x);
      });
    }
  }
}
