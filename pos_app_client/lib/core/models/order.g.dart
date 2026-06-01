// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderItemAdapter extends TypeAdapter<OrderItem> {
  @override
  final int typeId = 3;

  @override
  OrderItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderItem(
      itemKey: fields[0] as String,
      itemName: fields[1] as String,
      unitPrice: fields[2] as double,
      quantity: fields[3] as int,
      total: fields[4] as double,
      comment: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, OrderItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.itemKey)
      ..writeByte(1)
      ..write(obj.itemName)
      ..writeByte(2)
      ..write(obj.unitPrice)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.total)
      ..writeByte(5)
      ..write(obj.comment);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OrderAdapter extends TypeAdapter<Order> {
  @override
  final int typeId = 4;

  @override
  Order read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Order(
      orderId: fields[0] as int,
      tableNumbers: (fields[1] as List).cast<String>(),
      floor: fields[2] as String,
      items: (fields[3] as List).cast<OrderItem>(),
      totalAmount: fields[4] as double,
      createdAt: fields[5] as DateTime,
      createdBy: fields[6] as String,
      status: fields[7] as String,
      updatedAt: fields[8] as DateTime?,
      includeServiceFee: fields[9] as bool,
      paymentMethod: fields[10] as String?,
      closedAt: fields[11] as DateTime?,
      discountAmount: (fields[12] as double?) ?? 0.0,
      packageId: fields[13] as String?,
      packageName: fields[14] as String?,
      packagePrice: (fields[15] as double?) ?? 0.0,
      packageItems: (fields[16] as List?)?.cast<OrderItem>(),
      packageUnitPrice: (fields[17] as double?) ?? 0.0,
      packageGuestCount: (fields[18] as int?) ?? 0,
      manualAdjustmentAmount: (fields[19] as double?) ?? 0.0,
      openedByUserId: fields[20] as String?,
      customServiceFeePercentage: fields[21] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Order obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.orderId)
      ..writeByte(1)
      ..write(obj.tableNumbers)
      ..writeByte(2)
      ..write(obj.floor)
      ..writeByte(3)
      ..write(obj.items)
      ..writeByte(4)
      ..write(obj.totalAmount)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.createdBy)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.includeServiceFee)
      ..writeByte(10)
      ..write(obj.paymentMethod)
      ..writeByte(11)
      ..write(obj.closedAt)
      ..writeByte(12)
      ..write(obj.discountAmount)
      ..writeByte(13)
      ..write(obj.packageId)
      ..writeByte(14)
      ..write(obj.packageName)
      ..writeByte(15)
      ..write(obj.packagePrice)
      ..writeByte(16)
      ..write(obj.packageItems)
      ..writeByte(17)
      ..write(obj.packageUnitPrice)
      ..writeByte(18)
      ..write(obj.packageGuestCount)
      ..writeByte(19)
      ..write(obj.manualAdjustmentAmount)
      ..writeByte(20)
      ..write(obj.openedByUserId)
      ..writeByte(21)
      ..write(obj.customServiceFeePercentage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
