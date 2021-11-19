import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_disk_lru_cache/flutter_disk_lru_cache.dart';
import 'package:path_provider/path_provider.dart';

class DiskLruCacheManager {
  static DiskLruCache _sDiskLruCache;

  static Future<DiskLruCache> _getLruCache() async {
    if (_sDiskLruCache != null) {
      return _sDiskLruCache;
    }
    WidgetsFlutterBinding.ensureInitialized();
    Directory tempDirectory = await getTemporaryDirectory();
    if (tempDirectory == null) {
      return null;
    }

    /// init
    DiskLruCache diskLruCache = await DiskLruCache.open(tempDirectory,
        valueCount: 1, version: "1.0.0", maxSize: 100 * 10274 * 1024);
    _sDiskLruCache = diskLruCache;
    return diskLruCache;
  }

  static Future<String> read(String key) async {
    var bytes = await readBytes(key);
    if (bytes == null) {
      return null;
    }
    String text = utf8.decode(bytes);
    return text;
  }

  static Future<Uint8List> readBytes(String key) async {
    var diskLruCache = await _getLruCache();
    if (diskLruCache == null) {
      return null;
    }

    Snapshot snapShot;
    try {
      snapShot = await diskLruCache.get(key);
      if (snapShot == null) {
        return null;
      }
      RandomAccessFile inV1 = snapShot.getRandomAccessFile(0);
      Uint8List bytes = inV1.readSync(snapShot.getLength(0));

      return bytes;
    } catch (e) {
      print(e);
      return null;
    } finally {
      if (snapShot != null) {
        snapShot.close();
      }
    }
  }

  static Future<bool> writeBytes(String key, Uint8List bytes) async {
    if (bytes == null) {
      return false;
    }
    var diskLruCache = await _getLruCache();
    if (diskLruCache == null) {
      return false;
    }
    Editor editor;
    try {
      // write data to disk cache
      editor = await diskLruCache.edit(key);
      if (editor == null) {
        return false;
      }
      // open io stream
      FaultHidingIOSink faultHidingIOSink = editor.newOutputIOSink(0);
      // write text to disk,but it is dirty,is not commited
      await faultHidingIOSink.writeByte(bytes);
      // flush io
      await faultHidingIOSink.flush();
      // close the io stream
      await faultHidingIOSink.close();
      // comfirm commit
      await editor.commit(diskLruCache);
    } catch (e) {
      print(e);
      if (editor != null) {
        editor.abort(diskLruCache);
      }
    }
  }

  static Future<bool> write(String key, String content) async {
    var diskLruCache = await _getLruCache();
    if (diskLruCache == null) {
      return false;
    }
    Editor editor;
    try {
      // write data to disk cache
      editor = await diskLruCache.edit(key);
      if (editor == null) {
        return false;
      }
      // open io stream
      FaultHidingIOSink faultHidingIOSink = editor.newOutputIOSink(0);
      // write text to disk,but it is dirty,is not commited
      await faultHidingIOSink.write(content);
      // flush io
      await faultHidingIOSink.flush();
      // close the io stream
      await faultHidingIOSink.close();
      // comfirm commit
      await editor.commit(diskLruCache);
    } catch (e) {
      print(e);
      if (editor != null) {
        editor.abort(diskLruCache);
      }
    }
  }
}
