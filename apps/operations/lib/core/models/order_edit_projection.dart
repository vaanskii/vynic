import 'dart:convert';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/models/order.dart';

abstract final class OrderEditProjection {
  static Map<String, dynamic> build(
    Order order, {
    double? effectiveServiceFeePercent,
  }) {
    final image = PosBackupFormat.canonical(
      OrderTransferIntent.snapshot(order),
    );
    return {
      'effectiveServiceFeePercent':
          effectiveServiceFeePercent ??
          order.customServiceFeePercentage ??
          SettingsRepository.getServiceFeePercentage(),
      'version': 1,
      'orderUuid': order.orderUuid,
      'fingerprint': sha256.convert(utf8.encode(image)).toString(),
      'image': image,
    };
  }

  static Order read(Map<String, dynamic> v) {
    final image = v['image'];
    if (v['version'] != 1 ||
        v['effectiveServiceFeePercent'] is! num ||
        !(v['effectiveServiceFeePercent'] as num).isFinite ||
        v['effectiveServiceFeePercent'] < 0 ||
        v['effectiveServiceFeePercent'] > 100 ||
        image is! String ||
        image.length > 1000000 ||
        sha256.convert(utf8.encode(image)).toString() != v['fingerprint'])
      throw const FormatException('Invalid POS edit projection');
    final raw = jsonDecode(image) as Map<String, dynamic>;
    final order = BackupRepository.deserializeOrderSnapshot(raw);
    if (order.orderUuid != v['orderUuid'] ||
        PosBackupFormat.canonical(OrderTransferIntent.snapshot(order)) != image)
      throw const FormatException('Incomplete POS edit projection');
    order.managerEditProjection = Map<String, dynamic>.from(v);
    return order;
  }
}
