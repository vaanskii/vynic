// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PackageAdapter extends TypeAdapter<Package> {
  @override
  final int typeId = 11;

  @override
  Package read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Package(
      packageId: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String?,
      items: (fields[3] as List).cast<PackageItem>(),
      pricePerPerson: fields[4] as double,
      isActive: fields[5] == null ? true : fields[5] as bool,
      createdAt: fields[6] as DateTime,
      createdBy: fields[7] as String,
      servingSize: fields[8] == null ? 1 : fields[8] as int,
      allowedTables: (fields[9] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Package obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.packageId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.items)
      ..writeByte(4)
      ..write(obj.pricePerPerson)
      ..writeByte(5)
      ..write(obj.isActive)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.createdBy)
      ..writeByte(8)
      ..write(obj.servingSize)
      ..writeByte(9)
      ..write(obj.allowedTables);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PackageItemAdapter extends TypeAdapter<PackageItem> {
  @override
  final int typeId = 12;

  @override
  PackageItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PackageItem(
      itemKey: fields[0] as String,
      itemName: fields[1] as String,
      quantity: fields[2] as int,
      unitPrice: fields[3] as double,
      menuItemId: fields[4] as String?,
      variantId: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PackageItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.itemKey)
      ..writeByte(1)
      ..write(obj.itemName)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.unitPrice)
      ..writeByte(4)
      ..write(obj.menuItemId)
      ..writeByte(5)
      ..write(obj.variantId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
