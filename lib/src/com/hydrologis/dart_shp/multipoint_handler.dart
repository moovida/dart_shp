part of dart_shp;

/// @author aaime
/// @author Ian Schneider
class MultiPointHandler implements ShapeHandler {
  ShapeType shapeType;
  GeometryFactory geometryFactory;

  /// Creates new MultiPointHandler */
  MultiPointHandler(GeometryFactory gf) {
    shapeType = ShapeType.POINT;
    geometryFactory = gf;
  }

  MultiPointHandler.withType(ShapeType type, GeometryFactory gf) {
    if (!type.isMultiPointType()) {
      throw ShapefileException(
          "Multipointhandler constructor - expected type to be 8, 18, or 28");
    }

    shapeType = type;
    geometryFactory = gf;
  }

  /// Returns the shapefile shape type value for a point
  ///
  /// @return int Shapefile.MULTIPOINT
  @override
  ShapeType getShapeType() {
    return shapeType;
  }

  /// Calcuates the record length of this object.
  ///
  /// @return int The length of the record that this shapepoint will take up in a shapefile
  @override
  int getLength(dynamic geometry) {
    MultiPoint mp = geometry as MultiPoint;

    int length;

    if (shapeType == ShapeType.MULTIPOINT) {
      // two doubles per coord (16 * numgeoms) + 40 for header
      length = (mp.getNumGeometries() * 16) + 40;
    } else if (shapeType == ShapeType.MULTIPOINTM) {
      // add the additional MMin, MMax for 16, then 8 per measure
      length =
          (mp.getNumGeometries() * 16) + 40 + 16 + (8 * mp.getNumGeometries());
    } else if (shapeType == ShapeType.MULTIPOINTZ) {
      // add the additional ZMin,ZMax, plus 8 per Z
      length = (mp.getNumGeometries() * 16) +
          40 +
          16 +
          (8 * mp.getNumGeometries()) +
          16 +
          (8 * mp.getNumGeometries());
    } else {
      throw StateError("Expected ShapeType of Arc, got $shapeType");
    }

    return length;
  }

  dynamic createNull() {
    return geometryFactory.createMultiPointSeq(null);
  }

  @override
  dynamic read(LByteBuffer buffer, ShapeType type, bool flatGeometry) {
    if (type == ShapeType.NULL) {
      return createNull();
    }

    // read bounding box (not needed)
    buffer.position = buffer.position + 4 * 8;

    int numpoints = buffer.getInt32();
    int dimensions =
        shapeType == ShapeType.MULTIPOINTZ && !flatGeometry ? 3 : 2;
    int measure = flatGeometry ? 0 : 1;
    CoordinateSequence cs;
    if (shapeType == ShapeType.MULTIPOINTZ ||
        shapeType == ShapeType.MULTIPOINTM) {
      cs = Shapeutils.createCSMeas(
          geometryFactory.getCoordinateSequenceFactory(),
          numpoints,
          dimensions + measure,
          measure);
    } else {
      cs = Shapeutils.createCS(geometryFactory.getCoordinateSequenceFactory(),
          numpoints, dimensions);
    }

    // DoubleBuffer dbuffer = buffer.asDoubleBuffer();
    // double[] ordinates = new double[numpoints * 2];
    // dbuffer.get(ordinates);
    List<double> ordinates = List(numpoints * 2);
    for (var i = 0; i < ordinates.length; i++) {
      ordinates[i] = buffer.getDouble64();
    }

    for (int t = 0; t < numpoints; t++) {
      cs.setOrdinate(t, CoordinateSequence.X, ordinates[t * 2]);
      cs.setOrdinate(t, CoordinateSequence.Y, ordinates[t * 2 + 1]);
    }

    if (shapeType == ShapeType.MULTIPOINTZ && !flatGeometry) {
      // dbuffer.position(dbuffer.position() + 2);
      buffer.position = buffer.position + 2 * 8;
      for (var i = 0; i < numpoints; i++) {
        ordinates[i] = buffer.getDouble64();
      }
      // dbuffer.get(ordinates, 0, numpoints);

      for (int t = 0; t < numpoints; t++) {
        cs.setOrdinate(t, CoordinateSequence.Z, ordinates[t]); // z
      }
    }

    if ((shapeType == ShapeType.MULTIPOINTZ ||
            shapeType == ShapeType.MULTIPOINTM) &&
        !flatGeometry) {
      // Handle M
      buffer.position = buffer.position + 2 * 8;
      // dbuffer.position(dbuffer.position() + 2);
      for (var i = 0; i < numpoints; i++) {
        ordinates[i] = buffer.getDouble64();
      }
      // dbuffer.get(ordinates, 0, numPoints);

      for (int t = 0; t < numpoints; t++) {
        cs.setOrdinate(t, CoordinateSequence.M, ordinates[t]); // m
      }
    }

    return geometryFactory.createMultiPointSeq(cs);
  }

  @override
  void write(LByteBuffer buffer, Object geometry) {
    MultiPoint mp = geometry as MultiPoint;

    Envelope box = mp.getEnvelopeInternal();
    buffer.putDouble64(box.getMinX());
    buffer.putDouble64(box.getMinY());
    buffer.putDouble64(box.getMaxX());
    buffer.putDouble64(box.getMaxY());

    buffer.putInt32(mp.getNumGeometries());

    for (int t = 0, tt = mp.getNumGeometries(); t < tt; t++) {
      Coordinate c = (mp.getGeometryN(t)).getCoordinate();
      buffer.putDouble64(c.x);
      buffer.putDouble64(c.y);
    }

    if (shapeType == ShapeType.MULTIPOINTZ) {
      List<double> result = [double.nan, double.nan];
      Shapeutils.zMinMax(CoordinateArraySequence(mp.getCoordinates()), result);
      List<double> zExtreame = result;

      if (zExtreame[0].isNaN) {
        buffer.putDouble64(0.0);
        buffer.putDouble64(0.0);
      } else {
        buffer.putDouble64(zExtreame[0]);
        buffer.putDouble64(zExtreame[1]);
      }

      for (int t = 0; t < mp.getNumGeometries(); t++) {
        Coordinate c = (mp.getGeometryN(t)).getCoordinate();
        double z = c.getZ();

        if (z.isNaN) {
          buffer.putDouble64(0.0);
        } else {
          buffer.putDouble64(z);
        }
      }
    }
    // if have M coordinates
    if (shapeType == ShapeType.MULTIPOINTM ||
        shapeType == ShapeType.MULTIPOINTZ) {
      // obtain all M values
      List<double> mvalues = [];
      for (int t = 0, tt = mp.getNumGeometries(); t < tt; t++) {
        Point point = mp.getGeometryN(t) as Point;
        mvalues.add(point.getCoordinateSequence().getM(0));
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
