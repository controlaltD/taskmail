class TaskComment {
  final int id;
  final String user;
  final String text;
  final String time;

  const TaskComment({required this.id, required this.user, required this.text, required this.time});

  factory TaskComment.fromJson(Map<String, dynamic> json) => TaskComment(
        id: json['id'] as int,
        user: json['user'] as String? ?? '',
        text: json['text'] as String? ?? '',
        time: json['time'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'user': user, 'text': text, 'time': time};
}
