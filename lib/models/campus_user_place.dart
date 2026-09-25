class CampusUserPlace {
  const CampusUserPlace({
    required this.id,
    required this.name,
    required this.note,
    this.longitude,
    this.latitude,
    this.mapX,
    this.mapY,
    required this.createdAt,
    required this.updatedAt,
  }) : assert((longitude == null) == (latitude == null)),
       assert((mapX == null) == (mapY == null)),
       assert(longitude != null || mapX != null);

  final String id;
  final String name;
  final String note;
  final double? longitude;
  final double? latitude;
  final double? mapX;
  final double? mapY;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return other is CampusUserPlace &&
        other.id == id &&
        other.name == name &&
        other.note == note &&
        other.longitude == longitude &&
        other.latitude == latitude &&
        other.mapX == mapX &&
        other.mapY == mapY &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    note,
    longitude,
    latitude,
    mapX,
    mapY,
    createdAt,
    updatedAt,
  );

  CampusUserPlace copyWith({String? name, String? note, DateTime? updatedAt}) {
    return CampusUserPlace(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      longitude: longitude,
      latitude: latitude,
      mapX: mapX,
      mapY: mapY,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool matches(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        note.toLowerCase().contains(query);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'note': note,
    if (longitude != null) 'longitude': longitude,
    if (latitude != null) 'latitude': latitude,
    if (mapX != null) 'map_x': mapX,
    if (mapY != null) 'map_y': mapY,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory CampusUserPlace.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json['id'], field: 'id', maxLength: 96);
    final name = _requiredString(json['name'], field: 'name', maxLength: 60);
    final note = _optionalString(json['note'], field: 'note', maxLength: 160);
    final hasMapCoordinates = json['map_x'] != null || json['map_y'] != null;
    final hasGeoCoordinates =
        json['longitude'] != null || json['latitude'] != null;
    if (hasMapCoordinates == hasGeoCoordinates) {
      throw const FormatException(
        'exactly one coordinate pair must be provided',
      );
    }
    final mapX = hasMapCoordinates
        ? _mapCoordinate(json['map_x'], field: 'map_x')
        : null;
    final mapY = hasMapCoordinates
        ? _mapCoordinate(json['map_y'], field: 'map_y')
        : null;
    final longitude = hasGeoCoordinates
        ? _geoCoordinate(
            json['longitude'],
            field: 'longitude',
            minimum: -180,
            maximum: 180,
          )
        : null;
    final latitude = hasGeoCoordinates
        ? _geoCoordinate(
            json['latitude'],
            field: 'latitude',
            minimum: -90,
            maximum: 90,
          )
        : null;
    final createdAt = _dateTime(json['created_at'], field: 'created_at');
    final updatedAt = _dateTime(json['updated_at'], field: 'updated_at');
    return CampusUserPlace(
      id: id,
      name: name,
      note: note,
      longitude: longitude,
      latitude: latitude,
      mapX: mapX,
      mapY: mapY,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _requiredString(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    if (value is! String) {
      throw FormatException('$field must be a string');
    }
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maxLength) {
      throw FormatException('$field is invalid');
    }
    return normalized;
  }

  static String _optionalString(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    if (value == null) return '';
    if (value is! String || value.trim().length > maxLength) {
      throw FormatException('$field is invalid');
    }
    return value.trim();
  }

  static double _mapCoordinate(Object? value, {required String field}) {
    if (value is! num || !value.isFinite) {
      throw FormatException('$field must be a finite number');
    }
    final coordinate = value.toDouble();
    if (coordinate < 0 || coordinate > 1) {
      throw FormatException('$field is outside the campus map');
    }
    return coordinate;
  }

  static double _geoCoordinate(
    Object? value, {
    required String field,
    required double minimum,
    required double maximum,
  }) {
    if (value is! num || !value.isFinite) {
      throw FormatException('$field must be a finite number');
    }
    final coordinate = value.toDouble();
    if (coordinate < minimum || coordinate > maximum) {
      throw FormatException('$field is outside the valid range');
    }
    return coordinate;
  }

  static DateTime _dateTime(Object? value, {required String field}) {
    if (value is! String) {
      throw FormatException('$field must be a string');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$field is invalid');
    }
    return parsed.toUtc();
  }
}
