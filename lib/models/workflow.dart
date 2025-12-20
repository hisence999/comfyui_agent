import 'dart:convert';

class Workflow {
  final String id;
  String name;
  String content; // JSON string
  DateTime lastModified;

  Workflow({
    required this.id,
    required this.name,
    required this.content,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'last_modified': lastModified.millisecondsSinceEpoch,
    };
  }

  factory Workflow.fromMap(Map<String, dynamic> map) {
    return Workflow(
      id: map['id'],
      name: map['name'],
      content: map['content'],
      lastModified: DateTime.fromMillisecondsSinceEpoch(map['last_modified']),
    );
  }
  
  Map<String, dynamic> get jsonContent {
    try {
      return jsonDecode(content);
    } catch (e) {
      return {};
    }
  }
}
