class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.bio,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        username: map['username'] as String,
        fullName: (map['full_name'] ?? '') as String,
        avatarUrl: map['avatar_url'] as String?,
        bio: map['bio'] as String?,
      );
}
