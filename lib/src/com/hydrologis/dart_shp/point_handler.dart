part of dart_shp;

/// Wrapper for a Shapefile point.
///
/// @author aaime
/// @author Ian Schneider
class PointHandler extends ShapeHandler {
  ShapeType shapeType;
  GeometryFactory geometryFactory;

  PointHandler.withType(ShapeType type, GeometryFactory gf) {
    if ((type != ShapeType.POINT) &&
        (type != ShapeType.POINTM) &&
        (type != ShapeType.POINTZ)) {
      // 2d, 2d+m, 3d+m
      throw ShapefileException(
          "PointHandler constructor: expected a type of 1, 11 or 21");
    }

    shapeType = type;
    geometryFactory = gf;
  }

  PointHandler() {
    shapeType = ShapeType.POINT; // 2d
  }

  /// Returns the shapefile shape type value for a point
  ///
  /// @return int Shapefile.POINT
  @override
  ShapeType getShapeType() {
    return shapeType;
  }

  @override
  int getLength(dynamic geometry) {
    int length;
    if (shapeType == ShapeType.POINT) {
      length = 20;
    } else if (shapeType == ShapeType.POINTM) {
      length = 28;
    } else if (shapeType == ShapeType.POINTZ) {
      length = 36;
    } else {
      throw StateError("Expected ShapeType of Point, got $shapeType");
    }
    return length;
  }

  @override
  dynamic read(LByteBuffer buffer, ShapeType type, bool flatGeometry) {
    if (type == ShapeType.NULL) {
      return createNull();
    }

    Coordinate c;
    if (shapeType == ShapeType.POINTZ) {
      c = CoordinateXYZM.empty();
    } else if (shapeType == ShapeType.POINTM) {
      c = CoordinateXYM.empty();
    } else {
      c = CoordinateXY();
    }
    c.setX(buffer.getDouble64());
    c.setY(buffer.getDouble64());

    if (shapeType == ShapeType.POINTM) {
      c.setM(buffer.getDouble64());
    }

    if (shapeType == ShapeType.POINTZ) {
      c.setZ(buffer.getDouble64());
      c.setM(buffer.getDouble64());
    }

    return geometryFactory.createPoint(c);
  }

  Object createNull() {
    return geometryFactory
        .createPoint(Coordinate.fromXYZ(double.nan, double.nan, double.nan));
  }

  @override
  void write(LByteBuffer buffer, Object geometry) {
    Point point = geometry as Point;
    Coordinate c = point.getCoordinate();

    buffer.putDouble64(c.x);
    buffer.putDouble64(c.y);

    if (shapeType == ShapeType.POINTZ) {
      if (c.getZ().isNaN) {
        // nan means not defined
        buffer.putDouble64(0.0);
      } else {
        buffer.putDouble64(c.getZ());
      }
    }

    if ((shapeType == ShapeType.POINTZ) || (shapeType == ShapeType.POINTM)) {
      double m = point.getCoordinateSequence().getM(0);
      buffer.putDouble64(m.isNaN ? 0.0 : m); // M
    }
  }
}
