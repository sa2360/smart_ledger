import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_ledger/db/database_helper.dart';
import 'package:smart_ledger/services/settings_service.dart';

bool _initialized = false;

Future<Directory> setUpDatabase() async {
  sqfliteFfiInit();
  if (!_initialized) {
    _initialized = true;
    databaseFactory = databaseFactoryFfiNoIsolate;
  }
  final directory = await Directory.systemTemp.createTemp('ledger_test_');
  await databaseFactory.setDatabasesPath(directory.path);
  SharedPreferences.setMockInitialValues({});
  await SettingsService.init();
  return directory;
}

Future<void> tearDownDatabase(Directory directory) async {
  await DatabaseHelper.instance.close();
  await directory.delete(recursive: true);
}
