part of dart_shp;

class ShapefileWriter {
  FileWriter shpChannel;
  FileWriter shxChannel;
  List<Geometry> geometries;
  ShapeType geometryType;

  ShapefileWriter(
      this.geometries, this.geometryType, this.shpChannel, this.shxChannel);

  Future<void> write() async {
    var TYPE = geometryType;
    ShapeWriter? writer;
    if (TYPE == ShapeType.POLYGON) {
      writer = PolygonWriter(geometries, ShapeType.POLYGON);
      await writer.write(shpChannel, shxChannel);
    } else if (TYPE == ShapeType.ARC) {
      writer = LinestringWriter(geometries, ShapeType.ARC);
      await writer.write(shpChannel, shxChannel);
    } else if (TYPE == ShapeType.POINT) {
      writer = PointWriter(geometries, ShapeType.POINT);
      await writer.write(shpChannel, shxChannel);
    }
  }

  void close() {
    if (shpChannel.isOpen) {
      shpChannel.close();
    }

    if (shxChannel.isOpen) {
      shxChannel.close();
    }
  }
}

class PolygonWriter extends ShapeWriter {
  PolygonWriter(List<Geometry> geometries, ShapeType type)
      : super(geometries, type);

  @override
  void write(shpChannel, shxChannel, {verbose = false}) async {
    var shpI = 100;
    var shxI = 100;
    var shxOffset = 100;

    int parts = this.parts();
    int shpLength = 100 + (parts - geometries!.length) * 4 + this.shpLength();
    int shxLength = 100 + this.shxLength();
    var shpBuffer = Uint8List(shpLength);
    var shpView = ByteData.view(shpBuffer.buffer);
    var shxBuffer = Uint8List(shxLength);
    var shxView = ByteData.view(shxBuffer.buffer);

    if (verbose) {
      print('parts: $parts');
      print('geometries!.length: ${geometries!.length}');
      print('this.shpLength(): ${this.shpLength()}');
    }

    shpView.setInt32(0, 9994);
    shpView.setInt32(28, 1000, Endian.little);
    shpView.setInt32(32, type!.id, Endian.little);

    shxView.setInt32(0, 9994);
    shxView.setInt32(28, 1000, Endian.little);
    shxView.setInt32(32, type!.id, Endian.little);

    var extent = [999999999.0, 999999999.0, 0.0, 0.0]; // xmin, ymin, xmax, ymax
    for (var i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];

      // enlargeExtent
      if (extent[0] > geometry.getEnvelopeInternal().getMinX()) {
        extent[0] = geometry.getEnvelopeInternal().getMinX();
      }

      if (extent[1] > geometry.getEnvelopeInternal().getMinY()) {
        extent[1] = geometry.getEnvelopeInternal().getMinY();
      }

      if (extent[2] < geometry.getEnvelopeInternal().getMaxX()) {
        extent[2] = geometry.getEnvelopeInternal().getMaxX();
      }

      if (extent[3] < geometry.getEnvelopeInternal().getMaxY()) {
        extent[3] = geometry.getEnvelopeInternal().getMaxY();
      }

      var flattened = justCoords(geometry);

      var noParts = geometryParts(geometry);
      var headerLength = 8;
      var contentLength = (flattened!.length * 16) + 52 + noParts * 4;
      if (verbose) {
        print('noParts: ${noParts}');
        print('flattened: ${flattened.length}');
        print('extX: ${geometry.getEnvelopeInternal().getMinX()}');
        print('extY: ${geometry.getEnvelopeInternal().getMinY()}');
      }

      shxView.setInt32(shxI, (shxOffset / 2).toInt()); // offset
      shxView.setInt32(shxI + 4,
          ((contentLength - headerLength) / 2).toInt()); // offset length

      shxI += 8;
      shxOffset += contentLength;

      shpView.setInt32(shpI, i + 1); // record number
      shpView.setInt32(
          shpI + 4, ((contentLength - headerLength) / 2).toInt()); // length

      shpView.setInt32(shpI + 8, type!.id, Endian.little);

      // EXTENT
      shpView.setFloat64(
          shpI + 12, geometry.getEnvelopeInternal().getMinX(), Endian.little);
      shpView.setFloat64(
          shpI + 20, geometry.getEnvelopeInternal().getMinY(), Endian.little);
      shpView.setFloat64(
          shpI + 28, geometry.getEnvelopeInternal().getMaxX(), Endian.little);
      shpView.setFloat64(
          shpI + 36, geometry.getEnvelopeInternal().getMaxY(), Endian.little);

      shpView.setInt32(shpI + 44, noParts, Endian.little);
      shpView.setInt32(shpI + 48, flattened.length, Endian.little); // POINTS
      // shpView.setInt32(
      //     shpI + 52, 0, Endian.little); // The first part - index zero

      var partIdx = 0;
      var partStart = 0;
      var noGeom = geometry.getNumGeometries();

      for (var j = 0; j < noGeom; j++) {
        var geom = geometry.getGeometryN(j) as Polygon;

        shpView.setInt32(
            // set part index
            shpI + 52 + (partIdx * 4),
            partStart,
            Endian.little);

        partIdx++;
        partStart += geom.getExteriorRing().getNumPoints();

        for (var k = 0; k < geom.getNumInteriorRing(); k++) {
          shpView.setInt32(
              // set part index
              shpI + 52 + (partIdx * 4),
              partStart,
              Endian.little);

          partIdx++;
          partStart += geom.getInteriorRingN(k).getNumPoints();
        }
      }

      for (int j = 0; j < flattened.length; j++) {
        var coords = flattened[j];
        shpView.setFloat64(shpI + 52 + (j * 16) + partIdx * 4 + 0, coords.x,
            Endian.little); // X

        shpView.setFloat64(shpI + 52 + (j * 16) + partIdx * 4 + 8, coords.y,
            Endian.little); // Y
      }

      shpI += contentLength;
    }

    shpView.setInt32(24, (shpLength / 2).toInt());
    shxView.setInt32(24, (50 + geometries!.length * 4));

    shpView.setFloat64(36, extent[0], Endian.little);
    shpView.setFloat64(44, extent[1], Endian.little);
    shpView.setFloat64(52, extent[2], Endian.little);
    shpView.setFloat64(60, extent[3], Endian.little);

    shxView.setFloat64(36, extent[0], Endian.little);
    shxView.setFloat64(44, extent[1], Endian.little);
    shxView.setFloat64(52, extent[2], Endian.little);
    shxView.setFloat64(60, extent[3], Endian.little);

    await shpChannel.put(shpBuffer);
    await shxChannel.put(shxBuffer);
  }

  int parts() {
    int noParts = 0;
    for (int i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];
      noParts += geometryParts(geometry);
    }

    return noParts;
  }

  int geometryParts(Geometry geometry) {
    int noParts = 0;
    int noGeoms = geometry.getNumGeometries();
    for (int i = 0; i < noGeoms; i++) {
      var poly = geometry.getGeometryN(i) as Polygon;
      noParts += poly.getNumInteriorRing() + 1;
    }

    return noParts;
  }

  int shpLength() {
    var coordsCount = 0;

    for (var i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];

      int noGeoms = geometry.getNumGeometries();
      for (int j = 0; j < noGeoms; j++) {
        var poly = geometry.getGeometryN(j);
        coordsCount += poly.getNumPoints();
      }
    }
    return ((geometries!.length * 56) +
            // points
            (coordsCount * 16))
        .toInt();
  }

  int shxLength() {
    return geometries!.length * 8;
  }

  List<Coordinate>? justCoords(geometry) {
    List<Coordinate> coords = [];

    int noGeoms = geometry.getNumGeometries();
    for (int j = 0; j < noGeoms; j++) {
      var poly = geometry.getGeometryN(j) as Polygon;
      coords.addAll(poly.getExteriorRing().getCoordinates());

      var noParts = poly.getNumInteriorRing();
      for (int k = 0; k < noParts; k++) {
        coords.addAll(poly.getInteriorRingN(k).getCoordinates());
      }
    }

    return coords;
  }
}

class LinestringWriter extends ShapeWriter {
  LinestringWriter(List<Geometry> geometries, ShapeType type)
      : super(geometries, type);

  @override
  void write(shpChannel, shxChannel, {verbose = false}) async {
    var shpI = 100;
    var shxI = 100;
    var shxOffset = 100;

    int parts = this.parts();
    int shpLength = 100 + (parts - geometries!.length) * 4 + this.shpLength();
    int shxLength = 100 + this.shxLength();
    var shpBuffer = Uint8List(shpLength);
    var shpView = ByteData.view(shpBuffer.buffer);
    var shxBuffer = Uint8List(shxLength);
    var shxView = ByteData.view(shxBuffer.buffer);

    if (verbose) {
      print('parts: $parts');
      print('geometries!.length: ${geometries!.length}');
      print('this.shpLength(): ${this.shpLength()}');
    }

    shpView.setInt32(0, 9994);
    shpView.setInt32(28, 1000, Endian.little);
    shpView.setInt32(32, type!.id, Endian.little);

    shxView.setInt32(0, 9994);
    shxView.setInt32(28, 1000, Endian.little);
    shxView.setInt32(32, type!.id, Endian.little);

    var extent = [999999999.0, 999999999.0, 0.0, 0.0]; // xmin, ymin, xmax, ymax
    for (var i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];

      // enlargeExtent
      if (extent[0] > geometry.getEnvelopeInternal().getMinX()) {
        extent[0] = geometry.getEnvelopeInternal().getMinX();
      }

      if (extent[1] > geometry.getEnvelopeInternal().getMinY()) {
        extent[1] = geometry.getEnvelopeInternal().getMinY();
      }

      if (extent[2] < geometry.getEnvelopeInternal().getMaxX()) {
        extent[2] = geometry.getEnvelopeInternal().getMaxX();
      }

      if (extent[3] < geometry.getEnvelopeInternal().getMaxY()) {
        extent[3] = geometry.getEnvelopeInternal().getMaxY();
      }

      var flattened = justCoords(geometry);

      var noParts = geometry.getNumGeometries();
      var headerLength = 8;
      var contentLength = (flattened!.length * 16) + 52 + noParts * 4;
      if (verbose) {
        print('noParts: $noParts');
        print('flattened: ${flattened.length}');
        print('extX: ${geometry.getEnvelopeInternal().getMinX()}');
        print('extY: ${geometry.getEnvelopeInternal().getMinY()}');
      }

      shxView.setInt32(shxI, (shxOffset / 2).toInt()); // offset
      shxView.setInt32(shxI + 4,
          ((contentLength - headerLength) / 2).toInt()); // offset length

      shxI += 8;
      shxOffset += contentLength;

      shpView.setInt32(shpI, i + 1); // record number
      shpView.setInt32(
          shpI + 4, ((contentLength - headerLength) / 2).toInt()); // length

      shpView.setInt32(shpI + 8, type!.id, Endian.little);

      // EXTENT
      shpView.setFloat64(
          shpI + 12, geometry.getEnvelopeInternal().getMinX(), Endian.little);
      shpView.setFloat64(
          shpI + 20, geometry.getEnvelopeInternal().getMinY(), Endian.little);
      shpView.setFloat64(
          shpI + 28, geometry.getEnvelopeInternal().getMaxX(), Endian.little);
      shpView.setFloat64(
          shpI + 36, geometry.getEnvelopeInternal().getMaxY(), Endian.little);

      shpView.setInt32(shpI + 44, noParts, Endian.little);
      shpView.setInt32(shpI + 48, flattened.length, Endian.little); // POINTS
      // shpView.setInt32(
      //     shpI + 52, 0, Endian.little); // The first part - index zero

      var partIdx = 0;
      var partStart = 0;
      var noGeom = geometry.getNumGeometries();

      for (var j = 0; j < noGeom; j++) {
        var geom = geometry.getGeometryN(j) as LineString;

        shpView.setInt32(
            // set part index
            shpI + 52 + (partIdx * 4),
            partStart,
            Endian.little);

        partIdx++;
        partStart += geom.getNumPoints();
      }

      for (int j = 0; j < flattened.length; j++) {
        var coords = flattened[j];
        shpView.setFloat64(shpI + 52 + (j * 16) + partIdx * 4 + 0, coords.x,
            Endian.little); // X

        shpView.setFloat64(shpI + 52 + (j * 16) + partIdx * 4 + 8, coords.y,
            Endian.little); // Y
      }

      shpI += contentLength;
    }

    shpView.setInt32(24, (shpLength / 2).toInt());
    shxView.setInt32(24, (50 + geometries!.length * 4));

    shpView.setFloat64(36, extent[0], Endian.little);
    shpView.setFloat64(44, extent[1], Endian.little);
    shpView.setFloat64(52, extent[2], Endian.little);
    shpView.setFloat64(60, extent[3], Endian.little);

    shxView.setFloat64(36, extent[0], Endian.little);
    shxView.setFloat64(44, extent[1], Endian.little);
    shxView.setFloat64(52, extent[2], Endian.little);
    shxView.setFloat64(60, extent[3], Endian.little);

    await shpChannel.put(shpBuffer);
    await shxChannel.put(shxBuffer);
  }

  int parts() {
    int noParts = 0;
    for (int i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];
      noParts += geometry.getNumGeometries();
    }

    return noParts;
  }

  int shpLength() {
    var coordsCount = 0;

    for (var i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i];

      int noGeoms = geometry.getNumGeometries();
      for (int j = 0; j < noGeoms; j++) {
        var line = geometry.getGeometryN(j);
        coordsCount += line.getNumPoints();
      }
    }
    return ((geometries!.length * 56) +
            // points
            (coordsCount * 16))
        .toInt();
  }

  int shxLength() {
    return geometries!.length * 8;
  }

  List<Coordinate>? justCoords(geometry) {
    List<Coordinate> coords = [];

    int noGeoms = geometry.getNumGeometries();
    for (int j = 0; j < noGeoms; j++) {
      var line = geometry.getGeometryN(j) as LineString;
      coords.addAll(line.getCoordinates());
    }

    return coords;
  }
}

class PointWriter extends ShapeWriter {
  PointWriter(List<Geometry> geometries, ShapeType type)
      : super(geometries, type);

  @override
  write(shpChannel, shxChannel) async {
    var shpI = 100;
    var shxI = 100;
    var shxOffset = 100;

    var contentLength = 28; // 8 header, 20 content

    int shpLength = 100 + geometries!.length * 28;
    int shxLength = 100 + geometries!.length * 28;
    var shpBuffer = Uint8List(shpLength);
    var shpView = ByteData.view(shpBuffer.buffer);
    var shxBuffer = Uint8List(shxLength);
    var shxView = ByteData.view(shxBuffer.buffer);

    shpView.setInt32(0, 9994);
    shpView.setInt32(28, 1000, Endian.little);
    shpView.setInt32(32, type!.id, Endian.little);

    shxView.setInt32(0, 9994);
    shxView.setInt32(28, 1000, Endian.little);
    shxView.setInt32(32, type!.id, Endian.little);

    var extent = [999999999.0, 999999999.0, 0.0, 0.0]; // xmin, ymin, xmax, ymax
    for (var i = 0; i < geometries!.length; i++) {
      var geometry = geometries![i] as Point;

      // enlargeExtent
      if (extent[0] > geometry.getX()) {
        extent[0] = geometry.getX();
      }

      if (extent[1] > geometry.getY()) {
        extent[1] = geometry.getY();
      }

      if (extent[2] < geometry.getX()) {
        extent[2] = geometry.getX();
      }

      if (extent[3] < geometry.getY()) {
        extent[3] = geometry.getY();
      }

      // HEADER
      // 4 record number
      // 4 content length in 16-bit words (20/2)
      shpView.setInt32(shpI, i + 1);
      shpView.setInt32(shpI + 4, 10);

      // record
      // (8 + 8) + 4 = 20 content length
      shpView.setInt32(shpI + 8, 1, Endian.little); // POINT=1
      shpView.setFloat64(shpI + 12, geometry.getX(), Endian.little); // X
      shpView.setFloat64(shpI + 20, geometry.getY(), Endian.little); // Y

      // index
      shxView.setInt32(shxI, (shxOffset / 2).toInt()); // length in 16-bit words
      shxView.setInt32(shxI + 4, 10);

      shxI += 8;
      shpI += contentLength;
      shxOffset += contentLength;
    }

    shpView.setInt32(24, (shpLength / 2).toInt());
    shxView.setInt32(24, (50 + geometries!.length * 4));

    shpView.setFloat64(36, extent[0], Endian.little);
    shpView.setFloat64(44, extent[1], Endian.little);
    shpView.setFloat64(52, extent[2], Endian.little);
    shpView.setFloat64(60, extent[3], Endian.little);

    shxView.setFloat64(36, extent[0], Endian.little);
    shxView.setFloat64(44, extent[1], Endian.little);
    shxView.setFloat64(52, extent[2], Endian.little);
    shxView.setFloat64(60, extent[3], Endian.little);

    await shpChannel.put(shpBuffer);
    await shxChannel.put(shxBuffer);
  }
}

class ShapeWriter {
  List<Geometry>? geometries;
  ShapeType? type;

  ShapeWriter(List<Geometry> geometries, ShapeType type) {
    this.geometries = geometries;
    this.type = type;
  }

  write(shpChannel, shxChannel) async {}
}
