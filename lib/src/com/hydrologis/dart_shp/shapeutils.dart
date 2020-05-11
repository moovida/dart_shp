part of dart_shp;

class Feature {
  Geometry geometry;

  Map<String, dynamic> attributes = {};
}

/// Thrown when an error relating to the shapefile occurs. */
class ShapefileException implements Exception {
  String msg;
  Exception cause;

  ShapefileException(this.msg);

  ShapefileException.withCause(this.msg, this.cause);

  @override
  String toString() => 'ShapefileException: ' + msg;
}

class Shapeutils {
  /// Creates a {@link CoordinateSequence} using the provided factory confirming the provided size
  /// and dimension are respected.
  ///
  /// <p>If the requested dimension is larger than the CoordinateSequence implementation can
  /// provide, then a sequence of maximum possible dimension should be created. An error should not
  /// be thrown.
  ///
  /// <p>This method is functionally identical to calling csFactory.create(size,dim) - it contains
  /// additional logic to work around a limitation on the commonly used
  /// CoordinateArraySequenceFactory.
  ///
  /// @param size the number of coordinates in the sequence
  /// @param dimension the dimension of the coordinates in the sequence
  static CoordinateSequence createCS(
      CoordinateSequenceFactory csFactory, int size, int dimension) {
    // the coordinates don't have measures
    return createCSMeas(csFactory, size, dimension, 0);
  }

  /// Creates a {@link CoordinateSequence} using the provided factory confirming the provided size
  /// and dimension are respected.
  ///
  /// <p>If the requested dimension is larger than the CoordinateSequence implementation can
  /// provide, then a sequence of maximum possible dimension should be created. An error should not
  /// be thrown.
  ///
  /// <p>This method is functionally identical to calling csFactory.create(size,dim) - it contains
  /// additional logic to work around a limitation on the commonly used
  /// CoordinateArraySequenceFactory.
  ///
  /// @param size the number of coordinates in the sequence
  /// @param dimension the dimension of the coordinates in the sequence
  /// @param measures the measures of the coordinates in the sequence
  static CoordinateSequence createCSMeas(CoordinateSequenceFactory csFactory,
      int size, int dimension, int measures) {
    CoordinateSequence cs;
    if (csFactory is CoordinateArraySequenceFactory && dimension == 1) {
      // work around JTS 1.14 CoordinateArraySequenceFactory regression ignoring provided
      // dimension
      cs = CoordinateArraySequence.fromSizeDimensionMeasures(
          size, dimension, measures);
    } else {
      cs = csFactory.createSizeDimMeas(size, dimension, measures);
    }
    if (cs.getDimension() != dimension) {
      // illegal state error, try and fix
      throw StateError(
          "Unable to use $csFactory to produce CoordinateSequence with dimension $dimension");
    }
    return cs;
  }
}

/// A ShapeHandler defines what is needed to construct and persist geometries based upon the
/// shapefile specification.
///
/// @author aaime
/// @author Ian Schneider
abstract class ShapeHandler {
  /// Get the ShapeType of this handler.
  ///
  /// @return The ShapeType.
  ShapeType getShapeType();

  /// Read a geometry from the ByteBuffer. The buffer's position, byteOrder, and limit are set to
  /// that which is needed. The record has been read as well as the shape type integer. The handler
  /// need not worry about reading unused information as the ShapefileReader will correctly adjust
  /// the buffer position after this call.
  ///
  /// @param buffer The ByteBuffer to read from.
  /// @return A geometry object.
  dynamic read(LByteBuffer buffer, ShapeType type, bool flatGeometry);

  /// Write the geometry into the ByteBuffer. The position, byteOrder, and limit are all set. The
  /// handler is not responsible for writing the record or shape type integer.
  ///
  /// @param buffer The ByteBuffer to write to.
  /// @param geometry The geometry to write.
  void write(LByteBuffer buffer, Object geometry);

  /// Get the length of the given geometry Object in <b>bytes</b> not 16-bit words. This is easier
  /// to keep track of, since the ByteBuffer deals with bytes. <b>Do not include the 8 bytes of
  /// record.</b>
  ///
  /// @param geometry The geometry to analyze.
  /// @return The number of <b>bytes</b> the shape will take up.
  int getLength(dynamic geometry);
}

/// Not much but a type safe enumeration of file types as ints and names. The descriptions can easily
/// be tied to a ResourceBundle if someone wants to do that.
///
/// @author Ian Schneider
class ShapeType {
  /// The integer id of this ShapeType.
  final int id;

  /// The human-readable name for this ShapeType.<br>
  /// Could easily use ResourceBundle for internationialization.
  final String name;
  const ShapeType._(this.id, this.name);

  /// Represents a Null shape (id = 0).
  static const NULL = ShapeType._(0, 'Null');

  /// Represents a Point shape (id = 1).
  static const POINT = ShapeType._(1, 'Point');

  /// Represents a PointZ shape (id = 11).
  static const POINTZ = ShapeType._(11, 'PointZ');

  /// Represents a PointM shape (id = 21).
  static const POINTM = ShapeType._(21, 'PointM');

  /// Represents an Arc shape (id = 3).
  static const ARC = ShapeType._(3, 'Arc');

  /// Represents an ArcZ shape (id = 13).
  static const ARCZ = ShapeType._(13, 'ArcZ');

  /// Represents an ArcM shape (id = 23).
  static const ARCM = ShapeType._(23, 'ArcM');

  /// Represents a Polygon shape (id = 5).
  static const POLYGON = ShapeType._(5, 'Polygon');

  /// Represents a PolygonZ shape (id = 15).
  static const POLYGONZ = ShapeType._(15, 'PolygonZ');

  /// Represents a PolygonM shape (id = 25).
  static const POLYGONM = ShapeType._(25, 'PolygonM');

  /// Represents a MultiPoint shape (id = 8).
  static const MULTIPOINT = ShapeType._(8, 'MultiPoint');

  /// Represents a MultiPointZ shape (id = 18).
  static const MULTIPOINTZ = ShapeType._(18, 'MultiPointZ');

  /// Represents a MultiPointM shape (id = 28).
  static const MULTIPOINTM = ShapeType._(28, 'MultiPointM');

  /// Represents an Undefined shape (id = -1).
  static const UNDEFINED = ShapeType._(-1, 'Undefined');

  /// Get the name of this ShapeType.
  ///
  /// @return The name.
  @override
  String toString() {
    return name;
  }

  /// Is this a multipoint shape? Hint- all shapes are multipoint except NULL, UNDEFINED, and the
  /// POINTs.
  ///
  /// @return true if multipoint, false otherwise.
  bool isMultiPoint() {
    if (this == UNDEFINED) {
      return false;
    } else if (this == NULL) {
      return false;
    } else if (this == POINT || this == POINTM || this == POINTZ) {
      return false;
    }
    return true;
  }

  bool isPointType() {
    return id % 10 == 1;
  }

  bool isLineType() {
    return id % 10 == 3;
  }

  bool isPolygonType() {
    return id % 10 == 5;
  }

  bool isMultiPointType() {
    return id % 10 == 8;
  }

  /// Determine the ShapeType for the id.
  ///
  /// @param id The id to search for.
  /// @return The ShapeType for the id.
  static ShapeType forID(int id) {
    switch (id) {
      case 0:
        return NULL;
      case 1:
        return POINT;
      case 11:
        return POINTZ;
      case 21:
        return POINTM;
      case 3:
        return ARC;
      case 13:
        return ARCZ;
      case 23:
        return ARCM;
      case 5:
        return POLYGON;
      case 15:
        return POLYGONZ;
      case 25:
        return POLYGONM;
      case 8:
        return MULTIPOINT;
      case 18:
        return MULTIPOINTZ;
      case 28:
        return MULTIPOINTM;
      default:
        return UNDEFINED;
    }
  }

  /// Each ShapeType corresponds to a handler. In the future this should probably go else where to
  /// allow different handlers, or something...
  ///
  /// @throws ShapefileException If the ShapeType is bogus.
  /// @return The correct handler for this ShapeType. Returns a new one.
  ShapeHandler getShapeHandler(GeometryFactory gf) {
    switch (id) {
      case 1:
      case 11:
      case 21:
        return PointHandler.withType(this, gf);
      case 3:
      case 13:
      case 23:
        throw ArgumentError("MultiLine handling not implemented yet.");
      // return new MultiLineHandler(this, gf);
      case 5:
      case 15:
      case 25:
        throw ArgumentError("Polygon handling not implemented yet.");
      // return new PolygonHandler(this, gf);
      case 8:
      case 18:
      case 28:
        throw ArgumentError("MultiPoint handling not implemented yet.");
      // return new MultiPointHandler(this, gf);
      default:
        return null;
    }
  }
}
