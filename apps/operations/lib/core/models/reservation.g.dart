// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reservation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReservationAdapter extends TypeAdapter<Reservation> {
  @override
  final int typeId = 9;

  @override
  Reservation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Reservation(
      id: fields[0] as String,
      customerName: fields[1] as String,
      customerPhone: fields[2] as String,
      tableNumbers: (fields[3] as List).cast<int>(),
      reservationDate: fields[4] as DateTime,
      reservationTime: fields[5] as String,
      numberOfGuests: fields[6] as int,
      notes: fields[7] as String?,
      createdAt: fields[8] as DateTime,
      createdBy: fields[9] as String,
      status: fields[10] as String,
      preOrderItems: (fields[11] as List?)?.cast<OrderItem>(),
      isTakeAway: fields[12] as bool,
      linkedOrderId: fields[13] as int?,
      tableRefs: (fields[14] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Reservation obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.customerName)
      ..writeByte(2)
      ..write(obj.customerPhone)
      ..writeByte(3)
      ..write(obj.tableNumbers)
      ..writeByte(4)
      ..write(obj.reservationDate)
      ..writeByte(5)
      ..write(obj.reservationTime)
      ..writeByte(6)
      ..write(obj.numberOfGuests)
      ..writeByte(7)
      ..write(obj.notes)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.createdBy)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.preOrderItems)
      ..writeByte(12)
      ..write(obj.isTakeAway)
      ..writeByte(13)
      ..write(obj.linkedOrderId)
      ..writeByte(14)
      ..write(obj.tableRefs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReservationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
