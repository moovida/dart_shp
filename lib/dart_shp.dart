library dart_shp;

import 'dart:typed_data';
import 'dart:io';
import 'dart:convert' as conv;
import 'package:characters/characters.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:logger/logger.dart';
import 'package:chunked_stream/chunked_stream.dart';
import 'package:timezone/timezone.dart';

part 'src/com/hydrologis/dart_shp/dbase_reader.dart';
part 'src/com/hydrologis/dart_shp/utils.dart';
part 'src/com/hydrologis/dart_shp/shapetype.dart';

