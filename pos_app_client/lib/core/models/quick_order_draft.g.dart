// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quick_order_draft.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QuickOrderDraftAdapter extends TypeAdapter<QuickOrderDraft> {
  @override
  final int typeId = 14;

  @override
  QuickOrderDraft read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuickOrderDraft(
      id: fields[0] as String,
      items: (fields[1] as List).cast<OrderItem>(),
      subtotal: fields[2] as double,
      serviceFeeAmount: fields[3] as double,
      total: fields[4] as double,
      includeServiceFee: fields[5] as bool,
      serviceFeeRate: fields[6] as double,
      createdAt: fields[7] as DateTime,
      createdBy: fields[8] as String,
      displayName: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, QuickOrderDraft obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.items)
      ..writeByte(2)
      ..write(obj.subtotal)
      ..writeByte(3)
      ..write(obj.serviceFeeAmount)
      ..writeByte(4)
      ..write(obj.total)
      ..writeByte(5)
      ..write(obj.includeServiceFee)
      ..writeByte(6)
      ..write(obj.serviceFeeRate)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.createdBy)
      ..writeByte(9)
      ..write(obj.displayName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickOrderDraftAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
