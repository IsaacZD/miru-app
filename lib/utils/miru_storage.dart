import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:isar/isar.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/utils/miru_directory.dart';
import 'package:path/path.dart' as p;

class MiruStorage {
  static late final Isar database;
  static late final Box settings;
  static const int _lastDatabaseVersion = 2;
  static late String _path;

  static ensureInitialized() async {
    _path = await MiruDirectory.getDirectory;
    // 初始化设置
    await Hive.initFlutter(_path);
    settings = await Hive.openBox("settings");
    await _initSettings();

    // 初始化数据库
    database = await Isar.open(
      [
        FavoriteSchema,
        HistorySchema,
        ExtensionSettingSchema,
        MangaSettingSchema,
        MiruDetailSchema,
        TMDBSchema,
      ],
      directory: _path,
    );

    // 数据库升级
    await performMigrationIfNeeded();
  }

  static performMigrationIfNeeded() async {
    final currentVersion = await getDatabaseVersion();
    debugPrint(currentVersion.toString());
    switch (currentVersion) {
      case 1:
        await migrateV1ToV2();
        break;
      case 2:
        return;
      default:
        throw Exception('Unknown version: $currentVersion');
    }

    // 更新到最新版本
    await settings.put(SettingKey.databaseVersion, _lastDatabaseVersion);
  }

  static migrateV1ToV2() async {
    // 获取所有的 TMDB 数据
    final tmdbList = await database.tMDBs.where().findAll();
    database.writeTxn(() async {
      // 给所有的 TMDB 数据添加 mediaType 字段
      for (final tmdb in tmdbList) {
        final tmdbdetail = TMDBDetail.fromJson(jsonDecode(tmdb.data));
        tmdb.mediaType = tmdbdetail.mediaType;
        await database.tMDBs.put(tmdb);
      }
    });

    // 修改所有 miruDetail 的 tmdbId 字段为本地的 TMDB id
    final miruList = await database.miruDetails.where().findAll();
    database.writeTxn(() async {
      for (final miru in miruList) {
        final tmdb = await database.tMDBs
            .where()
            .filter()
            .tmdbIDEqualTo(miru.tmdbID!)
            .findFirst();
        if (tmdb != null) {
          miru.tmdbID = tmdb.id;
          await database.miruDetails.put(miru);
        }
      }
    });
  }

  // 获取数据库版本
  static Future<int> getDatabaseVersion() async {
    // 先获取数据库版本
    final version = await settings.get(SettingKey.databaseVersion);
    // 如果没有版本号，并且没有数据库文件说明是第一次使用，返回最新的数据库版本
    if (version == null) {
      final path = await MiruDirectory.getDirectory;
      final dbPath = p.join(path, 'default.isar');
      if (File(dbPath).existsSync()) {
        return 1;
      }
      // 设置数据库版本并返回最新版本
      await settings.put(SettingKey.databaseVersion, _lastDatabaseVersion);
      return _lastDatabaseVersion;
    }
    // 如果有版本号，返回版本号
    return version;
  }

  static _initSettings() async {
    await _initSetting(SettingKey.miruRepoUrl, "https://miru-repo.0n0.dev");
    await _initSetting(SettingKey.tmdbKay, "");
    await _initSetting(SettingKey.autoCheckUpdate, true);
    await _initSetting(SettingKey.language, 'en');
    await _initSetting(SettingKey.novelFontSize, 18.0);
    await _initSetting(SettingKey.theme, 'system');
    await _initSetting(SettingKey.enableNSFW, false);
    await _initSetting(SettingKey.videoPlayer, 'built-in');
    await _initSetting(SettingKey.listMode, "grid");
  }

  static _initSetting(String key, dynamic value) async {
    if (!settings.containsKey(key)) {
      await settings.put(key, value);
    }
  }

  static setSetting(String key, dynamic value) async {
    await settings.put(key, value);
  }

  static getSetting(String key) {
    return settings.get(key);
  }
}

class SettingKey {
  static String theme = "Theme";
  static String miruRepoUrl = "MiruRepoUrl";
  static String tmdbKay = 'TMDBKey';
  static String autoCheckUpdate = 'AutoCheckUpdate';
  static String language = 'Language';
  static String novelFontSize = 'NovelFontSize';
  static String enableNSFW = 'EnableNSFW';
  static String videoPlayer = 'VideoPlayer';
  static String databaseVersion = 'DatabaseVersion';
  static String listMode = 'ListMode';
}
