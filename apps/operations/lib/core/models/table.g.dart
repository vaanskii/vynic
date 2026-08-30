// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'table.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TableModelAdapter extends TypeAdapter<TableModel> {
  @override
  final int typeId = 2;

  @override
  TableModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TableModel(
      tableNumber: fields[0] as String,
      floor: fields[1] as String,
      isReserved: fields[2] as bool,
      reservedAt: fields[3] as DateTime?,
      reservedBy: fields[4] as String?,
      activeOrderId: fields[5] as int?,
      reservationId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TableModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.tableNumber)
      ..writeByte(1)
      ..write(obj.floor)
      ..writeByte(2)
      ..write(obj.isReserved)
      ..writeByte(3)
      ..write(obj.reservedAt)
      ..writeByte(4)
      ..write(obj.reservedBy)
      ..writeByte(5)
      ..write(obj.activeOrderId)
      ..writeByte(6)
      ..write(obj.reservationId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
