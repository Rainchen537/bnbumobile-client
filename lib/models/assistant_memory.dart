class AssistantMemoryEntry {
  const AssistantMemoryEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.memoryType = 'persona',
    this.sourceId = '',
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String memoryType;
  final String sourceId;

  AssistantMemoryEntry copyWith({
    String? content,
    DateTime? updatedAt,
    bool? deleted,
    String? memoryType,
    String? sourceId,
  }) => AssistantMemoryEntry(
    id: id,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
    memoryType: memoryType ?? this.memoryType,
    sourceId: sourceId ?? this.sourceId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
    'memory_type': memoryType,
    'source_id': sourceId,
  };

  factory AssistantMemoryEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final content = json['content'];
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updated_at']?.toString() ?? '');
    if (id is! String ||
        id.isEmpty ||
        content is! String ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('小U记忆格式无效。');
    }
    return AssistantMemoryEntry(
      id: id,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: json['deleted'] == true,
      memoryType: switch (json['memory_type']) {
        'episodic' => 'episodic',
        'instruction' => 'instruction',
        _ => 'persona',
      },
      sourceId: json['source_id'] is String
          ? (json['source_id'] as String)
          : '',
    );
  }
}
