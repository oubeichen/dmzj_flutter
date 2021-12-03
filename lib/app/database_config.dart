import 'package:flutter_dmzj/sql/comic_down.dart';
import 'package:flutter_dmzj/sql/comic_history.dart';
import 'package:tekartik_app_flutter_sqflite/sqflite.dart';

Future initDatabase() async {
  var databasesPath = await databaseFactory.getDatabasesPath();
  // File(databasesPath+"/nsplayer.db").deleteSync();
  var db = await databaseFactory.openDatabase(databasesPath + "/comic_history.db",
          options: OpenDatabaseOptions(
              version: 2,
              onCreate: (Database _db, int version) async {
                _createDataBase(_db);
              },
            onUpgrade: (Database _db, int oldVersion, int newVersion) async {
                _upgradeDataBase(_db, oldVersion, newVersion);
            }
          ));

  ComicHistoryProvider.db = db;
  ComicDownloadProvider.db = db;
}


_createDataBase(Database _db) async{
  await _db.execute('''
create table $comicHistoryTable ( 
  $comicHistoryColumnComicID integer primary key not null, 
  $comicHistoryColumnChapterID integer not null,
  $comicHistoryColumnPage double not null,
  $comicHistoryColumnPageOffset double not null,
  $comicHistoryMode integer not null)
''');

  await _db.execute('''
create table $comicDownloadTableName (
$comicDownloadColumnChapterID integer primary key not null,
$comicDownloadColumnChapterName text not null,
$comicDownloadColumnComicID integer not null,
$comicDownloadColumnComicName text not null,
$comicDownloadColumnStatus integer not null,
$comicDownloadColumnVolume text not null,
$comicDownloadColumnPage integer ,
$comicDownloadColumnCount integer ,
$comicDownloadColumnSavePath text ,
$comicDownloadColumnUrls text )
''');
}

void _upgradeDataBase(Database db, int oldVersion, int newVersion) async {
  if (oldVersion == 1) {
    var batch = db.batch();
    print("updateTable version $oldVersion $newVersion");
    batch.execute('alter table $comicHistoryTable add column $comicHistoryColumnPageOffset double');
    await batch.commit();
  }
}