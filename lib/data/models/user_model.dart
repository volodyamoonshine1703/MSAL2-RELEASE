// lib/data/models/user_model.dart

class UserModel {
  final String id;
  final String login;
  final String username;   // e.g. "sc1234567"
  final String name;
  final String email;
  final String emailCorporate;
  final List<String> phones;
  final String speciality;
  final String department;
  final String departmentId;
  final String group;
  final String groupId;
  final String role;
  final String subrole;    // "COLLEGE" | "UNIVERSITY"
  final String? photoPath; // relative path: "static/students/xxx.jpg"
  final int course;
  final int semester;
  // Server-side privacy settings
  final bool showEmail;
  final bool showPhoto;
  final bool showMobile;

  const UserModel({
    required this.id,
    required this.login,
    required this.username,
    required this.name,
    required this.email,
    required this.emailCorporate,
    required this.phones,
    required this.speciality,
    required this.department,
    required this.departmentId,
    required this.group,
    required this.groupId,
    required this.role,
    required this.subrole,
    this.photoPath,
    required this.course,
    required this.semester,
    required this.showEmail,
    required this.showPhoto,
    required this.showMobile,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) {
    final access = j['access'] as Map<String, dynamic>? ?? {};
    return UserModel(
      id: (j['id'] ?? '').toString(),
      login: (j['login'] ?? '').toString(),
      username: (j['username'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      emailCorporate: (j['emailCorporate'] ?? '').toString(),
      phones: List<String>.from(j['phones'] ?? []),
      speciality: (j['speciality'] ?? '').toString(),
      department: (j['department'] ?? '').toString(),
      departmentId: (j['departmentID'] ?? j['departmentId'] ?? '').toString(),
      group: (j['group'] ?? '').toString(),
      groupId: (j['groupID'] ?? j['groupId'] ?? '').toString(),
      role: (j['role'] ?? 'student').toString(),
      subrole: (j['subrole'] ?? '').toString(),
      photoPath: j['photo'] as String?,
      course: (j['course'] as num?)?.toInt() ?? 1,
      semester: (j['semester'] as num?)?.toInt() ?? 1,
      // Server returns: access.email, access.photo, access.mobile
      showEmail: access['email'] as bool? ?? true,
      showPhoto: access['photo'] as bool? ?? true,
      showMobile: access['mobile'] as bool? ?? true,
    );
  }

  /// Full URL to profile photo
  String? get photoUrl {
    if (photoPath == null || photoPath!.isEmpty) return null;
    if (photoPath!.startsWith('http')) return photoPath;
    return 'https://lk.msal.ru:3443/$photoPath';
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }

  /// True if this is a college student (different API response structure)
  bool get isCollege => subrole.toUpperCase() == 'COLLEGE';

  /// True if this is a university/institute student
  bool get isInstitute => !isCollege;

  Map<String, dynamic> toJson() => {
    'id': id,
    'login': login,
    'username': username,
    'name': name,
    'email': email,
    'emailCorporate': emailCorporate,
    'phones': phones,
    'speciality': speciality,
    'department': department,
    'departmentID': departmentId,
    'group': group,
    'groupID': groupId,
    'role': role,
    'subrole': subrole,
    'photo': photoPath,
    'course': course,
    'semester': semester,
    'access': {'email': showEmail, 'photo': showPhoto, 'mobile': showMobile},
  };

  UserModel copyWith({bool? showEmail, bool? showPhoto, bool? showMobile}) =>
    UserModel(
      id: id, login: login, username: username, name: name,
      email: email, emailCorporate: emailCorporate, phones: phones,
      speciality: speciality, department: department, departmentId: departmentId,
      group: group, groupId: groupId, role: role, subrole: subrole,
      photoPath: photoPath, course: course, semester: semester,
      showEmail: showEmail ?? this.showEmail,
      showPhoto: showPhoto ?? this.showPhoto,
      showMobile: showMobile ?? this.showMobile,
    );
}
