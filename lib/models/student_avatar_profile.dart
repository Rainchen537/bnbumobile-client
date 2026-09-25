enum StudentAvatarBody { classic, relaxed, athletic }

enum StudentAvatarSkinTone { porcelain, light, warm, tan, deep }

enum StudentAvatarHairStyle { crop, wave, shag, bob, bun }

enum StudentAvatarHairColor { ink, espresso, chestnut, ash, blueBlack }

enum StudentAvatarTop { campusHoodie, varsityJacket, smartShirt, winterCoat }

enum StudentAvatarBottom { greyJoggers, blackCargo, blueDenim }

enum StudentAvatarShoes { runners, highTops, sneakers }

enum StudentAvatarAccessory { none, crossbody, headphones, backpack, scarf }

enum StudentAvatarMood { calm, happy, focused, thinking }

class StudentAvatarProfile {
  const StudentAvatarProfile({
    this.schemaVersion = currentSchemaVersion,
    this.body = StudentAvatarBody.classic,
    this.skinTone = StudentAvatarSkinTone.light,
    this.hairStyle = StudentAvatarHairStyle.wave,
    this.hairColor = StudentAvatarHairColor.ink,
    this.top = StudentAvatarTop.campusHoodie,
    this.bottom = StudentAvatarBottom.blackCargo,
    this.shoes = StudentAvatarShoes.runners,
    this.accessory = StudentAvatarAccessory.crossbody,
    this.mood = StudentAvatarMood.calm,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final StudentAvatarBody body;
  final StudentAvatarSkinTone skinTone;
  final StudentAvatarHairStyle hairStyle;
  final StudentAvatarHairColor hairColor;
  final StudentAvatarTop top;
  final StudentAvatarBottom bottom;
  final StudentAvatarShoes shoes;
  final StudentAvatarAccessory accessory;
  final StudentAvatarMood mood;

  StudentAvatarProfile copyWith({
    StudentAvatarBody? body,
    StudentAvatarSkinTone? skinTone,
    StudentAvatarHairStyle? hairStyle,
    StudentAvatarHairColor? hairColor,
    StudentAvatarTop? top,
    StudentAvatarBottom? bottom,
    StudentAvatarShoes? shoes,
    StudentAvatarAccessory? accessory,
    StudentAvatarMood? mood,
  }) {
    return StudentAvatarProfile(
      schemaVersion: schemaVersion,
      body: body ?? this.body,
      skinTone: skinTone ?? this.skinTone,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      shoes: shoes ?? this.shoes,
      accessory: accessory ?? this.accessory,
      mood: mood ?? this.mood,
    );
  }

  Map<String, Object> toJson() {
    return {
      'schema_version': schemaVersion,
      'body': body.name,
      'skin_tone': skinTone.name,
      'hair_style': hairStyle.name,
      'hair_color': hairColor.name,
      'top': top.name,
      'bottom': bottom.name,
      'shoes': shoes.name,
      'accessory': accessory.name,
      'mood': mood.name,
    };
  }

  factory StudentAvatarProfile.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported student avatar schema');
    }

    return StudentAvatarProfile(
      schemaVersion: schemaVersion,
      body: _requiredEnum(json, 'body', StudentAvatarBody.values),
      skinTone: _requiredEnum(json, 'skin_tone', StudentAvatarSkinTone.values),
      hairStyle: _requiredEnum(
        json,
        'hair_style',
        StudentAvatarHairStyle.values,
      ),
      hairColor: _requiredEnum(
        json,
        'hair_color',
        StudentAvatarHairColor.values,
      ),
      top: _requiredEnum(json, 'top', StudentAvatarTop.values),
      bottom: _requiredEnum(json, 'bottom', StudentAvatarBottom.values),
      shoes: _requiredEnum(json, 'shoes', StudentAvatarShoes.values),
      accessory: _requiredEnum(
        json,
        'accessory',
        StudentAvatarAccessory.values,
      ),
      mood: _requiredEnum(json, 'mood', StudentAvatarMood.values),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StudentAvatarProfile &&
            schemaVersion == other.schemaVersion &&
            body == other.body &&
            skinTone == other.skinTone &&
            hairStyle == other.hairStyle &&
            hairColor == other.hairColor &&
            top == other.top &&
            bottom == other.bottom &&
            shoes == other.shoes &&
            accessory == other.accessory &&
            mood == other.mood;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    body,
    skinTone,
    hairStyle,
    hairColor,
    top,
    bottom,
    shoes,
    accessory,
    mood,
  );
}

class StudentAvatarPatch {
  const StudentAvatarPatch({
    this.body,
    this.skinTone,
    this.hairStyle,
    this.hairColor,
    this.top,
    this.bottom,
    this.shoes,
    this.accessory,
    this.mood,
  });

  final StudentAvatarBody? body;
  final StudentAvatarSkinTone? skinTone;
  final StudentAvatarHairStyle? hairStyle;
  final StudentAvatarHairColor? hairColor;
  final StudentAvatarTop? top;
  final StudentAvatarBottom? bottom;
  final StudentAvatarShoes? shoes;
  final StudentAvatarAccessory? accessory;
  final StudentAvatarMood? mood;

  bool get isEmpty =>
      body == null &&
      skinTone == null &&
      hairStyle == null &&
      hairColor == null &&
      top == null &&
      bottom == null &&
      shoes == null &&
      accessory == null &&
      mood == null;

  factory StudentAvatarPatch.fromJson(Map<String, Object?> json) {
    const allowedKeys = {
      'body',
      'skin_tone',
      'hair_style',
      'hair_color',
      'top',
      'bottom',
      'shoes',
      'accessory',
      'mood',
    };
    final unknownKeys = json.keys.where((key) => !allowedKeys.contains(key));
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'Unsupported student avatar fields: ${unknownKeys.join(', ')}',
      );
    }

    return StudentAvatarPatch(
      body: _optionalEnum(json, 'body', StudentAvatarBody.values),
      skinTone: _optionalEnum(json, 'skin_tone', StudentAvatarSkinTone.values),
      hairStyle: _optionalEnum(
        json,
        'hair_style',
        StudentAvatarHairStyle.values,
      ),
      hairColor: _optionalEnum(
        json,
        'hair_color',
        StudentAvatarHairColor.values,
      ),
      top: _optionalEnum(json, 'top', StudentAvatarTop.values),
      bottom: _optionalEnum(json, 'bottom', StudentAvatarBottom.values),
      shoes: _optionalEnum(json, 'shoes', StudentAvatarShoes.values),
      accessory: _optionalEnum(
        json,
        'accessory',
        StudentAvatarAccessory.values,
      ),
      mood: _optionalEnum(json, 'mood', StudentAvatarMood.values),
    );
  }

  StudentAvatarProfile applyTo(StudentAvatarProfile profile) {
    return profile.copyWith(
      body: body,
      skinTone: skinTone,
      hairStyle: hairStyle,
      hairColor: hairColor,
      top: top,
      bottom: bottom,
      shoes: shoes,
      accessory: accessory,
      mood: mood,
    );
  }
}

T _requiredEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) {
  final value = _optionalEnum(json, key, values);
  if (value == null) {
    throw FormatException('Missing student avatar field: $key');
  }
  return value;
}

T? _optionalEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  final raw = json[key];
  if (raw is! String || raw.isEmpty) {
    throw FormatException('Invalid student avatar field: $key');
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  throw FormatException('Invalid student avatar option: $key');
}
