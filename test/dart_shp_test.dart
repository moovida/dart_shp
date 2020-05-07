import 'dart:io';

import 'package:chunked_stream/chunked_stream.dart';
import 'package:dart_shp/dart_shp.dart';
import 'package:test/test.dart';

import 'testing_utilities.dart';

void main() async {
  File statesDbf;
  setUpAll(() async {
    statesDbf = File("./test/shapes/statepop.dbf");
  });

  tearDownAll(() {});

  group("DbaseFileTests - ", () {
    test("testNumberOfColsLoaded", () async {
      var dbf = await openStates(statesDbf);

      var header = dbf.getHeader();
      print(header);
      var numFields = header.getNumFields();
      print(numFields);
      expect(numFields, 252);

      dbf?.close();
    });
    test("testDataLoaded", () async {
      var dbf = await openStates(statesDbf);

      List<dynamic> attrs =
          await dbf.readEntryInto(List(dbf.getHeader().getNumFields()));
      expect(attrs[0], "Illinois");
      expect(attrs[4] as double, 143986.61);

      dbf?.close();
    });
    test("testRowVsEntry", () async {
      var dbf = await openStates(statesDbf);
      var dbf2 = await openStates(statesDbf);

      while (dbf.hasNext()) {
        List<dynamic> attrs =
            await dbf.readEntryInto(List(dbf.getHeader().getNumFields()));
        Row r = await dbf2.readRow();
        for (int i = 0, ii = attrs.length; i < ii; i++) {
          var attr1 = attrs[i];
          var attr2 = r.read(i);
          assertNotNull(attr1);
          assertNotNull(attr2);
          assertEquals(attr1, attr2);
        }
      }

      dbf?.close();
    });
    test("testHeader", () async {
      DbaseFileHeader header = new DbaseFileHeader();

      header.addColumn("emptyString", 'C', 20, 0);
      header.addColumn("emptyInt", 'N', 20, 0);
      header.addColumn("emptyDouble", 'N', 20, 5);
      header.addColumn("emptyFloat", 'F', 20, 5);
      header.addColumn("emptyLogical", 'L', 1, 0);
      header.addColumn("emptyDate", 'D', 20, 0);
      int length = header.getRecordLength();
      header.removeColumn("emptyDate");
      assertTrue(length != header.getRecordLength());
      header.addColumn("emptyDate", 'D', 20, 0);
      assertTrue(length == header.getRecordLength());
      header.removeColumn("billy");
      assertTrue(length == header.getRecordLength());
    });
  });

  test("testAddColumn", () async {
    DbaseFileHeader header = new DbaseFileHeader();

    header.addColumn("emptyInt", 'N', 9, 0);
    assertEquals(header.getFieldClass(0), int);
    assertEquals(header.getFieldLength(0), 9);

    header.addColumn("emptyString", 'C', 20, 0);
    assertEquals(header.getFieldClass(1), String);
    assertEquals(header.getFieldLength(1), 20);
  });
}

Future<DbaseFileReader> openStates(File statesDbf) async {
  var dbf = DbaseFileReader(statesDbf, Charset.defaultCharset(), null);
  await dbf.open();
  return dbf;
}
