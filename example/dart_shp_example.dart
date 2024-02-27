import 'package:dart_shp/dart_shp.dart';
import 'package:dart_jts/dart_jts.dart';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'dart:io';
import 'dart:math';

void main() {
  // Generate some random lat, lon points
  final random = Random();
  final randomLats =
      List.generate(5, (index) => (random.nextDouble() * 180.0) - 90.0);
  final randomLons =
      List.generate(5, (index) => (random.nextDouble() * 360.0) - 180.0);

  // Generate the list of coordinates for the random lat lon lists
  final coordinates = List.generate(
      5, (index) => Coordinate.fromYX(randomLats[index], randomLons[index]));

  // Initialize a Geometry Factory
  final geometryFactory = GeometryFactory.defaultPrecision();

  // Convert the coordinates into points
  final points =
      coordinates.map((e) => geometryFactory.createPoint(e)).toList();

  // Initialize the writer and write the points file
  final writer = PointWriter(points, ShapeType.POINT);

  writer.write(FileWriter(File('path/to/shp/file.shp')),
      FileWriter(File('path/to/shx/file.shx')));
}

void mainPolygon() {
  // Generate 3 random points, which guarantees as a simple/non-intersceting polygon.
  final random = Random();
  final randomLats =
      List.generate(3, (index) => (random.nextDouble() * 180.0) - 90.0);
  final randomLons =
      List.generate(3, (index) => (random.nextDouble() * 360.0) - 180.0);

  // Generate the list of coordinates for the random lat lon lists
  final coordinates = List.generate(
      3, (index) => Coordinate.fromYX(randomLats[index], randomLons[index]));

  // Close the polygon, ensure the final point is the same as the first point
  coordinates.add(coordinates.first);

  // Initialize a Geometry Factory
  final geometryFactory = GeometryFactory.defaultPrecision();

  // Convert the coordinates into points
  final poly = geometryFactory.createPolygonFromCoords(coordinates);

  // Initialize the writer and write the single polygon to file
  final writer = PolyWriter([poly], ShapeType.POLYGON);

  writer.write(FileWriter(File('path/to/shp/file.shp')),
      FileWriter(File('path/to/shx/file.shx')));
}
