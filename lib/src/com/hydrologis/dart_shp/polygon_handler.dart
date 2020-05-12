part of dart_shp;

/// Wrapper for a Shapefile polygon.
///
/// @author aaime
/// @author Ian Schneider
/// @version $Id$
class PolygonHandler extends ShapeHandler {
  GeometryFactory geometryFactory;

  ShapeType shapeType;

  PolygonHandler(GeometryFactory gf) {
    shapeType = ShapeType.POLYGON;
    geometryFactory = gf;
  }

  PolygonHandler.withType(ShapeType type, GeometryFactory gf) {
    if (!type.isPolygonType()) {
      throw ShapefileException(
          "PolygonHandler constructor - expected type to be 5, 15, or 25.");
    }

    shapeType = type;
    geometryFactory = gf;
  }

  // returns true if testPoint is a point in the pointList list.
  bool pointInList(Coordinate testPoint, List<Coordinate> pointList) {
    Coordinate p;

    for (int t = pointList.length - 1; t >= 0; t--) {
      p = pointList[t];

      // nan test; x!=x iff x is nan
      if ((testPoint.x == p.x) &&
          (testPoint.y == p.y) &&
          ((testPoint.getZ() == p.getZ()) || testPoint.getZ().isNaN)) {
        return true;
      }
    }

    return false;
  }

  @override
  ShapeType getShapeType() {
    return shapeType;
  }

  @override
  int getLength(dynamic geometry) {
    MultiPolygon multi;

    if (geometry is MultiPolygon) {
      multi = geometry;
    } else {
      multi = geometryFactory.createMultiPolygon([geometry as Polygon]);
    }

    int nrings = 0;

    for (int t = 0; t < multi.getNumGeometries(); t++) {
      Polygon p = multi.getGeometryN(t);
      nrings = nrings + 1 + p.getNumInteriorRing();
    }

    int npoints = multi.getNumPoints();
    int length;

    if (shapeType == ShapeType.POLYGONZ) {
      length = 44 +
          (4 * nrings) +
          (16 * npoints) +
          (8 * npoints) +
          16 +
          (8 * npoints) +
          16;
    } else if (shapeType == ShapeType.POLYGONM) {
      length = 44 + (4 * nrings) + (16 * npoints) + (8 * npoints) + 16;
    } else if (shapeType == ShapeType.POLYGON) {
      length = 44 + (4 * nrings) + (16 * npoints);
    } else {
      throw StateError("Expected ShapeType of Polygon, got $shapeType");
    }
    return length;
  }

  @override
  dynamic read(LByteBuffer buffer, ShapeType type, bool flatFeature) {
    if (type == ShapeType.NULL) {
      return createNull();
    }
    // bounds
    buffer.position = buffer.position + 4 * 8;

    List<int> partOffsets;

    int numParts = buffer.getInt32();
    int numPoints = buffer.getInt32();
    int dimensions = (shapeType == ShapeType.POLYGONZ) && !flatFeature ? 3 : 2;

    partOffsets = List(numParts);

    for (int i = 0; i < numParts; i++) {
      partOffsets[i] = buffer.getInt32();
    }

    List<LinearRing> shells = [];
    List<LinearRing> holes = [];
    CoordinateSequence coords = readCoordinates(buffer, numPoints, dimensions);

    int offset = 0;
    int start;
    int finish;
    int length;

    for (int part = 0; part < numParts; part++) {
      start = partOffsets[part];

      if (part == (numParts - 1)) {
        finish = numPoints;
      } else {
        finish = partOffsets[part + 1];
      }

      length = finish - start;
      int close = 0; // '1' if the ring must be closed, '0' otherwise
      if ((coords.getOrdinate(start, CoordinateSequence.X) !=
              coords.getOrdinate(finish - 1, CoordinateSequence.X)) ||
          (coords.getOrdinate(start, CoordinateSequence.Y) !=
              coords.getOrdinate(finish - 1, CoordinateSequence.Y))) {
        close = 1;
      }
      if (dimensions == 3 && !coords.hasM()) {
        if (coords.getOrdinate(start, CoordinateSequence.Z) !=
            coords.getOrdinate(finish - 1, CoordinateSequence.Z)) {
          close = 1;
        }
      }

      CoordinateSequence csRing;
      if (coords.hasZ()) {
        csRing = Shapeutils.createCSMeas(
            geometryFactory.getCoordinateSequenceFactory(),
            length + close,
            4,
            1);
      } else if (coords.hasM()) {
        csRing = Shapeutils.createCSMeas(
            geometryFactory.getCoordinateSequenceFactory(),
            length + close,
            3,
            1);
      } else {
        csRing = Shapeutils.createCS(
            geometryFactory.getCoordinateSequenceFactory(), length + close, 2);
      }

      // double area = 0;
      // int sx = offset;
      for (int i = 0; i < length; i++) {
        csRing.setOrdinate(i, CoordinateSequence.X,
            coords.getOrdinate(offset, CoordinateSequence.X));
        csRing.setOrdinate(i, CoordinateSequence.Y,
            coords.getOrdinate(offset, CoordinateSequence.Y));
        if (coords.hasZ()) {
          csRing.setOrdinate(i, CoordinateSequence.Z,
              coords.getOrdinate(offset, CoordinateSequence.Z));
        }
        if (coords.hasM()) {
          csRing.setOrdinate(i, CoordinateSequence.M,
              coords.getOrdinate(offset, CoordinateSequence.M));
        }
        offset++;
      }
      if (close == 1) {
        csRing.setOrdinate(length, CoordinateSequence.X,
            coords.getOrdinate(start, CoordinateSequence.X));
        csRing.setOrdinate(length, CoordinateSequence.Y,
            coords.getOrdinate(start, CoordinateSequence.Y));
        if (coords.hasZ()) {
          csRing.setOrdinate(length, CoordinateSequence.Z,
              coords.getOrdinate(start, CoordinateSequence.Z));
        }
        if (coords.hasM()) {
          csRing.setOrdinate(length, CoordinateSequence.M,
              coords.getOrdinate(start, CoordinateSequence.M));
        }
      }
      // REVISIT: polygons with only 1 or 2 points are not polygons -
      // geometryFactory will bomb so we skip if we find one.
      if (csRing.size() == 0 || csRing.size() > 3) {
        LinearRing ring = geometryFactory.createLinearRingSeq(csRing);

        if (Shapeutils.isCCW(csRing)) {
          // counter-clockwise
          holes.add(ring);
        } else {
          // clockwise
          shells.add(ring);
        }
      }
    }

    // quick optimization: if there's only one shell no need to check
    // for holes inclusion
    if (shells.length == 1) {
      return createMultiWithHoles(shells[0], holes);
    }
    // if for some reason, there is only one hole, we just reverse it and
    // carry on.
    else if (holes.length == 1 && shells.isEmpty) {
      return createMulti(holes[0]);
    } else {
      // build an association between shells and holes
      final List<List<LinearRing>> holesForShells =
          assignHolesToShells(shells, holes);

      Geometry g = buildGeometries(shells, holes, holesForShells);

      return g;
    }
  }

  CoordinateSequence readCoordinates(
      final LByteBuffer buffer, final int numPoints, final int dimensions) {
    CoordinateSequence cs;
    if (shapeType == ShapeType.POLYGONM) {
      cs = Shapeutils.createCSMeas(
          geometryFactory.getCoordinateSequenceFactory(), numPoints, 3, 1);
    } else if (shapeType == ShapeType.POLYGONZ) {
      cs = Shapeutils.createCSMeas(
          geometryFactory.getCoordinateSequenceFactory(), numPoints, 4, 1);
    } else {
      cs = Shapeutils.createCS(geometryFactory.getCoordinateSequenceFactory(),
          numPoints, dimensions);
    }
    // DoubleBuffer dbuffer = buffer.asDoubleBuffer();
    List<double> ordinates = List(numPoints * 2);
    for (var i = 0; i < ordinates.length; i++) {
      ordinates[i] = buffer.getDouble64();
    }
    // dbuffer.get(ordinates);
    for (int t = 0; t < numPoints; t++) {
      cs.setOrdinate(t, CoordinateSequence.X, ordinates[t * 2]);
      cs.setOrdinate(t, CoordinateSequence.Y, ordinates[t * 2 + 1]);
    }

    if (shapeType == ShapeType.POLYGONZ) {
      // Handle Z
      buffer.position = buffer.position + 2 * 8;
      // dbuffer.position(dbuffer.position() + 2);
      for (var i = 0; i < numPoints; i++) {
        ordinates[i] = buffer.getDouble64();
      }
      // dbuffer.get(ordinates, 0, numPoints);

      for (int t = 0; t < numPoints; t++) {
        cs.setOrdinate(t, CoordinateSequence.Z, ordinates[t]);
      }
    }
    if (shapeType == ShapeType.POLYGONM || shapeType == ShapeType.POLYGONZ) {
      // Handle M
      buffer.position = buffer.position + 2 * 8;
      // dbuffer.position(dbuffer.position() + 2);
      for (var i = 0; i < numPoints; i++) {
        ordinates[i] = buffer.getDouble64();
      }
      // dbuffer.get(ordinates, 0, numPoints);

      for (int t = 0; t < numPoints; t++) {
        cs.setOrdinate(t, CoordinateSequence.M, ordinates[t]);
      }
    }

    return cs;
  }

  Geometry buildGeometries(
      final List<LinearRing> shells,
      final List<LinearRing> holes,
      final List<List<LinearRing>> holesForShells) {
    List<Polygon> polygons;

    // if we have shells, lets use them
    if (shells.isNotEmpty) {
      polygons = List(shells.length);
      // oh, this is a bad record with only holes
    } else {
      polygons = List(holes.length);
    }

    // this will do nothing for the "only holes case"
    for (int i = 0; i < shells.length; i++) {
      LinearRing shell = shells[i];
      List<LinearRing> holesForShell = holesForShells[i];
      polygons[i] = geometryFactory.createPolygon(shell, holesForShell);
    }

    // this will take care of the "only holes case"
    // we just reverse each hole
    if (shells.isEmpty) {
      for (int i = 0, ii = holes.length; i < ii; i++) {
        LinearRing hole = holes[i];
        polygons[i] = geometryFactory.createPolygon(hole, null);
      }
    }

    Geometry g = geometryFactory.createMultiPolygon(polygons);

    return g;
  }

  List<List<LinearRing>> assignHolesToShells(
      final List<LinearRing> shells, final List<LinearRing> holes) {
    List<List<LinearRing>> holesForShells = List(shells.length);
    for (int i = 0; i < shells.length; i++) {
      holesForShells.add([]);
    }

    // find homes
    for (int i = 0; i < holes.length; i++) {
      LinearRing testRing = holes[i];
      LinearRing minShell;
      Envelope minEnv;
      Envelope testEnv = testRing.getEnvelopeInternal();
      Coordinate testPt = testRing.getCoordinateN(0);
      LinearRing tryRing;

      for (int j = 0; j < shells.length; j++) {
        tryRing = shells[j];

        Envelope tryEnv = tryRing.getEnvelopeInternal();
        if (minShell != null) {
          minEnv = minShell.getEnvelopeInternal();
        }

        bool isContained = false;
        List<Coordinate> coordList = tryRing.getCoordinates();

        if (tryEnv.containsEnvelope(testEnv) &&
            (RayCrossingCounter.locatePointInRingList(testPt, coordList) != 2 ||
                (pointInList(testPt, coordList)))) {
          isContained = true;
        }

        // check if this new containing ring is smaller than the current
        // minimum ring
        if (isContained) {
          if ((minShell == null) || minEnv.containsEnvelope(tryEnv)) {
            minShell = tryRing;
          }
        }
      }

      if (minShell == null) {
        // now reverse this bad "hole" and turn it into a shell
        shells.add(testRing);
        holesForShells.add([]);
      } else {
        holesForShells[shells.indexOf(minShell)].add(testRing);
      }
    }

    return holesForShells;
  }

  MultiPolygon createMulti(LinearRing single) {
    return createMultiWithHoles(single, []);
  }

  MultiPolygon createMultiWithHoles(LinearRing single, List<LinearRing> holes) {
    return geometryFactory.createMultiPolygon(
        <Polygon>[geometryFactory.createPolygon(single, holes)]);
  }

  MultiPolygon createNull() {
    return geometryFactory.createMultiPolygon(null);
  }

  @override
  void write(LByteBuffer buffer, Object geometry) {
    MultiPolygon multi;

    if (geometry is MultiPolygon) {
      multi = geometry;
    } else {
      multi = geometryFactory.createMultiPolygon(<Polygon>[geometry]);
    }

    Envelope box = multi.getEnvelopeInternal();
    buffer.putDouble64(box.getMinX());
    buffer.putDouble64(box.getMinY());
    buffer.putDouble64(box.getMaxX());
    buffer.putDouble64(box.getMaxY());

    // need to find the total number of rings and points
    List<CoordinateSequence> coordinates = [];
    for (int t = 0; t < multi.getNumGeometries(); t++) {
      Polygon p = multi.getGeometryN(t);
      coordinates.add(p.getExteriorRing().getCoordinateSequence());
      for (int ringN = 0; ringN < p.getNumInteriorRing(); ringN++) {
        coordinates.add(p.getInteriorRingN(ringN).getCoordinateSequence());
      }
    }
    int nrings = coordinates.length;

    final int npoints = multi.getNumPoints();

    buffer.putInt32(nrings);
    buffer.putInt32(npoints);

    int count = 0;
    for (int t = 0; t < nrings; t++) {
      buffer.putInt32(count);
      count = count + coordinates[t].size();
    }

    final List<double> zExtreame = [double.nan, double.nan];

    // write out points here!.. and gather up min and max z values
    for (int ringN = 0; ringN < nrings; ringN++) {
      CoordinateSequence coords = coordinates[ringN];

      Shapeutils.zMinMax(coords, zExtreame);

      final int seqSize = coords.size();
      for (int coordN = 0; coordN < seqSize; coordN++) {
        buffer.putDouble64(coords.getOrdinate(coordN, 0));
        buffer.putDouble64(coords.getOrdinate(coordN, 1));
      }
    }

    if (shapeType == ShapeType.POLYGONZ) {
      // z
      if (zExtreame[0].isNaN) {
        buffer.putDouble64(0.0);
        buffer.putDouble64(0.0);
      } else {
        buffer.putDouble64(zExtreame[0]);
        buffer.putDouble64(zExtreame[1]);
      }

      for (int ringN = 0; ringN < nrings; ringN++) {
        CoordinateSequence coords = coordinates[ringN];

        final int seqSize = coords.size();
        double z;
        for (int coordN = 0; coordN < seqSize; coordN++) {
          z = coords.getOrdinate(coordN, 2);
          if (z.isNaN) {
            buffer.putDouble64(0.0);
          } else {
            buffer.putDouble64(z);
          }
        }
      }
    }

    if (shapeType == ShapeType.POLYGONM || shapeType == ShapeType.POLYGONZ) {
      // obtain all M values
      List<double> values = [];
      for (int ringN = 0; ringN < nrings; ringN++) {
        CoordinateSequence coords = coordinates[ringN];
        final int seqSize = coords.size();
        double m;
        for (int coordN = 0; coordN < seqSize; coordN++) {
          m = coords.getM(coordN);
          values.add(m);
        }
      }

      // m min
      double edge =
          values.reduce(math.min); //    stream().min(Double::compare).get();
      buffer.putDouble64(!edge.isNaN ? edge : -10E40);
      // m max
      edge = values.reduce(math.max); //  stream().max(Double::compare).get();
      buffer.putDouble64(!edge.isNaN ? edge : -10E40);

      // m values
      values.forEach((x) {
        buffer.putDouble64(x.isNaN ? -10E40 : x);
      });
    }
  }
}
