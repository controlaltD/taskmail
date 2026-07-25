class Board {
  final String id;
  final String userId;
  final String name;
  final bool isDefault;
  final DateTime createdAt;

  const Board({
    required this.id,
    required this.userId,
    required this.name,
    this.isDefault = false,
    required this.createdAt,
  });

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String? ?? 'Saját feladatok',
        isDefault: json['is_default'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'name': name,
        'is_default': isDefault,
      };
}
