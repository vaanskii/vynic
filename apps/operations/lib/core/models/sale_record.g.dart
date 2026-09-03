// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SaleRecordItemAdapter extends TypeAdapter<SaleRecordItem> {
  @override
  final int typeId = 16;

  @override
  SaleRecordItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleRecordItem(
      itemName: fields[0] as String,
      quantity: fields[1] as int,
      unitPrice: fields[2] as double,
      total: fields[3] as double,
      comment: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SaleRecordItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.itemName)
      ..writeByte(1)
      ..write(obj.quantity)
      ..writeByte(2)
      ..write(obj.unitPrice)
      ..writeByte(3)
      ..write(obj.total)
      ..writeByte(4)
      ..write(obj.comment);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleRecordItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SaleRecordAdapter extends TypeAdapter<SaleRecord> {
  @override
  final int typeId = 15;

  @override
  SaleRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleRecord(
      closureId: fields[0] as String?,
      orderId: fields[1] as int,
      tableNumbers: (fields[2] as List).cast<String>(),
      floor: fields[3] as String,
      items: (fields[4] as List).cast<SaleRecordItem>(),
      totalAmount: fields[5] as double,
      paymentMethod: fields[6] as String,
      paymentBreakdown: (fields[7] as Map?)?.cast<String, double>(),
      customPaymentLabel: fields[8] as String?,
      createdBy: fields[9] as String,
      createdAt: fields[10] as DateTime,
      closedAt: fields[11] as DateTime,
      includeServiceFee: fields[12] as bool,
      discountAmount: fields[13] as double,
      advanceAmount: fields[14] as double,
      subtotalAmount: fields[15] as double,
      manualAdjustmentAmount: fields[16] as double,
      finalTransaction: (fields[17] as Map?)?.cast<String, dynamic>(),
      businessDate: fields[18] as String,
      isCancelled: fields[19] as bool,
      cancelledAt: fields[20] as DateTime?,
      isFiscal: fields[21] as bool,
      restoredToOrder: fields[22] as bool,
      restoredAt: fields[23] as DateTime?,
      restoredBy: fields[24] as String?,
      tipAmount: fields[25] as double,
      closedById: fields[26] as String?,
      cancelledBy: fields[27] as String?,
      cancellationReason: fields[28] as String?,
      recordType: (fields[29] as String?) ?? SaleRecord.recordTypeSale,
      grossSaleAmount: fields[30] as double?,
      advanceApplied: (fields[31] as double?) ?? 0.0,
      collectedNow: fields[32] as double?,
      appliedToClosureId: fields[33] as String?,
      advanceReceiptId: fields[34] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SaleRecord obj) {
    writer
      ..writeByte(35)
      ..writeByte(0)
      ..write(obj.closureId)
      ..writeByte(1)
      ..write(obj.orderId)
      ..writeByte(2)
      ..write(obj.tableNumbers)
      ..writeByte(3)
      ..write(obj.floor)
      ..writeByte(4)
      ..write(obj.items)
      ..writeByte(5)
      ..write(obj.totalAmount)
      ..writeByte(6)
      ..write(obj.paymentMethod)
      ..writeByte(7)
      ..write(obj.paymentBreakdown)
      ..writeByte(8)
      ..write(obj.customPaymentLabel)
      ..writeByte(9)
      ..write(obj.createdBy)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.closedAt)
      ..writeByte(12)
      ..write(obj.includeServiceFee)
      ..writeByte(13)
      ..write(obj.discountAmount)
      ..writeByte(14)
      ..write(obj.advanceAmount)
      ..writeByte(15)
      ..write(obj.subtotalAmount)
      ..writeByte(16)
      ..write(obj.manualAdjustmentAmount)
      ..writeByte(17)
      ..write(obj.finalTransaction)
      ..writeByte(18)
      ..write(obj.businessDate)
      ..writeByte(19)
      ..write(obj.isCancelled)
      ..writeByte(20)
      ..write(obj.cancelledAt)
      ..writeByte(21)
      ..write(obj.isFiscal)
      ..writeByte(22)
      ..write(obj.restoredToOrder)
      ..writeByte(23)
      ..write(obj.restoredAt)
      ..writeByte(24)
      ..write(obj.restoredBy)
      ..writeByte(25)
      ..write(obj.tipAmount)
      ..writeByte(26)
      ..write(obj.closedById)
      ..writeByte(27)
      ..write(obj.cancelledBy)
      ..writeByte(28)
      ..write(obj.cancellationReason)
      ..writeByte(29)
      ..write(obj.recordType)
      ..writeByte(30)
      ..write(obj.grossSaleAmount)
      ..writeByte(31)
      ..write(obj.advanceApplied)
      ..writeByte(32)
      ..write(obj.collectedNow)
      ..writeByte(33)
      ..write(obj.appliedToClosureId)
      ..writeByte(34)
      ..write(obj.advanceReceiptId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
