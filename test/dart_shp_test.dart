import 'dart:io';

import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:dart_shp/dart_shp.dart';
import 'package:test/test.dart';

import 'testing_utilities.dart';

void main() async {
  File statesDbf;
  setUpAll(() async {
    statesDbf = File('./test/shapes/statepop.dbf');
  });

  tearDownAll(() {});

  group('DbaseFileTests - ', () {
    test('testNumberOfColsLoaded', () async {
      var dbf = await openStates(statesDbf);

      var header = dbf.getHeader();
      var numFields = header.getNumFields();
      expect(numFields, 252);

      dbf?.close();
    });
    test('testDataLoaded', () async {
      var dbf = await openStates(statesDbf);

      List<dynamic> attrs =
          await dbf.readEntryInto(List(dbf.getHeader().getNumFields()));
      expect(attrs[0], 'Illinois');
      expect(attrs[4] as double, 143986.61);

      dbf?.close();
    });
    test('testRowVsEntry', () async {
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
        DbaseFileWriter dbf =
            DbaseFileWriter(header, fileWriter, Charset.defaultCharset());
        await dbf.open();
        for (int i = 0; i < header.getNumRecords(); i++) {
          await dbf.writeRecord(List<dynamic>(6));
        }
        dbf.close();

        DbaseFileReader r = DbaseFileReader(FileReader(temp));
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
      FieldFormatter formatter = FieldFormatter(
          Charset.defaultCharset(), TimeZones.getDefault(), false);

      var stringWithInternationChars = 'hello ' '\u20ac';
      var format = formatter.getFieldString(10, stringWithInternationChars);
      assertEquals('          '.codeUnits.length, format.codeUnits.length);

      // test when the string is too big.
      stringWithInternationChars = '\u20ac' '1234567890';
      format = formatter.getFieldString(10, stringWithInternationChars);

      assertEquals('          '.codeUnits.length, format.codeUnits.length);
    });
  });
}

Future<DbaseFileReader> openStates(File statesDbf) async {
  var dbf =
      DbaseFileReader(FileReader(statesDbf), Charset.defaultCharset(), null);
  await dbf.open();
  return dbf;
}
