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
      writer = PolyWriter(geometries);
      await writer.write(shpChannel, shxChannel);
    } else if (TYPE == ShapeType.ARC) {
      writer = PolyWriter(geometries);
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

class PolyWriter extends ShapeWriter {
  PolyWriter(List<Geometry> geometries) : super(geometries);

  @override
  write(shpChannel, shxChannel) async {
    var shpI = 100;
    var shxI = 100;
    var shxOffset = 100;

    int parts = this.parts();
    int shpLength =
        100 + (parts - geometries!.length) * 4 + this.shpLength();
    int shxLength = 100 + this.shxLength();
    var shpBuffer = Uint8List(shpLength);
    var shpView = ByteData.view(shpBuffer.buffer);
    var shxBuffer = Uint8List(shxLength);
    var shxView = ByteData.view(shxBuffer.buffer);

    print('parts: $parts');
    print('geometries!.length: ${geometries!.length}');
    print('this.shpLength(): ${this.shpLength()}');

    shpView.setInt32(0, 9994);
    shpView.setInt32(28, 1000, Endian.little);
    shpView.setInt32(32, ShapeType.POLYGON.id, Endian.little);

    shxView.setInt32(0, 9994);
    shxView.setInt32(28, 1000, Endian.little);
    shxView.setInt32(32, ShapeType.POLYGON.id, Endian.little);

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

      print('noParts: ${noParts}');
      print('flattened: ${flattened.length}');
      print('extX: ${geometry.getEnvelopeInternal().getMinX()}');
      print('extY: ${geometry.getEnvelopeInternal().getMinY()}');

      shxView.setInt32(shxI, (shxOffset / 2).toInt()); // offset
      shxView.setInt32(shxI + 4, ((contentLength - headerLength) / 2).toInt()); // offset length

      shxI += 8;
      shxOffset += contentLength;

      shpView.setInt32(shpI, i + 1); // record number
      shpView.setInt32(shpI + 4, ((contentLength - headerLength) / 2).toInt()); // length

      shpView.setInt32(
          shpI + 8, ShapeType.POLYGON.id, Endian.little);

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

  @override
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

  @override
  int shxLength() {
    return geometries!.length * 8;
  }

  @override
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

class ShapeWriter {
  List<Geometry>? geometries;

  ShapeWriter(List<Geometry> geometries) {
    this.geometries = geometries;
  }

  List<Coordinate>? justCoords(geometry) {
    return null;
  }

  int shpLength() {
    return 0;
  }

  int shxLength() {
    return 0;
  }

  write(shpChannel, shxChannel) async {}
}
