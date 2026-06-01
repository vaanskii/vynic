// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_item_db.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MenuCategoryDBAdapter extends TypeAdapter<MenuCategoryDB> {
  @override
  final int typeId = 5;

  @override
  MenuCategoryDB read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuCategoryDB(
      slug: fields[0] as String,
      translationsEn: (fields[1] as Map).cast<String, String>(),
      translationsKa: (fields[2] as Map).cast<String, String>(),
      items: (fields[3] as List?)?.cast<MenuItemDB>(),
      subcategories: (fields[4] as List?)?.cast<MenuSubcategoryDB>(),
      sendToKitchen: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MenuCategoryDB obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.slug)
      ..writeByte(1)
      ..write(obj.translationsEn)
      ..writeByte(2)
      ..write(obj.translationsKa)
      ..writeByte(3)
      ..write(obj.items)
      ..writeByte(4)
      ..write(obj.subcategories)
      ..writeByte(5)
      ..write(obj.sendToKitchen);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuCategoryDBAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MenuSubcategoryDBAdapter extends TypeAdapter<MenuSubcategoryDB> {
  @override
  final int typeId = 6;

  @override
  MenuSubcategoryDB read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuSubcategoryDB(
      slug: fields[0] as String,
      translationsEn: (fields[1] as Map).cast<String, String>(),
      translationsKa: (fields[2] as Map).cast<String, String>(),
      items: (fields[3] as List).cast<MenuItemDB>(),
    );
  }

  @override
  void write(BinaryWriter writer, MenuSubcategoryDB obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.slug)
      ..writeByte(1)
      ..write(obj.translationsEn)
      ..writeByte(2)
      ..write(obj.translationsKa)
      ..writeByte(3)
      ..write(obj.items);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuSubcategoryDBAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MenuItemDBAdapter extends TypeAdapter<MenuItemDB> {
  @override
  final int typeId = 7;

  @override
  MenuItemDB read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuItemDB(
      translationsEn: (fields[0] as Map).cast<String, String>(),
      translationsKa: (fields[1] as Map).cast<String, String>(),
      price: fields[2] as double?,
      variants: (fields[3] as List?)?.cast<MenuVariantDB>(),
      sendToKitchen: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MenuItemDB obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.translationsEn)
      ..writeByte(1)
      ..write(obj.translationsKa)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.variants)
      ..writeByte(4)
      ..write(obj.sendToKitchen);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuItemDBAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MenuVariantDBAdapter extends TypeAdapter<MenuVariantDB> {
  @override
  final int typeId = 8;

  @override
  MenuVariantDB read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuVariantDB(
      size: fields[0] as double,
      price: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, MenuVariantDB obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.size)
      ..writeByte(1)
      ..write(obj.price);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuVariantDBAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
