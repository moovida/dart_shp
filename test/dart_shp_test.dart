import 'dart:io';
import 'dart:math' as math;

import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:dart_jts/dart_jts.dart';
import 'package:dart_shp/dart_shp.dart';
import 'package:test/test.dart';

import 'testing_utilities.dart';

void main() async {
  File statesDbf;
  File nullsDbf;
  File pointTestShp;
  File danishShp;
  File rusShp;
  File chineseShp;
  File polygontestShp;
  FieldFormatter victim;
  setUpAll(() async {
    statesDbf = File('./test/shapes/statepop.dbf');
    nullsDbf = File('./test/shapes/nulls.dbf');
    pointTestShp = File('./test/shapes/pointtest.shp');
    danishShp = File('./test/shapes/danish_point.shp');
    rusShp = File('./test/shapes/rus-windows-1251.shp');
    chineseShp = File('./test/shapes/chinese_poly.shp');
    polygontestShp = File('./test/shapes/polygontest.shp');
    victim = FieldFormatter(Charset(), TimeZones.getDefault(), false);
  });

  tearDownAll(() {});

  group('DbaseFileTests - ', () {
    test('testNumberOfColsLoaded', () async {
      var dbf = await openDbf(statesDbf);

      var header = dbf.getHeader();
      var numFields = header.getNumFields();
      expect(numFields, 252);

      dbf?.close();
    });
    test('testNumberOfRowsLoaded', () async {
      var dbf = await openDbf(statesDbf);

      var header = dbf.getHeader();
      var numRows = header.getNumRecords();
      expect(numRows, 49);

      dbf?.close();
    });
    test('testDataLoaded', () async {
      var dbf = await openDbf(statesDbf);

      List<dynamic> attrs =
          await dbf.readEntryInto(List(dbf.getHeader().getNumFields()));
      expect(attrs[0], 'Illinois');
      expect(attrs[4] as double, 143986.61);

      dbf?.close();
    });
    test('testRowVsEntry', () async {
      var dbf = await openDbf(statesDbf);
      var dbf2 = await openDbf(statesDbf);

      while (dbf.hasNext()) {
        List<dynamic> attrs =
            await dbf.readEntryInto(List(dbf.getHeader().getNumFields()));
        Row r = await dbf2.readRow();
        for (int i = 0, ii = attrs.length; i < ii; i++) {
          var attr1 = attrs[i];
          var attr2 = await r.read(i);
          assertNotNull(attr1);
          assertNotNull(attr2);
          assertEquals(attr1, attr2);
        }
      }

      dbf?.close();
    });
    test('testHeader', () async {
      DbaseFileHeader header = DbaseFileHeader();

      header.addColumn('emptyString', 'C', 20, 0);
      header.addColumn('emptyInt', 'N', 20, 0);
      header.addColumn('emptyDouble', 'N', 20, 5);
      header.addColumn('emptyFloat', 'F', 20, 5);
      header.addColumn('emptyLogical', 'L', 1, 0);
      header.addColumn('emptyDate', 'D', 20, 0);
      int length = header.getRecordLength();
      header.removeColumn('emptyDate');
      assertTrue(length != header.getRecordLength());
      header.addColumn('emptyDate', 'D', 20, 0);
      assertTrue(length == header.getRecordLength());
      header.removeColumn('billy');
      assertTrue(length == header.getRecordLength());
    });
    test('testAddColumn', () async {
      DbaseFileHeader header = DbaseFileHeader();

      header.addColumn('emptyInt', 'N', 9, 0);
      assertEquals(header.getFieldClass(0), int);
      assertEquals(header.getFieldLength(0), 9);

      header.addColumn('emptyString', 'C', 20, 0);
      assertEquals(header.getFieldClass(1), String);
      assertEquals(header.getFieldLength(1), 20);
    });
    test('testEmptyFields', () async {
      var temp = FileUtilities.getTmpFile('dbf');

      try {
        DbaseFileHeader header = DbaseFileHeader();
        header.addColumn('emptyString', 'C', 20, 0);
        header.addColumn('emptyInt', 'N', 20, 0);
        header.addColumn('emptyDouble', 'N', 20, 5);
        header.addColumn('emptyFloat', 'F', 20, 5);
        header.addColumn('emptyLogical', 'L', 1, 0);
        header.addColumn('emptyDate', 'D', 20, 0);
        header.setNumRecords(20);

        var fileWriter = FileWriter(temp);
        DbaseFileWriter dbf = DbaseFileWriter(header, fileWriter, Charset());
        await dbf.open();
        for (int i = 0; i < header.getNumRecords(); i++) {
          await dbf.writeRecord(List<dynamic>(6));
        }
        dbf.close();

        DbaseFileReader r = DbaseFileReader(FileReaderRandom(temp));
        await r.open();

        int cnt = 0;
        var header2 = r.getHeader();
        while (r.hasNext()) {
          cnt++;
          var o = await r.readEntry();
          var numFields = header2.getNumFields();
          assertTrue(o.length == numFields);
        }
        assertEquals(cnt, 20);
      } finally {
        if (temp.existsSync()) {
          temp.deleteSync();
        }
      }
    });
    test('testFieldFormatter', () async {
      Charset cs = Charset();
      await cs.setCharsetEncoding(UTF16); // use dart internal
      FieldFormatter formatter =
          FieldFormatter(cs, TimeZones.getDefault(), false);

      var stringWithInternationChars = 'hello ' '\u20ac';
      var format =
          await formatter.getFieldString(10, stringWithInternationChars);
      assertEquals('          '.codeUnits.length, format.codeUnits.length);

      // test when the string is too big.
      stringWithInternationChars = '\u20ac' '1234567890';
      format = await formatter.getFieldString(10, stringWithInternationChars);

      assertEquals('          '.codeUnits.length, format.codeUnits.length);
    });
    test('testNulls', () async {
      Charset cs = Charset();

      TimeZones tz = TimeZones.getTimeZone("UTC");
      List<String> types = ['C', 'N', 'F', 'L', 'D'];
      List<int> sizes = [5, 9, 20, 1, 8];
      List<int> decimals = [0, 0, 31, 0, 0];
      List<dynamic> values = [
        "ABCDE",
        2 << 20,
        (2 << 10) + 1.0 / (2 << 4),
        true,
        TimeUtilities.ISO8601_TS_DAY_FORMATTER.parseUTC("2010-04-01")
      ];

      var temp = FileUtilities.getTmpFile('dbf');

      DbaseFileHeader header = DbaseFileHeader();
      for (int i = 0; i < types.length; i++) {
        header.addColumn("" + types[i], types[i], sizes[i], decimals[i]);
      }
      header.setNumRecords(values.length);
      var fw = FileWriter(temp);

      DbaseFileWriter writer = DbaseFileWriter(header, fw, cs, tz);
      try {
        await writer.open();
        // write records such that the i-th row has nulls in every column except the i-th column
        for (int row = 0; row < values.length; row++) {
          List<dynamic> current = List.filled(values.length, null);
          current[row] = values[row];
          await writer.writeRecord(current);
        }
      } finally {
        writer.close();
      }

      var fr = FileReaderRandom(temp);

      DbaseFileReader reader = DbaseFileReader(fr, cs, tz);
      try {
        await reader.open();
        assertTrue(values.length == reader.getHeader().getNumRecords());
        for (int row = 0; row < values.length; row++) {
          List<dynamic> current = await reader.readEntry();
          assertTrue(current != null && current.length == values.length);
          for (int column = 0; column < values.length; column++) {
            if (column == row) {
              assertTrue(current[column] != null);
              assertTrueMsg(
                  "Non-null column value " +
                      current[column].toString() +
                      " did not match original value " +
                      values[column].toString(),
                  current[column] == values[column]);
            } else {
              assertTrue(current[column] == null);
            }
          }
        }
      } finally {
        reader.close();
      }
    });

    test('testNull2', () async {
      /*
       The nulls.dbf file contains 2 columns: gistool_id (integer) and att_loss (real).
       There are 4 records:
       GISTOOL_ID | ATT_LOSS
       -----------+---------
         98245    | <all spaces>
         98289    | ****************** (= all stars)
         98538    | 0.000000000
         98586    | 5.210000000
    */
      var dbfReader = await openDbf(nullsDbf);

      var records = <int, double>{};
      while (dbfReader.hasNext()) {
        final List<dynamic> fields = await dbfReader.readEntry();
        records[fields[0]] = fields[1];
      }
      dbfReader.close();

      assertEqualsD(records[98586], 5.21, 0.00000001);
      assertEqualsD(records[98538], 0.0, 0.00000001);
      assertIsNull(records[98289]);
      assertIsNull(records[98245]);
    });

    test('testNaN', () async {
      checkOutput(victim, double.nan, 33, 31);
    });
    test('testNegative', () async {
      checkOutput(victim, -1.0e16, 33, 31);
    });
    test('testSmall', () async {
      checkOutput(victim, 42.123, 33, 31);
    });
    test('testLarge', () async {
      checkOutput(victim, 12345.678, 33, 31);
    });
  });

  group('ShapefileFileTests - ', () {
    test('testPoints', () async {
      var reader = ShapefileFeatureReader(pointTestShp);
      await reader.open();
      var id2Coor = {
        0: Coordinate(0.098, 0.600),
        1: Coordinate(0.018, 0.872),
        2: Coordinate(0.514, 0.352),
        3: Coordinate(0.218, 0.476),
        4: Coordinate(0.570, 0.744),
        5: Coordinate(0.666, 0.644),
      };
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        var id = feature.attributes["ID"];
        var coord = id2Coor[id];
        if (coord != null) {
          var fCoord = feature.geometry.getCoordinate();
          assertEqualsD(fCoord.distance(coord), 0, 0.00000001);
        }
      }

      reader?.close();
    });

    test('testPolygonTest', () async {
      var reader = ShapefileFeatureReader(polygontestShp);
      await reader.open();
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        var id = feature.attributes["ID"];
        var geometry = feature.geometry;
        var area = geometry.getArea();
        if (id == 1) {
          assertEqualsD(area, 0.167, 0.001, "${area} is not 0.167");
          assertEquals(geometry.getCoordinates().length, 7);
        } else if (id == 2) {
          assertEqualsD(area, 0.261, 0.001, "${area} is not 0.261");
          assertEquals(geometry.getCoordinates().length, 9);
        }
      }

      reader?.close();
    });
    test('testCountries', () async {
      var countries = File('./test/shapes/ne/countries.shp');
      var reader = ShapefileFeatureReader(countries);
      await reader.open();
      List<Feature> features = [];
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        features.add(feature);
      }

      assertEquals(features.length, 1);

      var f = features[0];
      var geomNum = f.geometry.getNumGeometries();
      assertEquals(geomNum, 29);

      assertEquals(f.attributes["SOVEREIGNT"], "Italy");
      assertEquals(f.attributes["ADMIN"], "Italy");
      assertEquals(f.attributes["POP_EST"], 58126212);

      reader?.close();
    });
    test('testProvinces', () async {
      var file = File('./test/shapes/ne/provinces.shp');
      var reader = ShapefileFeatureReader(file);
      await reader.open();
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        if (feature.attributes["adm1_code"] == "ITA-5459") {
          assertEquals(feature.attributes["name"], "Bozen");
          assertEquals(feature.attributes["name_local"], "");

          assertEqualsD(feature.geometry.getArea(), 0.869, 0.001);
          break;
        }
      }

      reader?.close();
    });
    test('testPois', () async {
      var file = File('./test/shapes/ne/poi.shp');
      var reader = ShapefileFeatureReader(file);
      await reader.open();
      var list = [];
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        if (feature.attributes["NAME"] == "Ancona") {
          assertEquals(feature.attributes["ADM1NAME"], "Marche");
          assertEquals(feature.attributes["RANK_MIN"], 8);
          assertEquals(feature.attributes["POP_MAX"], 100507);
        }
        list.add(feature);
      }

      assertEquals(list.length, 58);

      reader?.close();
    });
    test('testRoads', () async {
      var file = File('./test/shapes/ne/roads.shp');
      var reader = ShapefileFeatureReader(file);
      await reader.open();
      var list = [];
      var lSum = 0.0;
      var kmSum = 0.0;
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        lSum += feature.geometry.getLength();
        kmSum += feature.attributes["length_km"];
        list.add(feature);
      }

      assertEqualsD(lSum, 289.7497347181333, 0.001);
      assertEquals(kmSum, 29167);

      assertEquals(list.length, 564);

      reader?.close();
    });
    test('testArabic', () async {
      var file = File('./test/shapes/test_arabic.shp');
      Charset cs = Charset(); // use utf8, known to be the charset of the shp
      var reader = ShapefileFeatureReader(file, charset: cs);
      await reader.open();
      if (await reader.hasNext()) {
        Feature feature = await reader.next();
        var distance = feature.geometry.distance(
            GeometryFactory.defaultPrecision()
                .createPoint(Coordinate(31.230342, 29.91187)));
        assertEqualsD(distance, 0, 0.0000001, "$distance is not zero");

        var actType = "البنية الأساسية الريفية والري";
        var actTypeActual = feature.attributes["ACT_TYPE"];
        assertEquals(actTypeActual, actType);
        var devType = "إعادة التأهيل";
        var devTypeActual = feature.attributes["DEV_TYPE"];
        assertEquals(devTypeActual, devType);
      }
      reader?.close();
    });
    test('testDanishPoints UTF16', () async {
      Charset cs = Charset();
      await cs.setCharsetEncoding(UTF16); // use dart internal
      var reader = ShapefileFeatureReader(danishShp, charset: cs);
      await reader.open();
      var id2Coor = {
        1: [Coordinate(714477, 6171916), "Charløtte"],
        2: [Coordinate(715676, 6172305), "Noah"],
        3: [Coordinate(714579, 6171156), "Laura"],
        4: [Coordinate(715085, 6169602), "Lukas"],
      };
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        var id = feature.attributes["ID"];
        var list = id2Coor[id];
        if (list != null) {
          var fCoord = feature.geometry.getCoordinate();
          var coord = list[0];
          assertEqualsD(
              fCoord.distance(coord), 0, 1, "fCoord: $fCoord -> coord: $coord");

          var fname = feature.attributes["TEKST1"];
          var name = list[1];
          assertEquals(fname, name, "$fname vs $name");
        }
      }

      reader?.close();
    });
    test('testRussianPoints UTF16', () async {
      Charset cs = Charset();
      await cs.setCharsetEncoding(UTF16);// use dart internal
      var reader = ShapefileFeatureReader(rusShp, charset: cs);
      await reader.open();
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        var fCoord = feature.geometry.getCoordinate();
        var text = feature.attributes["TEXT"];
        print(text);
        if (fCoord.distance(Coordinate(-0.814, 0.610)) < 0.001) {
          assertEquals(text, "Êèðèëëèöà");
        } else if (fCoord.distance(Coordinate(0.367, 0.620)) < 0.001) {
          assertEquals(text, "Ñìåøàíûé 12345");
        }
      }

      reader?.close();
    });
    test('testChinesePolygons', () async {
      Charset cs = Charset();
      await cs.setCharsetEncoding(UTF16);
      var reader = ShapefileFeatureReader(chineseShp, charset: cs);
      await reader.open();
      while (await reader.hasNext()) {
        Feature feature = await reader.next();
        var code = feature.attributes["ADCODE93"];
        assertEquals(code, 230000);
        var geometry = feature.geometry;
        var area = geometry.getArea();
        assertEqualsD(area, 53.956, 0.001, "${area} is not 53.956");
        // TODO do something for chinese
        // var name = feature.attributes["NAME"];
        // assertEquals(name, "asd", "Could not match: $name");
      }

      reader?.close();
    });
  });
}

String checkOutput(var victim, num n, int sz, int places) {
  String s = victim.getFieldStringWithDec(sz, places, n);

  // assertEquals("Formatted Output", xpected, s.trim());
  bool ascii = true;
  int i, c = 0;
  ;
  for (i = 0; i < s.length; i++) {
    c = s.codeUnitAt(i);
    if (c > 127) {
      ascii = false;
      break;
    }
  }
  assertTrueMsg("ascii [$i]:$c", ascii);
  assertEquals(sz, s.length);

  assertEqualsD(n.toDouble(), double.parse(s), math.pow(10.0, -places));

  // System.out.printf("%36s->%36s%n", n, s);

  return s;
}

Future<DbaseFileReader> openDbf(File bdfFile) async {
  var dbf = DbaseFileReader(FileReaderRandom(bdfFile), Charset(), null);
  await dbf.open();
  return dbf;
}
