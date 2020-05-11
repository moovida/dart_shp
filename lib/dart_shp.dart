library dart_shp;

import 'dart:html';
import 'dart:typed_data';
import 'dart:io';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:intl/intl.dart';
import 'dart:convert' as conv;
import 'dart:math' as math;
import 'package:characters/characters.dart';
import 'package:dart_jts/dart_jts.dart' hide Type;
import 'package:timezone/data/latest.dart' as tz;
import 'package:logger/logger.dart';
import 'package:chunked_stream/chunked_stream.dart';
import 'package:timezone/timezone.dart';

part 'src/com/hydrologis/dart_shp/dbase_reader.dart';
part 'src/com/hydrologis/dart_shp/dbase_header.dart';
part 'src/com/hydrologis/dart_shp/dbase_writer.dart';
part 'src/com/hydrologis/dart_shp/utils.dart';
part 'src/com/hydrologis/dart_shp/shapeutils.dart';
part 'src/com/hydrologis/dart_shp/shapefile_header.dart';
part 'src/com/hydrologis/dart_shp/shapefile_reader.dart';
part 'src/com/hydrologis/dart_shp/index_reader.dart';

