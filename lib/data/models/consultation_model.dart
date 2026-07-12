// lib/data/models/consultation_model.dart

class ConsultationSlot {
  final Map<String, dynamic> raw;

  ConsultationSlot(this.raw);

  String get day => raw['day'] ?? '';
  String get between => raw['between'] ?? '';
  String get start => raw['start'] ?? '';
  String get startConsultation => raw['startConsultation'] ?? '';
  String get endConsultation => raw['endConsultation'] ?? '';
  bool get isFree => _bool(raw['free']);
  bool get isRecord => _bool(raw['record']);

  bool _bool(dynamic val) {
    if (val == true) return true;
    if (val == 'true' || val == '1') return true;
    if (val == 1) return true;
    return false;
  }
  String get teacherId => raw['teacher']?['id'] ?? '';
  String get teacherName => raw['teacher']?['name'] ?? '';
  String get corps => raw['corps'] ?? '';
  String get auditory => raw['auditory']?['name'] ?? '';
  String? get themeName => raw['theme']?['name'];
  String get disciplineName => raw['discipline']?['name'] ?? 'Консультация';
  String get disciplineId => raw['discipline']?['id'] ?? '';
}

class ConsultationTeacher {
  final String id;
  final String name;
  final String? rating;
  final List<String> reviews;

  ConsultationTeacher({
    required this.id, 
    required this.name,
    this.rating,
    this.reviews = const [],
  });

  factory ConsultationTeacher.fromJson(Map<String, dynamic> json) {
    return ConsultationTeacher(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      rating: json['rating'],
      reviews: (json['reviews'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  ConsultationTeacher copyWith({
    String? id,
    String? name,
    String? rating,
    List<String>? reviews,
  }) {
    return ConsultationTeacher(
      id: id ?? this.id,
      name: name ?? this.name,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsultationTeacher &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ConsultationTheme {
  final String id;
  final String name;

  ConsultationTheme({required this.id, required this.name});

  factory ConsultationTheme.fromJson(Map<String, dynamic> json) {
    return ConsultationTheme(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}
