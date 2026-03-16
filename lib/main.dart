import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

const String kBoxName = 'db';

// data
const String kTasksKey = 'tasks_v5';
const String kLogsKey = 'logs_v4';
const String kDayOverridesKey = 'day_overrides_v3';
const String kSeriSnapKey = 'seri_snaps_v1';
const String kUiStateKey = 'ui_state_v4';

// ui
const String kUiLastBreakShown = 'last_break_shown';
const String kUiDriveEnabled = 'drive_enabled';
const String kUiDriveLastBackup = 'drive_last_backup';
const String kUiTargetRatio = 'target_ratio';
const String kUiLastConfetti = 'last_confetti';
const String kUiThemeMode = 'theme_mode';
const String kUiLanguage = 'language';

// old
const String kOldTasksKey = 'tasks';
const String kOldLogsKey = 'logs';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(kBoxName);
  runApp(const AntoryApp());
}

/// ------------------------------------------------------------
/// helpers
/// ------------------------------------------------------------

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String humanDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

String weekdayNameShort(int weekday, AppLanguage lang) {
  const tr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (lang == AppLanguage.tr ? tr : en)[weekday - 1];
}

String weekdaysText(List<int>? weekdays, AppLanguage lang) {
  if (weekdays == null || weekdays.isEmpty || weekdays.length == 7) {
    return lang == AppLanguage.tr ? 'Her gün' : 'Every day';
  }
  final sorted = [...weekdays]..sort();
  return sorted.map((w) => weekdayNameShort(w, lang)).join(', ');
}

String newId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

List<int>? normalizeWeekdays(List<int>? days) {
  if (days == null) return null;
  final cleaned = days.where((e) => e >= 1 && e <= 7).toSet().toList()..sort();
  if (cleaned.isEmpty || cleaned.length == 7) return null;
  return cleaned;
}

bool taskIsValidOn(Map task, DateTime d) {
  final from = task['valid_from'] as String?;
  final to = task['valid_to'] as String?;
  if (from == null) return false;

  final dk = dateKey(d);
  final afterFrom = dk.compareTo(from) >= 0;
  final beforeTo = (to == null) || (dk.compareTo(to) <= 0);
  if (!(afterFrom && beforeTo)) return false;

  final rawDays = task['weekdays'];
  if (rawDays is List && rawDays.isNotEmpty) {
    final weekdaySet = rawDays.whereType<int>().toSet();
    return weekdaySet.contains(d.weekday);
  }

  return true;
}

bool taskIsArchived(Map task) => (task['valid_to'] as String?) != null;

ThemeMode parseThemeMode(String? v) {
  switch (v) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String cleanTime(String? v) {
  final t = v?.trim() ?? '';
  return t.isEmpty ? '' : t;
}

String? taskTimeText(Map<String, dynamic> task) {
  final s = (task['start_time'] as String?)?.trim() ?? '';
  final e = (task['end_time'] as String?)?.trim() ?? '';
  if (s.isEmpty && e.isEmpty) return null;
  if (s.isNotEmpty && e.isNotEmpty) return '$s - $e';
  return s.isNotEmpty ? s : e;
}

DateTime parseTimeToDate(String? value) {
  final now = DateTime.now();
  if (value == null || value.trim().isEmpty || !value.contains(':')) {
    return DateTime(now.year, now.month, now.day, 9, 0);
  }
  final parts = value.split(':');
  final h = int.tryParse(parts[0]) ?? 9;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return DateTime(now.year, now.month, now.day, h.clamp(0, 23), m.clamp(0, 59));
}

String timeToHm(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// ------------------------------------------------------------
/// language
/// ------------------------------------------------------------

enum AppLanguage { tr, en }

enum AddTaskScope { everyDay, todayOnly, specificDays }

AppLanguage parseLang(String? v) {
  switch (v) {
    case 'en':
      return AppLanguage.en;
    default:
      return AppLanguage.tr;
  }
}

class L {
  final AppLanguage lang;
  L(this.lang);

  AppLanguage get language => lang;

  static const Map<String, Map<String, String>> _v = {
    'app_name': {'tr': 'Antory', 'en': 'Antory'},
    'app_slogan': {'tr': 'Track Your Story', 'en': 'Track Your Story'},
    'today': {'tr': 'Bugün', 'en': 'Today'},
    'calendar': {'tr': 'Takvim', 'en': 'Calendar'},
    'tasks': {'tr': 'Görevler', 'en': 'Tasks'},
    'analytics': {'tr': 'Analitik', 'en': 'Analytics'},
    'profile': {'tr': 'Profil', 'en': 'Profile'},
    'settings': {'tr': 'Ayarlar', 'en': 'Settings'},
    'system': {'tr': 'Sistem', 'en': 'System'},
    'light': {'tr': 'Açık', 'en': 'Light'},
    'dark': {'tr': 'Koyu', 'en': 'Dark'},
    'target': {'tr': 'Hedef', 'en': 'Target'},
    'theme': {'tr': 'Tema', 'en': 'Theme'},
    'language': {'tr': 'Dil', 'en': 'Language'},
    'turkish': {'tr': 'Türkçe', 'en': 'Turkish'},
    'english': {'tr': 'İngilizce', 'en': 'English'},
    'drive_backup': {'tr': 'Drive Yedek', 'en': 'Drive Backup'},
    'google_sign_in': {'tr': 'Google ile Giriş', 'en': 'Sign in with Google'},
    'disconnect': {'tr': 'Bağlantıyı Kes', 'en': 'Disconnect'},
    'backup_to_drive': {'tr': 'Drive’a Yedekle', 'en': 'Backup to Drive'},
    'restore_from_drive': {
      'tr': 'Drive’dan Geri Yükle',
      'en': 'Restore from Drive'
    },
    'auto_daily_backup': {
      'tr': 'Otomatik günlük yedek',
      'en': 'Automatic daily backup'
    },
    'enabled': {'tr': 'Açık', 'en': 'Enabled'},
    'disabled': {'tr': 'Kapalı', 'en': 'Disabled'},
    'day_reset': {'tr': 'Günü Sıfırla', 'en': 'Reset Day'},
    'check': {'tr': 'Kontrol', 'en': 'Check'},
    'completed': {'tr': 'Tamamlandı', 'en': 'Completed'},
    'completed_count': {'tr': 'Tamamlanan', 'en': 'Completed'},
    'streak': {'tr': 'Seri', 'en': 'Streak'},
    'best_streak': {'tr': 'En Uzun', 'en': 'Best'},
    'date_pick': {'tr': 'Tarih seç', 'en': 'Pick date'},
    'new_task': {'tr': 'Yeni görev', 'en': 'New task'},
    'add_task': {'tr': 'Yeni görev ekle', 'en': 'Add new task'},
    'create_new_task': {'tr': 'Yeni görev oluştur', 'en': 'Create new task'},
    'add_from_archive': {'tr': 'Arşivden ekle', 'en': 'Add from archive'},
    'task_name': {'tr': 'Görev adı', 'en': 'Task name'},
    'start_time_optional': {'tr': 'Başlangıç saati', 'en': 'Start time'},
    'end_time_optional': {'tr': 'Bitiş saati', 'en': 'End time'},
    'cancel': {'tr': 'İptal', 'en': 'Cancel'},
    'save': {'tr': 'Kaydet', 'en': 'Save'},
    'save_today': {'tr': 'Kaydet (bugün)', 'en': 'Save (today)'},
    'save_every_day': {'tr': 'Her güne kaydet', 'en': 'Save for every day'},
    'edit': {'tr': 'Düzenle', 'en': 'Edit'},
    'delete': {'tr': 'Sil', 'en': 'Delete'},
    'delete_type': {'tr': 'Silme tipi', 'en': 'Delete type'},
    'delete_today': {'tr': 'Bugün', 'en': 'Today'},
    'delete_every_day': {'tr': 'Her gün', 'en': 'Every day'},
    'move_up': {'tr': 'Yukarı taşı', 'en': 'Move up'},
    'move_down': {'tr': 'Aşağı taşı', 'en': 'Move down'},
    'archive': {'tr': 'Arşiv', 'en': 'Archive'},
    'active': {'tr': 'Aktif', 'en': 'Active'},
    'unarchive': {'tr': 'Geri al', 'en': 'Restore'},
    'delete_forever': {'tr': 'Kalıcı sil', 'en': 'Delete permanently'},
    'confirm': {'tr': 'Onayla', 'en': 'Confirm'},
    'dismiss': {'tr': 'Vazgeç', 'en': 'Dismiss'},
    'continue': {'tr': 'Devam', 'en': 'Continue'},
    'daily': {'tr': 'Günlük', 'en': 'Daily'},
    'weekly': {'tr': 'Haftalık', 'en': 'Weekly'},
    'monthly': {'tr': 'Aylık', 'en': 'Monthly'},
    'average': {'tr': 'Ortalama', 'en': 'Average'},
    'total': {'tr': 'Toplam', 'en': 'Total'},
    'above_below': {'tr': 'Üst/Alt', 'en': 'Above/Below'},
    'daily_trend': {'tr': 'Günlük trend', 'en': 'Daily trend'},
    'pie_chart': {'tr': 'Pasta grafik', 'en': 'Pie chart'},
    'task_success': {'tr': 'Görev bazlı başarı', 'en': 'Task success'},
    'weekday': {'tr': 'Haftanın günü', 'en': 'Weekday'},
    'weakest_3': {'tr': 'En zayıf 3', 'en': 'Weakest 3'},
    'all': {'tr': 'Tümü', 'en': 'All'},
    'no_data': {'tr': 'Veri yok', 'en': 'No data'},
    'no_active_task': {'tr': 'Aktif görev yok.', 'en': 'No active task.'},
    'no_archive_task': {'tr': 'Arşiv görev yok.', 'en': 'No archived task.'},
    'no_task_for_date': {
      'tr': 'Bu tarihte geçerli görev yok.',
      'en': 'No active task for this date.'
    },
    'reset_done': {'tr': 'Sıfırlandı', 'en': 'Reset'},
    'drive_backup_done': {
      'tr': 'Drive yedek tamamlandı',
      'en': 'Drive backup completed'
    },
    'drive_restore_done': {
      'tr': 'Drive geri yüklendi',
      'en': 'Drive restore completed'
    },
    'drive_backup_not_found': {
      'tr': 'Drive yedeği bulunamadı',
      'en': 'Drive backup not found'
    },
    'google_connected': {
      'tr': 'Google hesabı bağlandı',
      'en': 'Google account connected'
    },
    'google_disconnected': {
      'tr': 'Google bağlantısı kaldırıldı',
      'en': 'Google account disconnected'
    },
    'loading_prepare': {
      'tr': 'Antory hazırlanıyor...',
      'en': 'Antory is preparing...'
    },
    'loading_google': {
      'tr': 'Google hesabı kontrol ediliyor...',
      'en': 'Checking Google account...'
    },
    'loading_drive_search': {
      'tr': 'Drive yedeği aranıyor...',
      'en': 'Searching Drive backup...'
    },
    'loading_drive_restore': {
      'tr': 'Drive yedeği yükleniyor...',
      'en': 'Restoring Drive backup...'
    },
    'motivation_title': {'tr': 'Günün sözü', 'en': 'Quote of the day'},
    'streak_broken': {'tr': 'Seri kırıldı', 'en': 'Streak broken'},
    'streak_broken_msg': {
      'tr': 'Dün %100 olmadı. Bugün yeni bir seri başlattın.',
      'en': 'Yesterday was not 100%. Today you started a new streak.'
    },
    'pick_from_archive_sub': {
      'tr': 'Kayıtlı görevleri özellikleriyle getir',
      'en': 'Reuse saved tasks with all properties'
    },
    'last_backup': {'tr': 'Son yedek', 'en': 'Last backup'},
    'not_connected': {
      'tr': 'Google hesabı bağlı değil',
      'en': 'No Google account connected'
    },
    'sign_in_for_drive': {
      'tr': 'Drive yedekleme için giriş yap',
      'en': 'Sign in for Drive backup'
    },
    'monday_short': {'tr': 'Pzt', 'en': 'Mon'},
    'tuesday_short': {'tr': 'Sal', 'en': 'Tue'},
    'wednesday_short': {'tr': 'Çar', 'en': 'Wed'},
    'thursday_short': {'tr': 'Per', 'en': 'Thu'},
    'friday_short': {'tr': 'Cum', 'en': 'Fri'},
    'saturday_short': {'tr': 'Cmt', 'en': 'Sat'},
    'sunday_short': {'tr': 'Paz', 'en': 'Sun'},
    'today_label': {'tr': 'Bugün', 'en': 'Today'},
    'week_label': {'tr': 'Hafta', 'en': 'Week'},
    'month_label': {'tr': 'Ay', 'en': 'Month'},
    'scope_every_day': {'tr': 'Her gün', 'en': 'Every day'},
    'scope_today_only': {'tr': 'Sadece bugün', 'en': 'Today only'},
    'scope_specific_days': {'tr': 'Belirli günler', 'en': 'Specific days'},
    'select_days': {'tr': 'Gün seçimi', 'en': 'Select days'},
    'done_label': {'tr': 'Yapılan', 'en': 'Done'},
    'remaining_label': {'tr': 'Yapılmayan', 'en': 'Remaining'},
  };

  String t(String key) {
    final code = lang == AppLanguage.tr ? 'tr' : 'en';
    return _v[key]?[code] ?? key;
  }
}

/// ------------------------------------------------------------
/// quote bank localized
/// ------------------------------------------------------------

const List<Map<String, String>> kQuoteBank = [
  {
    'tr': 'Gelecek, bugün yaptıklarına bağlıdır.',
    'en': 'The future depends on what you do today.',
    'author': 'Mahatma Gandhi',
  },
  {
    'tr': 'Başarının temel anahtarı eylemdir.',
    'en': 'Action is the foundational key to all success.',
    'author': 'Pablo Picasso',
  },
  {
    'tr': 'Başarı, her gün tekrarlanan küçük çabaların toplamıdır.',
    'en': 'Success is the sum of small efforts repeated day in and day out.',
    'author': 'Robert Collier',
  },
  {
    'tr': 'İyi yapılmış iş, iyi söylenmiş sözden üstündür.',
    'en': 'Well done is better than well said.',
    'author': 'Benjamin Franklin',
  },
  {
    'tr': 'Bekleme. Zaman asla tam uygun olmayacak.',
    'en': 'Do not wait. The time will never be just right.',
    'author': 'Napoleon Hill',
  },
  {
    'tr': 'Ölçülen şey yönetilir.',
    'en': 'What gets measured gets managed.',
    'author': 'Peter Drucker',
  },
  {
    'tr': 'Disiplin, hedeflerle başarı arasındaki köprüdür.',
    'en': 'Discipline is the bridge between goals and accomplishment.',
    'author': 'Jim Rohn',
  },
  {
    'tr': 'İşin en önemli kısmı başlangıçtır.',
    'en': 'The beginning is the most important part of the work.',
    'author': 'Plato',
  },
];

Map<String, String> quoteOfTheDay(DateTime d, AppLanguage lang) {
  final dayNumber =
      d.millisecondsSinceEpoch ~/ const Duration(days: 1).inMilliseconds;
  final idx = dayNumber % kQuoteBank.length;
  final item = kQuoteBank[idx];
  return {
    'quote': item[lang == AppLanguage.tr ? 'tr' : 'en'] ?? '',
    'author': item['author'] ?? '',
  };
}

/// ------------------------------------------------------------
/// drive
/// ------------------------------------------------------------

class DriveService {
  final GoogleSignIn _googleSignIn =
      GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  drive.DriveApi? _api;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<bool> signInInteractive() async {
    final acc = await _googleSignIn.signIn();
    if (acc == null) return false;
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return false;
    _api = drive.DriveApi(client);
    return true;
  }

  Future<bool> signInSilent() async {
    try {
      final acc = await _googleSignIn.signInSilently();
      if (acc == null) return false;
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) return false;
      _api = drive.DriveApi(client);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
    _api = null;
  }

  Future<String?> _findBackupFileId() async {
    if (_api == null) return null;
    final res = await _api!.files.list(
      q: "name='antory_backup.json' and trashed=false",
      spaces: 'drive',
    );
    if (res.files == null || res.files!.isEmpty) return null;
    return res.files!.first.id;
  }

  Future<void> backupJson(Map<String, dynamic> data) async {
    if (_api == null) return;
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    final media = drive.Media(Stream.value(bytes), bytes.length);

    final existingId = await _findBackupFileId();
    if (existingId != null) {
      await _api!.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      await _api!.files.create(
        drive.File()
          ..name = 'antory_backup.json'
          ..mimeType = 'application/json',
        uploadMedia: media,
      );
    }
  }

  Future<Map<String, dynamic>?> restoreJson() async {
    if (_api == null) return null;
    final id = await _findBackupFileId();
    if (id == null) return null;

    final media = await _api!.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = await media.stream.expand((e) => e).toList();
    final jsonStr = utf8.decode(bytes);
    final decoded = jsonDecode(jsonStr);

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }
}

/// ------------------------------------------------------------
/// repo
/// ------------------------------------------------------------

class Repo {
  final Box box = Hive.box(kBoxName);

  void ensureInitializedAndMigrateIfNeeded() {
    if (box.get(kTasksKey) == null) box.put(kTasksKey, <dynamic>[]);
    if (box.get(kLogsKey) == null) box.put(kLogsKey, <String, dynamic>{});
    if (box.get(kSeriSnapKey) == null) {
      box.put(kSeriSnapKey, <String, dynamic>{});
    }
    if (box.get(kDayOverridesKey) == null) {
      box.put(kDayOverridesKey, <String, dynamic>{});
    }
    if (box.get(kUiStateKey) == null) {
      box.put(kUiStateKey, <String, dynamic>{
        kUiDriveEnabled: false,
        kUiTargetRatio: 0.80,
        kUiThemeMode: 'system',
        kUiLanguage: 'tr',
      });
    }

    final vTasks = box.get(kTasksKey);
    final hasTasks = (vTasks is List) && vTasks.isNotEmpty;

    final oldTasks = box.get(kOldTasksKey);
    final oldLogs = box.get(kOldLogsKey);

    if (!hasTasks && oldTasks is List && oldTasks.isNotEmpty) {
      final today = dateKey(dateOnly(DateTime.now()));
      final List<Map<String, dynamic>> migratedTasks = [];
      int sort = 1;

      for (final t in oldTasks) {
        if (t is String && t.trim().isNotEmpty) {
          migratedTasks.add({
            'id': newId(),
            'name': t.trim(),
            'sort': sort++,
            'valid_from': today,
            'valid_to': null,
            'start_time': '',
            'end_time': '',
            'weekdays': null,
          });
        }
      }

      final Map<String, String> nameToId = {
        for (final t in migratedTasks)
          (t['name'] as String): (t['id'] as String),
      };

      final Map<String, dynamic> migratedLogs = {};
      if (oldLogs is Map) {
        oldLogs.forEach((d, raw) {
          if (d is! String) return;
          final Map<String, bool> day = {};
          if (raw is Map) {
            raw.forEach((k, v) {
              if (k is String) {
                final id = nameToId[k];
                if (id != null) day[id] = (v == true);
              }
            });
          }
          migratedLogs[d] = day;
        });
      }

      box.put(kTasksKey, migratedTasks);
      box.put(kLogsKey, migratedLogs);
    }

    final tasksNow = box.get(kTasksKey);
    if (tasksNow is List && tasksNow.isEmpty) {
      final today = dateKey(dateOnly(DateTime.now()));
      const defaults = <String>[
        '7’de kalk',
        'Spor',
        'Kitap oku',
        '104 şınav',
        'Sigara içme',
        'Çalışma',
        'Şükret',
        'Gitar',
        'Yatış',
      ];

      int sort = 1;
      final list = defaults.map((name) {
        return {
          'id': newId(),
          'name': name,
          'sort': sort++,
          'valid_from': today,
          'valid_to': null,
          'start_time': '',
          'end_time': '',
          'weekdays': null,
        };
      }).toList();

      box.put(kTasksKey, list);
    }
  }

  List<Map<String, dynamic>> getAllTasks() {
    final raw = box.get(kTasksKey);
    if (raw is List) {
      final list = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      list.sort((a, b) =>
          (a['sort'] as int? ?? 0).compareTo((b['sort'] as int? ?? 0)));
      return list;
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> getAllLogs() {
    final raw = box.get(kLogsKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> getSeriSnaps() {
    final raw = box.get(kSeriSnapKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> getUiState() {
    final raw = box.get(kUiStateKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<void> setUiValue(String key, dynamic value) async {
    final ui = getUiState();
    ui[key] = value;
    await box.put(kUiStateKey, ui);
  }

  bool driveEnabled() => getUiState()[kUiDriveEnabled] == true;
  String? driveLastBackupKey() {
    final v = getUiState()[kUiDriveLastBackup];
    return v is String ? v : null;
  }

  double targetRatio() {
    final t = getUiState()[kUiTargetRatio];
    return t is num ? t.toDouble() : 0.80;
  }

  ThemeMode themeMode() =>
      parseThemeMode(getUiState()[kUiThemeMode] as String?);
  AppLanguage language() => parseLang(getUiState()[kUiLanguage] as String?);

  String? lastConfettiKey() {
    final v = getUiState()[kUiLastConfetti];
    return v is String ? v : null;
  }

  Map<String, bool> logsForDate(DateTime d) {
    final all = getAllLogs();
    final raw = all[dateKey(d)];
    if (raw is Map) {
      final result = <String, bool>{};
      raw.forEach((kk, vv) {
        if (kk is String) result[kk] = vv == true;
      });
      return result;
    }
    return <String, bool>{};
  }

  bool isTaskDone(DateTime d, String taskId) => logsForDate(d)[taskId] == true;
  int totalCountForDate(DateTime d) => tasksForDate(d).length;

  int completedCountForDate(DateTime d) {
    final tasks = tasksForDate(d);
    if (tasks.isEmpty) return 0;
    final logs = logsForDate(d);
    int done = 0;
    for (final t in tasks) {
      final id = t['id'] as String;
      if (logs[id] == true) done++;
    }
    return done;
  }

  double ratioForDate(DateTime d) {
    final total = totalCountForDate(d);
    if (total == 0) return 0;
    return completedCountForDate(d) / total;
  }

  bool isPerfectDay(DateTime d) =>
      totalCountForDate(d) > 0 && ratioForDate(d) >= 1.0;

  int currentSeri() {
    final today = dateOnly(DateTime.now());
    int seri = 0;
    DateTime cursor = today;
    while (true) {
      if (!isPerfectDay(cursor)) break;
      seri++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return seri;
  }

  int longestSeri() {
    final logKeys = getAllLogs().keys.whereType<String>().toList();
    final snapKeys = getSeriSnaps().keys.whereType<String>().toList();
    final allKeys = {...logKeys, ...snapKeys}.toList()..sort();
    if (allKeys.isEmpty) return 0;

    int maxSeri = 0, cur = 0;
    DateTime? prev;

    for (final k in allKeys) {
      DateTime d;
      try {
        d = DateTime.parse(k);
      } catch (_) {
        continue;
      }

      final perfect = isPerfectDay(d);
      if (perfect) {
        if (prev != null && d.difference(prev).inDays == 1) {
          cur++;
        } else {
          cur = 1;
        }
        maxSeri = max(maxSeri, cur);
      } else {
        cur = 0;
      }
      prev = d;
    }
    return maxSeri;
  }

  Future<void> writeSeriSnapshotIfPerfect(DateTime d) async {
    final day = dateOnly(d);
    if (!isPerfectDay(day)) return;

    final snaps = getSeriSnaps();
    final key = dateKey(day);
    snaps[key] = {
      'perfect': true,
      'total': totalCountForDate(day),
      'done': completedCountForDate(day),
      'at': DateTime.now().toIso8601String(),
    };
    await box.put(kSeriSnapKey, snaps);
  }

  Future<void> setDone(DateTime d, String taskId, bool done) async {
    final all = getAllLogs();
    final key = dateKey(d);
    final current = logsForDate(d);
    current[taskId] = done;
    all[key] = current;
    await box.put(kLogsKey, all);
    await writeSeriSnapshotIfPerfect(d);
  }

  Future<void> removeLogForTaskOnDate(DateTime d, String taskId) async {
    final all = getAllLogs();
    final key = dateKey(d);
    final raw = all[key];
    if (raw is Map) {
      raw.remove(taskId);
      all[key] = raw;
      await box.put(kLogsKey, all);
    }
  }

  Future<void> resetDay(DateTime d) async {
    final all = getAllLogs();
    all.remove(dateKey(d));
    await box.put(kLogsKey, all);
  }

  Future<void> addTask(
    String name, {
    String? startTime,
    String? endTime,
    DateTime? validFrom,
    DateTime? validTo,
    List<int>? weekdays,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final tasks = getAllTasks();
    final fromDay = dateOnly(validFrom ?? DateTime.now());
    final normalizedDays = normalizeWeekdays(weekdays);

    final nextSort = tasks.isEmpty
        ? 1
        : (tasks.map((t) => t['sort'] as int? ?? 0).fold<int>(0, max) + 1);

    tasks.add({
      'id': newId(),
      'name': trimmed,
      'sort': nextSort,
      'valid_from': dateKey(fromDay),
      'valid_to': validTo == null ? null : dateKey(dateOnly(validTo)),
      'start_time': cleanTime(startTime),
      'end_time': cleanTime(endTime),
      'weekdays': normalizedDays,
    });
    await box.put(kTasksKey, tasks);
  }

  Future<void> renameTask(
    String taskId,
    String newName, {
    String? startTime,
    String? endTime,
    List<int>? weekdays,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;

    tasks[idx]['name'] = trimmed;
    tasks[idx]['start_time'] = cleanTime(startTime);
    tasks[idx]['end_time'] = cleanTime(endTime);
    tasks[idx]['weekdays'] = normalizeWeekdays(weekdays);
    await box.put(kTasksKey, tasks);
  }

  List<int> taskWeekdaysOrAll(Map<String, dynamic> task) {
    final raw = (task['weekdays'] as List?)?.whereType<int>().toList();
    final normalized = normalizeWeekdays(raw);
    return normalized ?? [1, 2, 3, 4, 5, 6, 7];
  }

  Future<void> updateTaskForSpecificDays(
    String taskId, {
    required List<int> weekdays,
    String? newName,
    String? startTime,
    String? endTime,
  }) async {
    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;

    final normalized = normalizeWeekdays(weekdays);

    tasks[idx]['weekdays'] = normalized;
    if (newName != null && newName.trim().isNotEmpty) {
      tasks[idx]['name'] = newName.trim();
    }
    if (startTime != null) tasks[idx]['start_time'] = cleanTime(startTime);
    if (endTime != null) tasks[idx]['end_time'] = cleanTime(endTime);

    await box.put(kTasksKey, tasks);
  }

  Future<void> deleteTaskSpecificDays(
    String taskId,
    List<int> weekdays,
  ) async {
    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;

    final currentDays = taskWeekdaysOrAll(tasks[idx]);
    final removeDays = weekdays.toSet();
    final remainingDays =
        currentDays.where((d) => !removeDays.contains(d)).toList()..sort();

    if (remainingDays.isEmpty) {
      final yesterday =
          dateOnly(DateTime.now()).subtract(const Duration(days: 1));
      tasks[idx]['valid_to'] = dateKey(yesterday);
    } else {
      tasks[idx]['weekdays'] = normalizeWeekdays(remainingDays);
    }

    await box.put(kTasksKey, tasks);
  }

  Future<void> archiveTask(String taskId) async {
    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;

    final yesterday =
        dateOnly(DateTime.now()).subtract(const Duration(days: 1));
    tasks[idx]['valid_to'] = dateKey(yesterday);
    await box.put(kTasksKey, tasks);
  }

  Future<void> restoreTask(String taskId) async {
    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;
    tasks[idx]['valid_to'] = null;
    await box.put(kTasksKey, tasks);
  }

  Future<void> restoreTaskFromArchiveAsNew(String taskId) async {
    final tasks = getAllTasks();
    final idx = tasks.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;
    tasks[idx]['valid_to'] = null;
    tasks[idx]['sort'] =
        (tasks.map((t) => t['sort'] as int? ?? 0).fold<int>(0, max) + 1);
    await box.put(kTasksKey, tasks);
  }

  Future<void> deleteTaskPermanently(String taskId) async {
    final tasks = getAllTasks();
    tasks.removeWhere((t) => t['id'] == taskId);
    await box.put(kTasksKey, tasks);

    final logs = getAllLogs();
    bool changed = false;
    logs.forEach((_, raw) {
      if (raw is Map && raw.containsKey(taskId)) {
        raw.remove(taskId);
        changed = true;
      }
    });
    if (changed) await box.put(kLogsKey, logs);
  }

  Map<String, dynamic> _allDayOverrides() {
    final raw = box.get(kDayOverridesKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _overridesForDate(DateTime d) {
    final all = _allDayOverrides();
    final raw = all[dateKey(d)];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<void> _writeOverridesForDate(
      DateTime d, Map<String, dynamic> day) async {
    final all = _allDayOverrides();
    all[dateKey(d)] = day;
    await box.put(kDayOverridesKey, all);
  }

  Future<void> setTaskFieldsForDay(
    DateTime d,
    String taskId, {
    String? name,
    String? startTime,
    String? endTime,
  }) async {
    final day = _overridesForDate(d);
    final cur = (day[taskId] is Map)
        ? Map<String, dynamic>.from(day[taskId] as Map)
        : <String, dynamic>{};

    if (name != null) cur['name'] = name.trim();
    if (startTime != null) cur['start_time'] = cleanTime(startTime);
    if (endTime != null) cur['end_time'] = cleanTime(endTime);

    day[taskId] = cur;
    await _writeOverridesForDate(d, day);
  }

  Future<void> hideTaskForDay(DateTime d, String taskId, bool hidden) async {
    final day = _overridesForDate(d);
    final cur = (day[taskId] is Map)
        ? Map<String, dynamic>.from(day[taskId] as Map)
        : <String, dynamic>{};
    cur['hidden'] = hidden;
    day[taskId] = cur;
    await _writeOverridesForDate(d, day);
  }

  Future<void> setTaskSortForDay(DateTime d, String taskId, int sort) async {
    final day = _overridesForDate(d);
    final cur = (day[taskId] is Map)
        ? Map<String, dynamic>.from(day[taskId] as Map)
        : <String, dynamic>{};
    cur['sort'] = sort;
    day[taskId] = cur;
    await _writeOverridesForDate(d, day);
  }

  List<Map<String, dynamic>> tasksForDate(DateTime d) {
    final base = getAllTasks().where((t) => taskIsValidOn(t, d)).toList();
    final ov = _overridesForDate(d);

    final applied = <Map<String, dynamic>>[];
    for (final t in base) {
      final id = t['id'] as String;
      final o = ov[id];

      if (o is Map) {
        final m = Map<String, dynamic>.from(o);
        if (m['hidden'] == true) continue;

        final copy = Map<String, dynamic>.from(t);
        if (m['name'] is String && (m['name'] as String).trim().isNotEmpty) {
          copy['name'] = (m['name'] as String).trim();
        }
        if (m['start_time'] is String) copy['start_time'] = m['start_time'];
        if (m['end_time'] is String) copy['end_time'] = m['end_time'];
        if (m['sort'] is int) copy['sort'] = m['sort'] as int;
        applied.add(copy);
      } else {
        applied.add(Map<String, dynamic>.from(t));
      }
    }

    applied.sort(
        (a, b) => (a['sort'] as int? ?? 0).compareTo((b['sort'] as int? ?? 0)));
    return applied;
  }

  List<Map<String, dynamic>> archivedTasks() {
    final tasks = getAllTasks().where((t) => taskIsArchived(t)).toList();
    tasks.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return tasks;
  }

  Future<void> moveTaskForDay(DateTime d, String taskId,
      {required bool up}) async {
    final list = tasksForDate(d);
    final idx = list.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;
    if (up && idx == 0) return;
    if (!up && idx == list.length - 1) return;

    final swapIdx = up ? idx - 1 : idx + 1;
    final a = list[idx];
    final b = list[swapIdx];
    final aSort = a['sort'] as int? ?? (idx + 1);
    final bSort = b['sort'] as int? ?? (swapIdx + 1);

    await setTaskSortForDay(d, a['id'] as String, bSort);
    await setTaskSortForDay(d, b['id'] as String, aSort);
  }

  Future<String?> cloneTaskForOnlyThatDay({
    required DateTime day,
    required String sourceTaskId,
    required String newName,
    String? startTime,
    String? endTime,
  }) async {
    final tasks = getAllTasks();
    final src = tasks.firstWhere(
      (t) => t['id'] == sourceTaskId,
      orElse: () => <String, dynamic>{},
    );
    if (src.isEmpty) return null;

    final dk = dateKey(day);
    final visible = tasksForDate(day);
    final maxSort = visible.isEmpty
        ? 0
        : visible.map((t) => (t['sort'] as int? ?? 0)).reduce(max);

    final newTaskId = newId();
    tasks.add({
      'id': newTaskId,
      'name': newName.trim(),
      'sort': maxSort + 1,
      'valid_from': dk,
      'valid_to': dk,
      'start_time': cleanTime(startTime ?? (src['start_time'] as String?)),
      'end_time': cleanTime(endTime ?? (src['end_time'] as String?)),
      'weekdays': null,
    });

    await box.put(kTasksKey, tasks);
    await hideTaskForDay(day, sourceTaskId, true);

    final wasDone = isTaskDone(day, sourceTaskId);
    await removeLogForTaskOnDate(day, sourceTaskId);
    if (wasDone) {
      await setDone(day, newTaskId, true);
    }

    return newTaskId;
  }

  Future<String?> addArchivedTaskForOnlyThatDay({
    required DateTime day,
    required String sourceTaskId,
  }) async {
    final tasks = getAllTasks();
    final src = tasks.firstWhere(
      (t) => t['id'] == sourceTaskId,
      orElse: () => <String, dynamic>{},
    );
    if (src.isEmpty) return null;

    final dk = dateKey(day);
    final visible = tasksForDate(day);
    final maxSort = visible.isEmpty
        ? 0
        : visible.map((t) => (t['sort'] as int? ?? 0)).reduce(max);

    final newTaskId = newId();
    tasks.add({
      'id': newTaskId,
      'name': src['name'],
      'sort': maxSort + 1,
      'valid_from': dk,
      'valid_to': dk,
      'start_time': src['start_time'],
      'end_time': src['end_time'],
      'weekdays': null,
    });

    await box.put(kTasksKey, tasks);
    return newTaskId;
  }

  Map<String, dynamic> exportAllData() {
    return {
      'tasks': box.get(kTasksKey),
      'logs': box.get(kLogsKey),
      'seri': box.get(kSeriSnapKey),
      'ui': box.get(kUiStateKey),
      'day_overrides': box.get(kDayOverridesKey),
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    if (data.containsKey('tasks')) await box.put(kTasksKey, data['tasks']);
    if (data.containsKey('logs')) await box.put(kLogsKey, data['logs']);
    if (data.containsKey('seri')) await box.put(kSeriSnapKey, data['seri']);
    if (data.containsKey('ui')) await box.put(kUiStateKey, data['ui']);
    if (data.containsKey('day_overrides')) {
      await box.put(kDayOverridesKey, data['day_overrides']);
    }
  }
}

/// ------------------------------------------------------------
/// app
/// ------------------------------------------------------------

class AntoryApp extends StatefulWidget {
  const AntoryApp({super.key});

  @override
  State<AntoryApp> createState() => _AntoryAppState();
}

class _AntoryAppState extends State<AntoryApp> {
  final Repo repo = Repo();

  @override
  void initState() {
    super.initState();
    repo.ensureInitializedAndMigrateIfNeeded();
  }

  void _refreshApp() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    final lang = repo.language();
    final l = L(lang);

    final light = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7F3),
    );

    final dark = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F1511),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: l.t('app_name'),
      themeMode: repo.themeMode(),
      theme: light,
      darkTheme: dark,
      home: AppBootstrapper(
        repo: repo,
        onAppRefresh: _refreshApp,
      ),
    );
  }
}

/// ------------------------------------------------------------
/// bootstrap
/// ------------------------------------------------------------

class AppBootstrapper extends StatefulWidget {
  final Repo repo;
  final VoidCallback onAppRefresh;

  const AppBootstrapper({
    super.key,
    required this.repo,
    required this.onAppRefresh,
  });

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  late final DriveService _driveService;
  bool _loading = true;
  String _status = '';

  bool _showLogo = false;
  bool _showQuote = false;

  @override
  void initState() {
    super.initState();
    _driveService = DriveService();
    _status = L(widget.repo.language()).t('loading_prepare');
    unawaited(_bootstrap());

    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _showLogo = true);
    });

    Future.delayed(const Duration(milliseconds: 980), () {
      if (mounted) setState(() => _showQuote = true);
    });
  }

  Future<void> _bootstrap() async {
    final l = L(widget.repo.language());

    try {
      if (mounted) setState(() => _status = l.t('loading_google'));
      final signed = await _driveService.signInSilent();

      if (signed && widget.repo.driveEnabled()) {
        if (mounted) setState(() => _status = l.t('loading_drive_search'));
        final data = await _driveService.restoreJson();
        if (data != null) {
          if (mounted) setState(() => _status = l.t('loading_drive_restore'));
          await widget.repo.importAllData(data);
        }
      }
    } catch (_) {
      // silent
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1700));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.repo.language();
    final l = L(lang);

    if (_loading) {
      final q = quoteOfTheDay(DateTime.now(), lang);
      final cs = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF0D1511),
                      Color(0xFF132119),
                      Color(0xFF183327),
                    ]
                  : const [
                      Color(0xFFF7FAF5),
                      Color(0xFFEAF4EC),
                      Color(0xFFDCEFE1),
                    ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.25),
                        radius: 0.95,
                        colors: [
                          cs.primary.withOpacity(isDark ? 0.16 : 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedOpacity(
                        opacity: _showLogo ? 1 : 0,
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        child: AnimatedScale(
                          scale: _showLogo ? 1 : 0.92,
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          child: Column(
                            children: [
                              const AntoryLogo(size: 124),
                              const SizedBox(height: 22),
                              Text(
                                l.t('app_name'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Antory — ${l.t("app_slogan")}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      letterSpacing: 0.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      AnimatedOpacity(
                        opacity: _showQuote ? 1 : 0,
                        duration: const Duration(milliseconds: 850),
                        curve: Curves.easeOutCubic,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 850),
                          curve: Curves.easeOutCubic,
                          offset:
                              _showQuote ? Offset.zero : const Offset(0, 0.08),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 22),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.white.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.white.withOpacity(0.88),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withOpacity(0.24)
                                      : cs.primary.withOpacity(0.08),
                                  blurRadius: 30,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  l.t('motivation_title'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.7,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '“${q['quote']!}”',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.42,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '— ${q['author']}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      AnimatedOpacity(
                        opacity: _showQuote ? 1 : 0,
                        duration: const Duration(milliseconds: 750),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return HomeShell(
      repo: widget.repo,
      driveService: _driveService,
      onAppRefresh: widget.onAppRefresh,
    );
  }
}

/// ------------------------------------------------------------
/// home shell
/// ------------------------------------------------------------

class HomeShell extends StatefulWidget {
  final Repo repo;
  final DriveService driveService;
  final VoidCallback onAppRefresh;

  const HomeShell({
    super.key,
    required this.repo,
    required this.driveService,
    required this.onAppRefresh,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  Repo get repo => widget.repo;
  DriveService get driveService => widget.driveService;

  int _index = 0;
  int _revision = 0;
  DateTime _selectedDate = dateOnly(DateTime.now());
  bool _autoBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_autoBackupIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      unawaited(_autoBackupIfNeeded());
    }
  }

  Future<void> _autoBackupIfNeeded() async {
    if (_autoBusy) return;
    if (!repo.driveEnabled()) return;

    final todayKey = dateKey(dateOnly(DateTime.now()));
    if (repo.driveLastBackupKey() == todayKey) return;

    _autoBusy = true;
    try {
      final ok = await driveService.signInSilent();
      if (!ok) return;
      await driveService.backupJson(repo.exportAllData());
      await repo.setUiValue(kUiDriveLastBackup, todayKey);
    } catch (_) {
      // silent
    } finally {
      _autoBusy = false;
    }
  }

  void _refreshData() {
    if (!mounted) return;
    setState(() {
      _revision++;
    });
  }

  void _goToDate(DateTime d) {
    setState(() {
      _selectedDate = dateOnly(d);
      _index = 0;
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());

    final pages = [
      TodayScreen(
        key: ValueKey('today_$_revision'),
        repo: repo,
        initialDate: _selectedDate,
        onDatePicked: (d) => setState(() => _selectedDate = d),
        onDataChanged: _refreshData,
      ),
      CalendarScreen(
        key: ValueKey('calendar_$_revision'),
        repo: repo,
        initialSelectedDate: _selectedDate,
        onDateSelected: _goToDate,
      ),
      TasksScreen(
        key: ValueKey('tasks_$_revision'),
        repo: repo,
        onDataChanged: _refreshData,
      ),
      AnalyticsScreen(
        key: ValueKey('analytics_$_revision'),
        repo: repo,
      ),
      ProfileScreen(
        key: ValueKey('profile_$_revision'),
        repo: repo,
        driveService: driveService,
        onAppRefresh: widget.onAppRefresh,
        onLocalRefresh: () => setState(() {}),
      ),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: pages[_index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.checklist),
            label: l.t('today'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month),
            label: l.t('calendar'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune),
            label: l.t('tasks'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights),
            label: l.t('analytics'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: l.t('profile'),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// logo
/// ------------------------------------------------------------

class AntoryLogo extends StatelessWidget {
  final double size;
  const AntoryLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFDCE3D6), Color(0xFF58B999)],
            ),
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// time picker
/// ------------------------------------------------------------

Future<String?> showHmPicker(
  BuildContext context, {
  String? initialValue,
}) async {
  final theme = Theme.of(context);
  DateTime selected = parseTimeToDate(initialValue);

  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) {
      return SafeArea(
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('İptal'),
                    ),
                    const Spacer(),
                    Text(
                      'Saat seç',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(timeToHm(selected)),
                      child: const Text('Seç'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: selected,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  return result;
}

/// ------------------------------------------------------------
/// profile
/// ------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  final Repo repo;
  final DriveService driveService;
  final VoidCallback onAppRefresh;
  final VoidCallback onLocalRefresh;

  const ProfileScreen({
    super.key,
    required this.repo,
    required this.driveService,
    required this.onAppRefresh,
    required this.onLocalRefresh,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Repo get repo => widget.repo;
  DriveService get driveService => widget.driveService;

  bool _busy = false;

  Future<void> _signIn() async {
    final l = L(repo.language());
    setState(() => _busy = true);
    try {
      final ok = await driveService.signInInteractive();
      if (!mounted) return;
      if (ok) {
        widget.onLocalRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.t('google_connected'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final l = L(repo.language());
    setState(() => _busy = true);
    try {
      await driveService.signOut();
      if (!mounted) return;
      widget.onLocalRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('google_disconnected'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    final l = L(repo.language());
    setState(() => _busy = true);
    try {
      final ok = await driveService.signInInteractive();
      if (!ok) return;
      await repo.setUiValue(kUiDriveEnabled, true);
      await driveService.backupJson(repo.exportAllData());
      await repo.setUiValue(
          kUiDriveLastBackup, dateKey(dateOnly(DateTime.now())));
      if (!mounted) return;
      widget.onLocalRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('drive_backup_done'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yedek hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final l = L(repo.language());
    setState(() => _busy = true);
    try {
      final ok = await driveService.signInInteractive();
      if (!ok) return;
      final data = await driveService.restoreJson();
      if (data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.t('drive_backup_not_found'))),
        );
        return;
      }
      await repo.importAllData(data);
      if (!mounted) return;
      widget.onAppRefresh();
      widget.onLocalRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('drive_restore_done'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Geri yükleme hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());
    final cs = Theme.of(context).colorScheme;
    final user = driveService.currentUser;
    final mode = repo.themeMode();
    final lang = repo.language();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('profile')),
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: AntoryLogo(size: 32),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Antory — ${l.t("app_slogan")}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(
                      user == null ? Icons.cloud_off : Icons.cloud_done,
                      color: cs.primary,
                    ),
                  ),
                  title: Text(
                    user?.displayName ?? l.t('not_connected'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(user?.email ?? l.t('sign_in_for_drive')),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FancyButton(
                        label: user == null
                            ? l.t('google_sign_in')
                            : l.t('disconnect'),
                        icon: user == null ? Icons.login : Icons.logout,
                        onPressed:
                            _busy ? null : (user == null ? _signIn : _signOut),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('drive_backup'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: repo.driveEnabled(),
                  onChanged: (v) async {
                    await repo.setUiValue(kUiDriveEnabled, v);
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('auto_daily_backup')),
                  subtitle: Text(
                    repo.driveLastBackupKey() == null
                        ? l.t('disabled')
                        : '${l.t("last_backup")}: ${repo.driveLastBackupKey()}',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FancyButton(
                        label: l.t('backup_to_drive'),
                        icon: Icons.cloud_upload,
                        onPressed: _busy ? null : _backup,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FancyButton(
                        label: l.t('restore_from_drive'),
                        icon: Icons.cloud_download,
                        onPressed: _busy ? null : _restore,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('theme'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: mode,
                  onChanged: (_) async {
                    await repo.setUiValue(kUiThemeMode, 'system');
                    widget.onAppRefresh();
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('system')),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: mode,
                  onChanged: (_) async {
                    await repo.setUiValue(kUiThemeMode, 'light');
                    widget.onAppRefresh();
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('light')),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: mode,
                  onChanged: (_) async {
                    await repo.setUiValue(kUiThemeMode, 'dark');
                    widget.onAppRefresh();
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('dark')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('language'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                RadioListTile<AppLanguage>(
                  value: AppLanguage.tr,
                  groupValue: lang,
                  onChanged: (_) async {
                    await repo.setUiValue(kUiLanguage, 'tr');
                    widget.onAppRefresh();
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('turkish')),
                ),
                RadioListTile<AppLanguage>(
                  value: AppLanguage.en,
                  groupValue: lang,
                  onChanged: (_) async {
                    await repo.setUiValue(kUiLanguage, 'en');
                    widget.onAppRefresh();
                    if (mounted) setState(() {});
                  },
                  title: Text(l.t('english')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// today
/// ------------------------------------------------------------

class TodayScreen extends StatefulWidget {
  final Repo repo;
  final DateTime initialDate;
  final ValueChanged<DateTime> onDatePicked;
  final VoidCallback onDataChanged;

  const TodayScreen({
    super.key,
    required this.repo,
    required this.initialDate,
    required this.onDatePicked,
    required this.onDataChanged,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Repo get repo => widget.repo;

  late DateTime _selectedDate;
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _selectedDate = dateOnly(widget.initialDate);
    _confetti =
        ConfettiController(duration: const Duration(milliseconds: 1000));
  }

  Future<void> _showTaskActionsSheet(Map<String, dynamic> task) async {
    final l = L(repo.language());
    final id = task['id'] as String;
    final name = task['name'] as String;
    final startTime = task['start_time'] as String?;
    final endTime = task['end_time'] as String?;

    Future<List<int>?> askSpecificDays(List<int> initialDays) async {
      final selected = {...initialDays};

      return await showDialog<List<int>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: Text(
                  l.language == AppLanguage.tr ? 'Gün seç' : 'Select days'),
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  final isSelected = selected.contains(day);
                  return FilterChip(
                    label: Text(weekdayNameShort(day, l.language)),
                    selected: isSelected,
                    onSelected: (v) {
                      setLocalState(() {
                        if (v) {
                          selected.add(day);
                        } else {
                          selected.remove(day);
                        }
                      });
                    },
                  );
                }),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(l.t('cancel')),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(selected.toList()..sort()),
                  child: Text(l.t('save')),
                ),
              ],
            );
          },
        ),
      );
    }

    Future<void> editDialog() async {
      final c = TextEditingController(text: name);
      String start = startTime ?? '';
      String end = endTime ?? '';

      final scope = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocalState) {
            Future<void> pickStart() async {
              final res = await showHmPicker(ctx, initialValue: start);
              if (res != null) setLocalState(() => start = res);
            }

            Future<void> pickEnd() async {
              final res = await showHmPicker(ctx, initialValue: end);
              if (res != null) setLocalState(() => end = res);
            }

            return AlertDialog(
              title: Text(l.t('edit')),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: c,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.sentences,
                      autocorrect: true,
                      enableSuggestions: true,
                      smartDashesType: SmartDashesType.enabled,
                      smartQuotesType: SmartQuotesType.enabled,
                      decoration: InputDecoration(labelText: l.t('task_name')),
                    ),
                    const SizedBox(height: 12),
                    TimePickTile(
                      label: l.t('start_time_optional'),
                      value: start,
                      onTap: pickStart,
                      onClear: start.isEmpty
                          ? null
                          : () => setLocalState(() => start = ''),
                    ),
                    const SizedBox(height: 12),
                    TimePickTile(
                      label: l.t('end_time_optional'),
                      value: end,
                      onTap: pickEnd,
                      onClear: end.isEmpty
                          ? null
                          : () => setLocalState(() => end = ''),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(l.t('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('today'),
                  child: Text(l.t('save_today')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('specific'),
                  child: Text(l.language == AppLanguage.tr
                      ? 'Belirli günler'
                      : 'Specific days'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop('all'),
                  child: Text(l.t('save_every_day')),
                ),
              ],
            );
          },
        ),
      );

      if (scope == 'all') {
        await repo.renameTask(
          id,
          c.text,
          startTime: start,
          endTime: end,
          weekdays: null,
        );
      } else if (scope == 'today') {
        await repo.cloneTaskForOnlyThatDay(
          day: _selectedDate,
          sourceTaskId: id,
          newName: c.text,
          startTime: start,
          endTime: end,
        );
      } else if (scope == 'specific') {
        final initialDays = repo.taskWeekdaysOrAll(task);
        final pickedDays = await askSpecificDays(initialDays);
        if (pickedDays == null || pickedDays.isEmpty) return;

        await repo.updateTaskForSpecificDays(
          id,
          weekdays: pickedDays,
          newName: c.text,
          startTime: start,
          endTime: end,
        );
      } else {
        return;
      }

      if (!mounted) return;
      setState(() {});
      widget.onDataChanged();
    }

    Future<void> deleteDialog() async {
      final scope = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.t('delete_type')),
          content: Text(
            l.language == AppLanguage.tr
                ? 'Bugün, belirli günler veya her gün için silmek istiyor musun?'
                : 'Delete for today, specific days, or every day?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l.t('dismiss')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('today'),
              child: Text(l.t('delete_today')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('specific'),
              child: Text(l.language == AppLanguage.tr
                  ? 'Belirli günler'
                  : 'Specific days'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('all'),
              child: Text(l.t('delete_every_day')),
            ),
          ],
        ),
      );

      if (scope == 'today') {
        await repo.hideTaskForDay(_selectedDate, id, true);
        await repo.removeLogForTaskOnDate(_selectedDate, id);
      } else if (scope == 'specific') {
        final initialDays = repo.taskWeekdaysOrAll(task);
        final pickedDays = await askSpecificDays(initialDays);
        if (pickedDays == null || pickedDays.isEmpty) return;

        await repo.deleteTaskSpecificDays(id, pickedDays);
      } else if (scope == 'all') {
        await repo.archiveTask(id);
      } else {
        return;
      }

      if (!mounted) return;
      setState(() {});
      widget.onDataChanged();
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(humanDate(_selectedDate)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l.t('edit')),
              subtitle: Text(
                l.language == AppLanguage.tr
                    ? 'Bugün / Belirli günler / Her gün'
                    : 'Today / Specific days / Every day',
              ),
              onTap: () async {
                Navigator.pop(context);
                await editDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(l.t('move_up')),
              subtitle: Text(
                l.language == AppLanguage.tr
                    ? 'Sadece bugün için'
                    : 'Only for today',
              ),
              onTap: () async {
                Navigator.pop(context);
                await repo.moveTaskForDay(_selectedDate, id, up: true);
                if (!mounted) return;
                setState(() {});
                widget.onDataChanged();
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: Text(l.t('move_down')),
              subtitle: Text(
                l.language == AppLanguage.tr
                    ? 'Sadece bugün için'
                    : 'Only for today',
              ),
              onTap: () async {
                Navigator.pop(context);
                await repo.moveTaskForDay(_selectedDate, id, up: false);
                if (!mounted) return;
                setState(() {});
                widget.onDataChanged();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l.t('delete')),
              subtitle: Text(
                l.language == AppLanguage.tr
                    ? 'Bugün / Belirli günler / Her gün'
                    : 'Today / Specific days / Every day',
              ),
              onTap: () async {
                Navigator.pop(context);
                await deleteDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.initialDate, widget.initialDate)) {
      _selectedDate = dateOnly(widget.initialDate);
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 2, 1, 1),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked != null) {
      final d = dateOnly(picked);
      setState(() => _selectedDate = d);
      widget.onDatePicked(d);
      widget.onDataChanged();
    }
  }

  Future<void> _showAddTaskMenu() async {
    final l = L(repo.language());

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task),
              title: Text(l.t('create_new_task')),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _showCreateTaskDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.t('add_from_archive')),
              subtitle: Text(l.t('pick_from_archive_sub')),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _showArchivedPicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateTaskDialog() async {
    final l = L(repo.language());
    final name = TextEditingController();
    String start = '';
    String end = '';
    AddTaskScope scope = AddTaskScope.everyDay;
    final selectedDays = <int>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          Future<void> pickStart() async {
            final res = await showHmPicker(ctx, initialValue: start);
            if (res != null) setLocalState(() => start = res);
          }

          Future<void> pickEnd() async {
            final res = await showHmPicker(ctx, initialValue: end);
            if (res != null) setLocalState(() => end = res);
          }

          return AlertDialog(
            title: Text(l.t('new_task')),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    autocorrect: true,
                    enableSuggestions: true,
                    smartDashesType: SmartDashesType.enabled,
                    smartQuotesType: SmartQuotesType.enabled,
                    decoration: InputDecoration(labelText: l.t('task_name')),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AddTaskScope>(
                    segments: [
                      ButtonSegment(
                        value: AddTaskScope.everyDay,
                        label: Text(l.t('scope_every_day')),
                      ),
                      ButtonSegment(
                        value: AddTaskScope.todayOnly,
                        label: Text(l.t('scope_today_only')),
                      ),
                      ButtonSegment(
                        value: AddTaskScope.specificDays,
                        label: Text(l.t('scope_specific_days')),
                      ),
                    ],
                    selected: {scope},
                    onSelectionChanged: (v) {
                      setLocalState(() => scope = v.first);
                    },
                  ),
                  if (scope == AddTaskScope.specificDays) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l.t('select_days'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        final selected = selectedDays.contains(day);
                        return FilterChip(
                          label: Text(weekdayNameShort(day, l.language)),
                          selected: selected,
                          onSelected: (v) {
                            setLocalState(() {
                              if (v) {
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TimePickTile(
                    label: l.t('start_time_optional'),
                    value: start,
                    onTap: pickStart,
                    onClear: start.isEmpty
                        ? null
                        : () => setLocalState(() => start = ''),
                  ),
                  const SizedBox(height: 12),
                  TimePickTile(
                    label: l.t('end_time_optional'),
                    value: end,
                    onTap: pickEnd,
                    onClear: end.isEmpty
                        ? null
                        : () => setLocalState(() => end = ''),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.t('save')),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      if (scope == AddTaskScope.everyDay) {
        await repo.addTask(
          name.text,
          startTime: start,
          endTime: end,
          validFrom: _selectedDate,
        );
      } else if (scope == AddTaskScope.todayOnly) {
        await repo.addTask(
          name.text,
          startTime: start,
          endTime: end,
          validFrom: _selectedDate,
          validTo: _selectedDate,
        );
      } else {
        await repo.addTask(
          name.text,
          startTime: start,
          endTime: end,
          validFrom: _selectedDate,
          weekdays: selectedDays.toList(),
        );
      }

      if (!mounted) return;
      setState(() {});
      widget.onDataChanged();
    }
  }

  Future<void> _showArchivedPicker() async {
    final l = L(repo.language());
    final archived = repo.archivedTasks();

    if (archived.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('no_archive_task'))),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.70,
          child: ListView.separated(
            itemCount: archived.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = archived[i];
              final id = t['id'] as String;
              final name = t['name'] as String;
              final time = taskTimeText(t);

              return ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (time != null) Text(time),
                    Text(
                      weekdaysText(
                        (t['weekdays'] as List?)?.whereType<int>().toList(),
                        l.language,
                      ),
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    Navigator.of(ctx).pop();
                    if (v == 'day') {
                      await repo.addArchivedTaskForOnlyThatDay(
                        day: _selectedDate,
                        sourceTaskId: id,
                      );
                    } else if (v == 'all') {
                      await repo.restoreTaskFromArchiveAsNew(id);
                    }
                    if (!mounted) return;
                    setState(() {});
                    widget.onDataChanged();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'day',
                      child: Text(l.language == AppLanguage.tr
                          ? 'Sadece bu güne ekle'
                          : 'Add only for this day'),
                    ),
                    PopupMenuItem(
                      value: 'all',
                      child: Text(l.language == AppLanguage.tr
                          ? 'Her güne geri al'
                          : 'Restore for every day'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _maybeShowSeriBrokenDialogIfNeeded() async {
    final l = L(repo.language());
    final today = dateOnly(DateTime.now());
    if (!repo.isPerfectDay(today)) return;

    final yesterday = today.subtract(const Duration(days: 1));
    if (repo.isPerfectDay(yesterday)) return;

    final ui = repo.getUiState();
    final lastShown = ui[kUiLastBreakShown] as String?;
    final todayKey = dateKey(today);
    if (lastShown == todayKey) return;

    await repo.setUiValue(kUiLastBreakShown, todayKey);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('streak_broken')),
        content: Text(
          '${l.t("streak_broken_msg")}\n\n${l.t("best_streak")}: ${repo.longestSeri()}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.t('continue')),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeConfettiIfPerfectToday() async {
    final d = dateOnly(_selectedDate);
    final dk = dateKey(d);
    if (!repo.isPerfectDay(d)) return;
    if (repo.lastConfettiKey() == dk) return;

    await repo.setUiValue(kUiLastConfetti, dk);
    _confetti.play();
  }

  Widget _buildSummaryPanel(BuildContext context) {
    final l = L(repo.language());
    final cs = Theme.of(context).colorScheme;
    final total = repo.totalCountForDate(_selectedDate);
    final done = repo.completedCountForDate(_selectedDate);
    final ratio = repo.ratioForDate(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftCard(
          child: Row(
            children: [
              const AntoryLogo(size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.t('app_name'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              IconButton(
                tooltip: l.t('date_pick'),
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      humanDate(_selectedDate),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${l.t("completed_count")}: $done / $total',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Pill(
                          icon: Icons.local_fire_department,
                          label: '${l.t("streak")}: ${repo.currentSeri()}',
                          tone: cs.primary,
                        ),
                        Pill(
                          icon: Icons.emoji_events,
                          label: '${l.t("best_streak")}: ${repo.longestSeri()}',
                          tone: cs.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ProgressRing(
                percent: ratio,
                color: ratio >= 1.0 ? cs.primary : cs.tertiary,
                size: 92,
                label: '${(ratio * 100).round()}%',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(BuildContext context) {
    final l = L(repo.language());
    final validTasks = repo.tasksForDate(_selectedDate);
    final logs = repo.logsForDate(_selectedDate);

    if (validTasks.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 20),
          Center(child: Text(l.t('no_task_for_date'))),
        ],
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: validTasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final task = validTasks[i];
        final id = task['id'] as String;
        final name = task['name'] as String;
        final isDone = logs[id] == true;
        final timeText = taskTimeText(task);

        return TaskTile(
          name: name,
          done: isDone,
          timeText: timeText,
          doneLabel: l.t('completed'),
          onChanged: (v) async {
            await repo.setDone(_selectedDate, id, v ?? false);
            if (!mounted) return;
            setState(() {});
            widget.onDataChanged();
            await _maybeConfettiIfPerfectToday();
          },
          onLongPress: () => _showTaskActionsSheet(task),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());
    final orientation = MediaQuery.of(context).orientation;
    final summary = _buildSummaryPanel(context);
    final taskList = _buildTaskList(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('today')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskMenu,
        icon: const Icon(Icons.add),
        label: Text(l.t('add_task')),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: orientation == Orientation.portrait
                ? Column(
                    children: [
                      summary,
                      const SizedBox(height: 14),
                      Expanded(child: taskList),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 11,
                        child: SingleChildScrollView(child: summary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 12,
                        child: taskList,
                      ),
                    ],
                  ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirectionality: BlastDirectionality.explosive,
                  numberOfParticles: 28,
                  gravity: 0.25,
                  emissionFrequency: 0.03,
                  shouldLoop: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// calendar
/// ------------------------------------------------------------

class CalendarScreen extends StatefulWidget {
  final Repo repo;
  final DateTime initialSelectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const CalendarScreen({
    super.key,
    required this.repo,
    required this.initialSelectedDate,
    required this.onDateSelected,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Repo get repo => widget.repo;

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(widget.initialSelectedDate);
    _focusedDay = _selectedDay;
  }

  Color _tierColor(double ratio, ColorScheme cs) {
    if (ratio >= 0.80) return cs.primary;
    if (ratio >= 0.60) return cs.tertiary;
    if (ratio >= 0.40) return cs.secondary;
    if (ratio >= 0.20) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('calendar'))),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _format,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onFormatChanged: (format) => setState(() => _format = format),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = dateOnly(selectedDay);
                _focusedDay = dateOnly(focusedDay);
              });
              widget.onDateSelected(_selectedDay);
            },
            onPageChanged: (focusedDay) =>
                setState(() => _focusedDay = dateOnly(focusedDay)),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) {
                final r = repo.ratioForDate(dateOnly(day));
                return _dayCell(day, _tierColor(r, cs), cs, false,
                    selected: false);
              },
              todayBuilder: (context, day, _) {
                final r = repo.ratioForDate(dateOnly(day));
                return _dayCell(day, _tierColor(r, cs), cs, true,
                    selected: false);
              },
              selectedBuilder: (context, day, _) {
                final r = repo.ratioForDate(dateOnly(day));
                return _dayCell(day, _tierColor(r, cs), cs, true,
                    selected: true);
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LegendRow(lang: l),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, Color color, ColorScheme cs, bool outlined,
      {required bool selected}) {
    final perfect = repo.isPerfectDay(dateOnly(day));

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: outlined
            ? Border.all(
                color: selected ? cs.onSurface : cs.outlineVariant,
                width: selected ? 2 : 1,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${day.day}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900),
          ),
          if (perfect)
            const Positioned(
              bottom: 2,
              right: 2,
              child: Icon(Icons.local_fire_department,
                  size: 12, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class LegendRow extends StatelessWidget {
  final L lang;
  const LegendRow({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(Colors.red.shade700),
          const SizedBox(width: 6),
          const Text('0–19%')
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(Colors.orange.shade700),
          const SizedBox(width: 6),
          const Text('20–39%')
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(Colors.green.shade400),
          const SizedBox(width: 6),
          const Text('40–59%')
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(Colors.green.shade700),
          const SizedBox(width: 6),
          const Text('60–79%')
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(Colors.green.shade900),
          const SizedBox(width: 6),
          const Text('80–100%')
        ]),
      ],
    );
  }
}

/// ------------------------------------------------------------
/// tasks
/// ------------------------------------------------------------
class TaskTile extends StatelessWidget {
  final String name;
  final bool done;
  final String? timeText;
  final String doneLabel;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onLongPress;

  const TaskTile({
    super.key,
    required this.name,
    required this.done,
    required this.timeText,
    required this.doneLabel,
    required this.onChanged,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseA =
        done ? cs.primary.withOpacity(isDark ? 0.28 : 0.14) : cs.surface;
    final baseB = done
        ? cs.tertiary.withOpacity(isDark ? 0.20 : 0.10)
        : cs.surfaceContainerHighest.withOpacity(isDark ? 0.20 : 0.60);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseA, baseB],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: done
              ? cs.primary.withOpacity(0.35)
              : cs.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: ListTile(
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: timeText == null
            ? (done
                ? Text(doneLabel,
                    style: TextStyle(
                        color: cs.primary, fontWeight: FontWeight.w700))
                : null)
            : Text(
                done ? '$timeText  •  $doneLabel' : timeText!,
                style: TextStyle(
                  color: done ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
        trailing: Checkbox(
          value: done,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class TasksScreen extends StatefulWidget {
  final Repo repo;
  final VoidCallback onDataChanged;

  const TasksScreen({
    super.key,
    required this.repo,
    required this.onDataChanged,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  Repo get repo => widget.repo;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final l = L(repo.language());
    final c = TextEditingController(text: task['name'] as String);
    String start = (task['start_time'] as String?) ?? '';
    String end = (task['end_time'] as String?) ?? '';
    final selectedDays =
        ((task['weekdays'] as List?)?.whereType<int>().toSet()) ?? <int>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          Future<void> pickStart() async {
            final res = await showHmPicker(ctx, initialValue: start);
            if (res != null) setLocalState(() => start = res);
          }

          Future<void> pickEnd() async {
            final res = await showHmPicker(ctx, initialValue: end);
            if (res != null) setLocalState(() => end = res);
          }

          return AlertDialog(
            title: Text(l.t('edit')),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: c,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    autocorrect: true,
                    enableSuggestions: true,
                    smartDashesType: SmartDashesType.enabled,
                    smartQuotesType: SmartQuotesType.enabled,
                    decoration: InputDecoration(labelText: l.t('task_name')),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (index) {
                      final day = index + 1;
                      final selected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(weekdayNameShort(day, l.language)),
                        selected: selected,
                        onSelected: (v) {
                          setLocalState(() {
                            if (v) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TimePickTile(
                    label: l.t('start_time_optional'),
                    value: start,
                    onTap: pickStart,
                    onClear: start.isEmpty
                        ? null
                        : () => setLocalState(() => start = ''),
                  ),
                  const SizedBox(height: 12),
                  TimePickTile(
                    label: l.t('end_time_optional'),
                    value: end,
                    onTap: pickEnd,
                    onClear: end.isEmpty
                        ? null
                        : () => setLocalState(() => end = ''),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.t('save')),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      await repo.renameTask(
        task['id'] as String,
        c.text,
        startTime: start,
        endTime: end,
        weekdays: selectedDays.toList(),
      );
      if (mounted) setState(() {});
    }
    if (ok == true) {
      await repo.renameTask(
        task['id'] as String,
        c.text,
        startTime: start,
        endTime: end,
        weekdays: selectedDays.toList(),
      );
      if (mounted) {
        setState(() {});
        widget.onDataChanged();
      }
    }
    if (mounted) {
      setState(() {});
      widget.onDataChanged();
    }
  }

  Future<void> _confirm(
    String title,
    String msg,
    Future<void> Function() action,
  ) async {
    final l = L(repo.language());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.t('dismiss')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.t('confirm')),
          ),
        ],
      ),
    );

    if (ok == true) {
      await action();
      if (mounted) {
        setState(() {});
        widget.onDataChanged();
      }
    }
    if (ok == true) {
      await action();
      if (mounted) {
        setState(() {});
        widget.onDataChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());
    final tasks = repo.getAllTasks();
    final active = tasks.where((t) => !taskIsArchived(t)).toList();
    final archived = tasks.where((t) => taskIsArchived(t)).toList();

    Widget row(Map<String, dynamic> t, bool isArchived) {
      final id = t['id'] as String;
      final name = t['name'] as String;
      final from = t['valid_from'] as String? ?? '-';
      final to = t['valid_to'] as String?;
      final time = taskTimeText(t);
      final daysText = weekdaysText(
        (t['weekdays'] as List?)?.whereType<int>().toList(),
        l.language,
      );

      return SoftCard(
        child: ListTile(
          title:
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            isArchived
                ? '${l.t("archive")}: $from → ${to ?? "-"}${time == null ? "" : "\n$time"}\n$daysText'
                : '${l.t("active")}: $from → (devam)${time == null ? "" : "\n$time"}\n$daysText',
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editTask(t),
              ),
              if (!isArchived)
                IconButton(
                  icon: const Icon(Icons.archive),
                  onPressed: () => _confirm(
                    l.t('archive'),
                    l.language == AppLanguage.tr
                        ? '"$name" bugünden itibaren arşivlenecek.'
                        : '"$name" will be archived from today.',
                    () => repo.archiveTask(id),
                  ),
                ),
              if (isArchived)
                IconButton(
                  icon: const Icon(Icons.unarchive),
                  onPressed: () => _confirm(
                    l.t('unarchive'),
                    l.language == AppLanguage.tr
                        ? '"$name" yeniden aktif edilsin mi?'
                        : 'Restore "$name" to active tasks?',
                    () => repo.restoreTask(id),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_forever),
                onPressed: () => _confirm(
                  l.t('delete_forever'),
                  l.language == AppLanguage.tr
                      ? '"$name" kalıcı silinecek.'
                      : '"$name" will be deleted permanently.',
                  () => repo.deleteTaskPermanently(id),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('tasks')),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l.t('active')),
            Tab(text: l.t('archive')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          active.isEmpty
              ? Center(child: Text(l.t('no_active_task')))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: active.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: row(active[i], false),
                  ),
                ),
          archived.isEmpty
              ? Center(child: Text(l.t('no_archive_task')))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: archived.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: row(archived[i], true),
                  ),
                ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// analytics
/// ------------------------------------------------------------

enum AnalyticsMode { daily, weekly, monthly }

class AnalyticsScreen extends StatefulWidget {
  final Repo repo;
  const AnalyticsScreen({super.key, required this.repo});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Repo get repo => widget.repo;

  AnalyticsMode _mode = AnalyticsMode.weekly;
  DateTime _anchor = dateOnly(DateTime.now());

  DateTime _startOfWeek(DateTime d) {
    final dd = dateOnly(d);
    final diff = dd.weekday - DateTime.monday;
    return dd.subtract(Duration(days: diff));
  }

  DateTimeRange _rangeForAnchor() {
    final a = dateOnly(_anchor);
    if (_mode == AnalyticsMode.daily) {
      return DateTimeRange(start: a, end: a);
    }
    if (_mode == AnalyticsMode.weekly) {
      final s = _startOfWeek(a);
      return DateTimeRange(start: s, end: s.add(const Duration(days: 6)));
    }
    final s = DateTime(a.year, a.month, 1);
    final e = DateTime(a.year, a.month + 1, 0);
    return DateTimeRange(start: s, end: e);
  }

  List<DateTime> _daysInRange(DateTimeRange r) {
    final days = <DateTime>[];
    DateTime cur = dateOnly(r.start);
    final end = dateOnly(r.end);
    while (!cur.isAfter(end)) {
      days.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return days;
  }

  void _prev() => setState(() {
        if (_mode == AnalyticsMode.daily) {
          _anchor = _anchor.subtract(const Duration(days: 1));
        } else if (_mode == AnalyticsMode.weekly) {
          _anchor = _anchor.subtract(const Duration(days: 7));
        } else {
          _anchor = DateTime(_anchor.year, _anchor.month - 1, 1);
        }
      });

  void _next() => setState(() {
        if (_mode == AnalyticsMode.daily) {
          _anchor = _anchor.add(const Duration(days: 1));
        } else if (_mode == AnalyticsMode.weekly) {
          _anchor = _anchor.add(const Duration(days: 7));
        } else {
          _anchor = DateTime(_anchor.year, _anchor.month + 1, 1);
        }
      });

  void _today() => setState(() => _anchor = dateOnly(DateTime.now()));

  String _title(DateTimeRange r, L l) {
    if (_mode == AnalyticsMode.daily) {
      return '${l.t("today_label")}: ${humanDate(r.start)}';
    }
    if (_mode == AnalyticsMode.weekly) {
      return '${l.t("week_label")}: ${humanDate(r.start)} - ${humanDate(r.end)}';
    }
    return '${l.t("month_label")}: ${r.start.month.toString().padLeft(2, '0')}.${r.start.year}';
  }

  Color _tierColor(double ratio, ColorScheme cs) {
    if (ratio >= 0.80) return cs.primary;
    if (ratio >= 0.60) return cs.tertiary;
    if (ratio >= 0.40) return cs.secondary;
    if (ratio >= 0.20) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final l = L(repo.language());
    final cs = Theme.of(context).colorScheme;
    final orientation = MediaQuery.of(context).orientation;
    final range = _rangeForAnchor();
    final days = _daysInRange(range);

    final ratios = days.map((d) => repo.ratioForDate(d)).toList();
    final avg =
        ratios.isEmpty ? 0.0 : ratios.reduce((a, b) => a + b) / ratios.length;

    int totalTasks = 0, doneTasks = 0, daysAbove = 0, daysBelow = 0;
    final target = repo.targetRatio();

    for (final d in days) {
      final tot = repo.totalCountForDate(d);
      final dn = repo.completedCountForDate(d);
      totalTasks += tot;
      doneTasks += dn;
      if (tot > 0) {
        if (dn / tot >= target) {
          daysAbove++;
        } else {
          daysBelow++;
        }
      }
    }

    final remaining = max(0, totalTasks - doneTasks);

    final tasks = repo.getAllTasks();
    final activeInRange =
        tasks.where((t) => days.any((d) => taskIsValidOn(t, d))).toList();

    final stats = <_TaskStat>[];
    for (final t in activeInRange) {
      final id = t['id'] as String;
      final name = t['name'] as String;
      int validDays = 0, doneDays = 0;
      for (final d in days) {
        if (!taskIsValidOn(t, d)) continue;
        validDays++;
        if (repo.isTaskDone(d, id)) doneDays++;
      }
      if (validDays > 0) {
        stats.add(
            _TaskStat(name: name, validDays: validDays, doneDays: doneDays));
      }
    }
    stats.sort((a, b) => a.rate.compareTo(b.rate));
    final weakest3 = stats.take(3).toList();

    final sum = List<double>.filled(7, 0);
    final cnt = List<int>.filled(7, 0);
    for (final d in days) {
      final tot = repo.totalCountForDate(d);
      if (tot == 0) continue;
      final idx = d.weekday - 1;
      sum[idx] += repo.ratioForDate(d);
      cnt[idx] += 1;
    }
    final weekdayAvg =
        List<double>.generate(7, (i) => cnt[i] == 0 ? 0 : sum[i] / cnt[i]);

    final weekdayNames = [
      l.t('monday_short'),
      l.t('tuesday_short'),
      l.t('wednesday_short'),
      l.t('thursday_short'),
      l.t('friday_short'),
      l.t('saturday_short'),
      l.t('sunday_short'),
    ];

    Widget kpiArea = orientation == Orientation.portrait
        ? Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: KpiCard(
                          title: l.t('average'),
                          value: '${(avg * 100).round()}%')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: KpiCard(
                          title: l.t('total'),
                          value:
                              '$totalTasks\n${l.t("completed_count")}: $doneTasks')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: KpiCard(
                          title: l.t('target'),
                          value: '${(target * 100).round()}%')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: KpiCard(
                          title: l.t('above_below'),
                          value: '$daysAbove / $daysBelow')),
                ],
              ),
            ],
          )
        : Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                  width: 220,
                  child: KpiCard(
                      title: l.t('average'), value: '${(avg * 100).round()}%')),
              SizedBox(
                  width: 220,
                  child: KpiCard(
                      title: l.t('total'),
                      value:
                          '$totalTasks\n${l.t("completed_count")}: $doneTasks')),
              SizedBox(
                  width: 220,
                  child: KpiCard(
                      title: l.t('target'),
                      value: '${(target * 100).round()}%')),
              SizedBox(
                  width: 220,
                  child: KpiCard(
                      title: l.t('above_below'),
                      value: '$daysAbove / $daysBelow')),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('analytics'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                        onPressed: _prev, icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: Center(
                        child: Text(
                          _title(range, l),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    IconButton(
                        onPressed: _next,
                        icon: const Icon(Icons.chevron_right)),
                    TextButton.icon(
                      onPressed: _today,
                      icon: const Icon(Icons.today),
                      label: Text(l.t('today')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<AnalyticsMode>(
                  segments: [
                    ButtonSegment(
                        value: AnalyticsMode.daily,
                        label: Text(l.t('daily')),
                        icon: const Icon(Icons.today)),
                    ButtonSegment(
                        value: AnalyticsMode.weekly,
                        label: Text(l.t('weekly')),
                        icon: const Icon(Icons.view_week)),
                    ButtonSegment(
                        value: AnalyticsMode.monthly,
                        label: Text(l.t('monthly')),
                        icon: const Icon(Icons.calendar_view_month)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          kpiArea,
          const SizedBox(height: 18),
          Text(l.t('daily_trend'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SoftCard(
            child: SizedBox(
              height: 240,
              child: LineChartPercent(days: days, ratios: ratios),
            ),
          ),
          const SizedBox(height: 18),
          Text(l.t('pie_chart'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SoftCard(
            child: PieChartBox(
              done: doneTasks,
              remaining: remaining,
              completedLabel: l.t('done_label'),
              remainingLabel: l.t('remaining_label'),
            ),
          ),
          const SizedBox(height: 18),
          Text(l.t('task_success'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SoftCard(
            child: stats.isEmpty
                ? Text(l.t('no_data'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (weakest3.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.warning_amber, size: 18),
                            const SizedBox(width: 6),
                            Text(l.t('weakest_3'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final s in weakest3)
                          TaskStatRow(
                            name: s.name,
                            done: s.doneDays,
                            total: s.validDays,
                            color: _tierColor(s.rate, cs),
                          ),
                        const Divider(height: 24),
                      ],
                      Text(l.t('all'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      for (final s in stats.reversed)
                        TaskStatRow(
                          name: s.name,
                          done: s.doneDays,
                          total: s.validDays,
                          color: _tierColor(s.rate, cs),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          Text(l.t('weekday'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SoftCard(
            child: Column(
              children: List.generate(7, (i) {
                final v = weekdayAvg[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(weekdayNames[i],
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: v.clamp(0, 1),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(999),
                          backgroundColor: cs.outlineVariant.withOpacity(0.35),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_tierColor(v, cs)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 44, child: Text('${(v * 100).round()}%')),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskStat {
  final String name;
  final int validDays;
  final int doneDays;
  _TaskStat(
      {required this.name, required this.validDays, required this.doneDays});

  double get rate => validDays == 0 ? 0 : doneDays / validDays;
}

/// ------------------------------------------------------------
/// widgets
/// ------------------------------------------------------------

class SoftCard extends StatelessWidget {
  final Widget child;
  const SoftCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF19211C) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(isDark ? 0.25 : 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.28)
                : cs.primary.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark
                ? Colors.white.withOpacity(0.02)
                : Colors.white.withOpacity(0.85),
            blurRadius: 2,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class FancyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const FancyButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? [
                  cs.primary.withOpacity(isDark ? 0.88 : 0.95),
                  cs.secondary.withOpacity(isDark ? 0.74 : 0.82),
                ]
              : [cs.surfaceContainerHighest, cs.surfaceContainerHighest],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: cs.primary.withOpacity(isDark ? 0.22 : 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: enabled ? cs.onPrimary : cs.onSurfaceVariant,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class AddTaskBottomCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AddTaskBottomCard({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;

  const Pill({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final double percent;
  final double size;
  final Color color;
  final String label;

  const ProgressRing({
    super.key,
    required this.percent,
    required this.size,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = percent.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 10,
            valueColor: AlwaysStoppedAnimation<Color>(
              cs.outlineVariant.withOpacity(0.35),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) {
              return CircularProgressIndicator(
                value: v,
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              );
            },
          ),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  const KpiCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class TaskStatRow extends StatelessWidget {
  final String name;
  final int done;
  final int total;
  final Color color;

  const TaskStatRow({
    super.key,
    required this.name,
    required this.done,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
              width: 60,
              child: Text('$done/$total', textAlign: TextAlign.right)),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: LinearProgressIndicator(
              value: v.clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withOpacity(0.35),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class TimePickTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const TimePickTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasValue)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.schedule),
              ),
            ],
          ),
        ),
        child: Text(hasValue ? value : '--:--'),
      ),
    );
  }
}

class LineChartPercent extends StatelessWidget {
  final List<DateTime> days;
  final List<double> ratios;

  const LineChartPercent({
    super.key,
    required this.days,
    required this.ratios,
  });

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Center(child: Text('No data'));

    final spots = <FlSpot>[];
    for (int i = 0; i < ratios.length; i++) {
      spots.add(FlSpot(i.toDouble(), ratios[i] * 100));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: 20,
              getTitlesWidget: (v, _) => Text('${v.toInt()}'),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: max(1, (days.length / 6).floor()).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Text('${days[i].day}');
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            dotData: const FlDotData(show: true),
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
        borderData: FlBorderData(show: true),
      ),
    );
  }
}

class PieChartBox extends StatelessWidget {
  final int done;
  final int remaining;
  final String completedLabel;
  final String remainingLabel;

  const PieChartBox({
    super.key,
    required this.done,
    required this.remaining,
    required this.completedLabel,
    required this.remainingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = max(1, done + remaining);
    final donePct = (done / total) * 100;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final doneColor = cs.primary;
    final remainingColor =
        isDark ? cs.surfaceContainerHighest : cs.secondaryContainer;

    return SizedBox(
      height: 180,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 28,
                    sectionsSpace: 3,
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(
                        value: done.toDouble(),
                        title: '',
                        radius: 22,
                        color: doneColor,
                      ),
                      PieChartSectionData(
                        value: remaining.toDouble(),
                        title: '',
                        radius: 22,
                        color: remainingColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: doneColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$completedLabel: $done',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: remainingColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$remainingLabel: $remaining',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Tamamlama: ${donePct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
echo "# antory" >> README.md 
git init 
git add README.md 
git commit -m "first commit" 
git branch -M main 
git remote add origin https://github.com/blaknodscompany-cloud/antory.git
 git push -u origin main