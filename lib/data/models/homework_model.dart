// lib/data/models/homework_model.dart

class HomeworkModel {
  final String lessonId;
  final String discipline;
  final String date; // "2026-04-20"
  final String? serverText; // from portal (teacher posted)
  String? localText;        // user's own note
  List<String> localFilePaths;
  bool isLocalOverwrite;
  DateTime? deadline;        // user-set deadline for notifications

  HomeworkModel({
    required this.lessonId,
    required this.discipline,
    required this.date,
    this.serverText,
    this.localText,
    this.localFilePaths = const [],
    this.isLocalOverwrite = false,
    this.deadline,
  });

  /// What to show in UI — prefers local if overwritten, else server
  String get effectiveText {
    if (isLocalOverwrite && localText != null && localText!.isNotEmpty) return localText!;
    return serverText ?? '';
  }

  bool get isEmpty => effectiveText.trim().isEmpty;
  bool get hasServerHomework => serverText != null && serverText!.isNotEmpty;

  /// Days until deadline (negative = overdue)
  int? get daysUntilDeadline {
    if (deadline == null) return null;
    final now = DateTime.now();
    final d = DateTime(deadline!.year, deadline!.month, deadline!.day);
    final today = DateTime(now.year, now.month, now.day);
    return d.difference(today).inDays;
  }

  bool get isHot {
    final d = daysUntilDeadline;
    return d != null && d <= 2 && d >= 0;
  }

  bool get isOverdue {
    final d = daysUntilDeadline;
    return d != null && d < 0;
  }

  factory HomeworkModel.fromJson(
      Map<String, dynamic> j, String lessonId, String discipline, String date) =>
      HomeworkModel(
        lessonId: lessonId,
        discipline: discipline,
        date: date,
        serverText: (j['text'] ?? j['task'] ?? j['homework'] ?? '').toString().nullIfEmpty,
      );

  Map<String, dynamic> toLocalJson() => {
    'lessonId': lessonId,
    'discipline': discipline,
    'date': date,
    'localText': localText,
    'localFilePaths': localFilePaths.join('|||'),
    'isLocalOverwrite': isLocalOverwrite ? 1 : 0,
    'deadline': deadline?.toIso8601String(),
  };

  factory HomeworkModel.fromLocalJson(Map<String, dynamic> j) => HomeworkModel(
    lessonId: j['lessonId'] ?? '',
    discipline: j['discipline'] ?? '',
    date: j['date'] ?? '',
    localText: j['localText'] as String?,
    localFilePaths: (j['localFilePaths'] as String?)
            ?.split('|||')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [],
    isLocalOverwrite: (j['isLocalOverwrite'] ?? 0) == 1,
    deadline: j['deadline'] != null
        ? DateTime.tryParse(j['deadline'] as String)
        : null,
  );
}

extension _StrNull on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
