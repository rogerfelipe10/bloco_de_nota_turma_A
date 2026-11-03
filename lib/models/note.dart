
class Note {
  final int? id;
  final String uid;
  final String title;
  final String content;
  final String date;

  // Novos campos
  final String? cloudId;
  final String category;
  final String updatedAt;

  Note({
    this.id,
    required this.uid,
    required this.title,
    required this.content,
    required this.date,
    this.cloudId,
    this.category = 'Pessoal',
    String? updatedAt,
  }) : updatedAt = updatedAt ?? date;

  // Converte a nota para o SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'title': title,
      'content': content,
      'date': date,
      'cloudId': cloudId,
      'category': category,
      'updatedAt': updatedAt,
    };
  }

  // Recupera uma nota do SQLite
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      uid: map['uid'],
      title: map['title'],
      content: map['content'],
      date: map['date'],
      cloudId: map['cloudId'],
      category: map['category'] ?? 'Pessoal',
      updatedAt: map['updatedAt'],
    );
  }
}
