part of dart_shp;

class Feature {
  Geometry? geometry;

  int? fid;

  Map<String, dynamic> attributes = {};

  @override
  String toString() {
    String attr = "";
    attributes.forEach((k, v) {
      attr += "\n\t--> $k: ${v.toString()}";
    });

    return "fid: $fid:\n\tgeom: ${geometry.toString()},\n\tattributes:$attr";
  }
}

/// Thrown when an error relating to the shapefile occurs. */
class ShapefileException implements Exception {
  String msg;
  Exception? cause;

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

  /// Determine the min and max "z" values in an array of Coordinates.
  ///
  /// @param cs The array to search.
  /// @param target array with at least two elements where to hold the min and max zvalues.
  ///     target[0] will be filled with the minimum zvalue, target[1] with the maximum. The array
  ///     current values, if not NaN, will be taken into acount in the computation.
  static void zMinMax(final CoordinateSequence cs, List<double> target) {
    if (cs.getDimension() < 3) {
      return;
    }
    double zmin;
    double zmax;
    bool validZFound = false;

    zmin = double.nan;
    zmax = double.nan;

    double z;
    final int size = cs.size();
    for (int t = size - 1; t >= 0; t--) {
      z = cs.getOrdinate(t, 2);

      if (!(z.isNaN)) {
        if (validZFound) {
          if (z < zmin) {
            zmin = z;
          }

          if (z > zmax) {
            zmax = z;
          }
        } else {
          validZFound = true;
          zmin = z;
          zmax = z;
        }
      }
    }

    if (!zmin.isNaN) {
      target[0] = zmin;
    }
    if (!zmax.isNaN) {
      target[1] = (zmax);
    }
  }

  /// Computes whether a ring defined by an array of {@link Coordinate}s is oriented
  /// counter-clockwise.
  ///
  /// <ul>
  ///   <li>The list of points is assumed to have the first and last points equal.
  ///   <li>This will handle coordinate lists which contain repeated points.
  /// </ul>
  ///
  /// This algorithm is <b>only</b> guaranteed to work with valid rings. If the ring is invalid
  /// (e.g. self-crosses or touches), the computed result may not be correct.
  ///
  /// @param ring an array of Coordinates forming a ring
  /// @return true if the ring is oriented counter-clockwise.
  static bool isCCW(CoordinateSequence ring) {
    // # of points without closing endpoint
    int nPts = ring.size() - 1;

    // find highest point
    double hiy = ring.getOrdinate(0, 1);
    int hiIndex = 0;
    for (int i = 1; i <= nPts; i++) {
      if (ring.getOrdinate(i, 1) > hiy) {
        hiy = ring.getOrdinate(i, 1);
        hiIndex = i;
      }
    }

    // find distinct point before highest point
    int iPrev = hiIndex;
    do {
      iPrev = iPrev - 1;
      if (iPrev < 0) iPrev = nPts;
    } while (equals2D(ring, iPrev, hiIndex) && iPrev != hiIndex);

    // find distinct point after highest point
    int iNext = hiIndex;
    do {
      iNext = (iNext + 1) % nPts;
    } while (equals2D(ring, iNext, hiIndex) && iNext != hiIndex);

    /**
         * This check catches cases where the ring contains an A-B-A configuration of points. This
         * can happen if the ring does not contain 3 distinct points (including the case where the
         * input array has fewer than 4 elements), or it contains coincident line segments.
         */
    if (equals2D(ring, iPrev, hiIndex) ||
        equals2D(ring, iNext, hiIndex) ||
        equals2D(ring, iPrev, iNext)) return false;

    int disc = computeOrientation(ring, iPrev, hiIndex, iNext);

    /**
         * If disc is exactly 0, lines are collinear. There are two possible cases: (1) the lines
         * lie along the x axis in opposite directions (2) the lines lie on top of one another
         *
         * <p>(1) is handled by checking if next is left of prev ==> CCW (2) will never happen if
         * the ring is valid, so don't check for it (Might want to assert this)
         */
    bool isCCW = false;
    if (disc == 0) {
      // poly is CCW if prev x is right of next x
      isCCW = (ring.getOrdinate(iPrev, 0) > ring.getOrdinate(iNext, 0));
    } else {
      // if area is positive, points are ordered CCW
      isCCW = (disc > 0);
    }
    return isCCW;
  }

  static bool equals2D(CoordinateSequence cs, int i, int j) {
    return cs.getOrdinate(i, 0) == cs.getOrdinate(j, 0) &&
        cs.getOrdinate(i, 1) == cs.getOrdinate(j, 1);
  }

  static int computeOrientation(CoordinateSequence cs, int p1, int p2, int q) {
    // travelling along p1->p2, turn counter clockwise to get to q return 1,
    // travelling along p1->p2, turn clockwise to get to q return -1,
    // p1, p2 and q are colinear return 0.
    double p1x = cs.getOrdinate(p1, 0);
    double p1y = cs.getOrdinate(p1, 1);
    double p2x = cs.getOrdinate(p2, 0);
    double p2y = cs.getOrdinate(p2, 1);
    double qx = cs.getOrdinate(q, 0);
    double qy = cs.getOrdinate(q, 1);
    double dx1 = p2x - p1x;
    double dy1 = p2y - p1y;
    double dx2 = qx - p2x;
    double dy2 = qy - p2y;
    return RobustDeterminant.signOfDet2x2(dx1, dy1, dx2, dy2);
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
  dynamic read(LByteBuffer buffer, ShapeType? type, bool flatGeometry);

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
  ShapeHandler? getShapeHandler(GeometryFactory gf) {
    switch (id) {
      case 1:
      case 11:
      case 21:
        return PointHandler.withType(this, gf);
      case 3:
      case 13:
      case 23:
        return MultiLineHandler.withType(this, gf);
      case 5:
      case 15:
      case 25:
        return PolygonHandler.withType(this, gf);
      case 8:
      case 18:
      case 28:
        return MultiPointHandler.withType(this, gf);
      default:
        return null;
    }
  }
}

/**
 * Implements an algorithm to compute the sign of a 2x2 determinant for double precision values
 * robustly. It is a direct translation of code developed by Olivier Devillers.
 *
 * <p>The original code carries the following copyright notice:
 *
 * <pre>
 * ************************************************************************
 * Author : Olivier Devillers
 * Olivier.Devillers@sophia.inria.fr
 * http:/www.inria.fr:/prisme/personnel/devillers/anglais/determinant.html
 *
 * Olivier Devillers has allowed the code to be distributed under
 * the LGPL (2012-02-16) saying "It is ok for LGPL distribution."
 *
 * *************************************************************************
 *
 * *************************************************************************
 *              Copyright (c) 1995  by  INRIA Prisme Project
 *                  BP 93 06902 Sophia Antipolis Cedex, France.
 *                           All rights reserved
 * *************************************************************************
 * </pre>
 */
class RobustDeterminant {
  // public static int callCount = 0; // debugging only

  static int signOfDet2x2(double x1, double y1, double x2, double y2) {
    // returns -1 if the determinant is negative,
    // returns 1 if the determinant is positive,
    // retunrs 0 if the determinant is null.
    int sign;
    double swap;
    double k;
    int count = 0;

    // callCount++; // debugging only

    sign = 1;

    /*
         * testing null entries
         */
    if ((x1 == 0.0) || (y2 == 0.0)) {
      if ((y1 == 0.0) || (x2 == 0.0)) {
        return 0;
      } else if (y1 > 0) {
        if (x2 > 0) {
          return -sign;
        } else {
          return sign;
        }
      } else {
        if (x2 > 0) {
          return sign;
        } else {
          return -sign;
        }
      }
    }
    if ((y1 == 0.0) || (x2 == 0.0)) {
      if (y2 > 0) {
        if (x1 > 0) {
          return sign;
        } else {
          return -sign;
        }
      } else {
        if (x1 > 0) {
          return -sign;
        } else {
          return sign;
        }
      }
    }

    /*
         * making y coordinates positive and permuting the entries
         */
    /*
         * so that y2 is the biggest one
         */
    if (0.0 < y1) {
      if (0.0 < y2) {
        if (y1 > y2) {
          sign = -sign;
          swap = x1;
          x1 = x2;
          x2 = swap;
          swap = y1;
          y1 = y2;
          y2 = swap;
        }
      } else {
        if (y1 <= -y2) {
          sign = -sign;
          x2 = -x2;
          y2 = -y2;
        } else {
          swap = x1;
          x1 = -x2;
          x2 = swap;
          swap = y1;
          y1 = -y2;
          y2 = swap;
        }
      }
    } else {
      if (0.0 < y2) {
        if (-y1 <= y2) {
          sign = -sign;
          x1 = -x1;
          y1 = -y1;
        } else {
          swap = -x1;
          x1 = x2;
          x2 = swap;
          swap = -y1;
          y1 = y2;
          y2 = swap;
        }
      } else {
        if (y1 >= y2) {
          x1 = -x1;
          y1 = -y1;
          x2 = -x2;
          y2 = -y2;
        } else {
          sign = -sign;
          swap = -x1;
          x1 = -x2;
          x2 = swap;
          swap = -y1;
          y1 = -y2;
          y2 = swap;
        }
      }
    }

    /*
         * making x coordinates positive
         */
    /*
         * if |x2| < |x1| one can conclude
         */
    if (0.0 < x1) {
      if (0.0 < x2) {
        if (x1 > x2) {
          return sign;
        }
      } else {
        return sign;
      }
    } else {
      if (0.0 < x2) {
        return -sign;
      } else {
        if (x1 >= x2) {
          sign = -sign;
          x1 = -x1;
          x2 = -x2;
        } else {
          return -sign;
        }
      }
    }

    /*
         * all entries strictly positive x1 <= x2 and y1 <= y2
         */
    while (true) {
      count = count + 1;
      k = (x2 / x1).floorToDouble();
      x2 = x2 - k * x1;
      y2 = y2 - k * y1;

      /*
             * testing if R (new U2) is in U1 rectangle
             */
      if (y2 < 0.0) {
        return -sign;
      }
      if (y2 > y1) {
        return sign;
      }

      /*
             * finding R'
             */
      if (x1 > x2 + x2) {
        if (y1 < y2 + y2) {
          return sign;
        }
      } else {
        if (y1 > y2 + y2) {
          return -sign;
        } else {
          x2 = x1 - x2;
          y2 = y1 - y2;
          sign = -sign;
        }
      }
      if (y2 == 0.0) {
        if (x2 == 0.0) {
          return 0;
        } else {
          return -sign;
        }
      }
      if (x2 == 0.0) {
        return sign;
      }

      /*
             * exchange 1 and 2 role.
             */
      k = (x1 / x2).floorToDouble();
      x1 = x1 - k * x2;
      y1 = y1 - k * y2;

      /*
             * testing if R (new U1) is in U2 rectangle
             */
      if (y1 < 0.0) {
        return sign;
      }
      if (y1 > y2) {
        return -sign;
      }

      /*
             * finding R'
             */
      if (x2 > x1 + x1) {
        if (y2 < y1 + y1) {
          return -sign;
        }
      } else {
        if (y2 > y1 + y1) {
          return sign;
        } else {
          x1 = x2 - x1;
          y1 = y2 - y1;
          sign = -sign;
        }
      }
      if (y1 == 0.0) {
        if (x1 == 0.0) {
          return 0;
        } else {
          return sign;
        }
      }
      if (x1 == 0.0) {
        return -sign;
      }
    }
  }
}
