import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/menu_item_db.dart';

/// Canonical Cloud Menu as this POS last saw it, and the pure rules that turn
/// it into the local operational menu (docs/CANONICAL_MENU_SYNC.md).
///
/// Identity is the stable offline UUID every Menu node already carries
/// (`MenuCategoryDB.id` … `MenuVariantDB.id`); Cloud uses the same value. Each
/// node has its own server revision, so the POS can base an edit on exactly the
/// version it saw. Nothing here does I/O.
enum MenuKind { category, subcategory, item, variant }

extension MenuKindWire on MenuKind {
  String get wire => name.toUpperCase();
  static MenuKind parse(String value) =>
      MenuKind.values.firstWhere((k) => k.wire == value.toUpperCase());
}

class CanonicalNode {
  CanonicalNode({
    required this.kind,
    required this.id,
    required this.revision,
    required this.fields,
  });

  final MenuKind kind;
  final String id;
  final int revision;

  /// Wire fields without id/revision/changeSeq (e.g. nameKa, price, parents).
  final Map<String, Object?> fields;

  CanonicalNode copyWith({int? revision, Map<String, Object?>? fields}) =>
      CanonicalNode(
        kind: kind,
        id: id,
        revision: revision ?? this.revision,
        fields: fields ?? Map<String, Object?>.from(this.fields),
      );

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'id': id,
    'revision': revision,
    'fields': fields,
  };

  static CanonicalNode fromJson(Map<String, dynamic> json) => CanonicalNode(
    kind: MenuKindWire.parse(json['kind'] as String),
    id: json['id'] as String,
    revision: (json['revision'] as num).toInt(),
    fields: Map<String, Object?>.from(json['fields'] as Map),
  );

  /// Parses one node of a server snapshot/changes list.
  static CanonicalNode fromWire(MenuKind kind, Map<String, dynamic> wire) {
    final fields = Map<String, Object?>.from(wire)
      ..remove('id')
      ..remove('revision')
      ..remove('changeSeq');
    return CanonicalNode(
      kind: kind,
      id: wire['id'] as String,
      revision: (wire['revision'] as num).toInt(),
      fields: fields,
    );
  }

  String? get parentId => switch (kind) {
    MenuKind.category => null,
    MenuKind.subcategory => fields['categoryId'] as String?,
    MenuKind.item =>
      (fields['subcategoryId'] as String?) ?? fields['categoryId'] as String?,
    MenuKind.variant => fields['menuItemId'] as String?,
  };

  int get sortOrder => (fields['sortOrder'] as num?)?.toInt() ?? 0;
}

/// Editable fields per kind, as the POS can express them. `enabled` is not a
/// POS field: the POS never sends it, so a POS edit cannot re-enable a product
/// the owner disabled in the Dashboard.
const Map<MenuKind, List<String>> posFields = {
  MenuKind.category: ['slug', 'nameKa', 'nameEn', 'sendToKitchen'],
  MenuKind.subcategory: ['categoryId', 'slug', 'nameKa', 'nameEn'],
  MenuKind.item: [
    'categoryId',
    'subcategoryId',
    'nameKa',
    'nameEn',
    'price',
    'sendToKitchen',
  ],
  MenuKind.variant: ['menuItemId', 'size', 'price'],
};

const _kindOrder = [
  MenuKind.category,
  MenuKind.subcategory,
  MenuKind.item,
  MenuKind.variant,
];

/// One local change, before it is journaled.
class MenuChange {
  MenuChange({
    required this.kind,
    required this.operation,
    required this.entityId,
    required this.patch,
  });
  final MenuKind kind;

  /// `UPSERT` or `DELETE`.
  final String operation;
  final String entityId;
  final Map<String, Object?> patch;
}

class CanonicalMenu {
  CanonicalMenu({
    required this.venueId,
    required this.sequence,
    Map<String, CanonicalNode>? nodes,
  }) : nodes = nodes ?? <String, CanonicalNode>{};

  final String venueId;

  /// Venue catalog sequence this state is complete up to (catch-up cursor).
  int sequence;
  final Map<String, CanonicalNode> nodes;

  CanonicalMenu copy() => CanonicalMenu(
    venueId: venueId,
    sequence: sequence,
    nodes: {for (final e in nodes.entries) e.key: e.value.copyWith()},
  );

  static const _lists = {
    'categories': MenuKind.category,
    'subcategories': MenuKind.subcategory,
    'items': MenuKind.item,
    'variants': MenuKind.variant,
  };

  /// A complete version-2 server snapshot.
  static CanonicalMenu fromSnapshot(Map<String, dynamic> snapshot) {
    if (snapshot['version'] != 2 || snapshot['venueId'] is! String) {
      throw const FormatException('Unsupported canonical menu snapshot');
    }
    final menu = CanonicalMenu(
      venueId: snapshot['venueId'] as String,
      sequence: (snapshot['sequence'] as num).toInt(),
    );
    for (final entry in _lists.entries) {
      for (final raw in (snapshot[entry.key] as List? ?? const [])) {
        final node = CanonicalNode.fromWire(
          entry.value,
          Map<String, dynamic>.from(raw as Map),
        );
        menu.nodes[node.id] = node;
      }
    }
    return menu;
  }

  /// Applies a `changes?since=` response: current nodes, then tombstones.
  /// Deletion is only ever learned from a tombstone, never from omission.
  void applyChanges(Map<String, dynamic> changes) {
    if (changes['venueId'] != venueId) {
      throw StateError('Menu changes belong to another Venue');
    }
    for (final entry in _lists.entries) {
      for (final raw in (changes[entry.key] as List? ?? const [])) {
        final node = CanonicalNode.fromWire(
          entry.value,
          Map<String, dynamic>.from(raw as Map),
        );
        final known = nodes[node.id];
        // Never move backwards (a stale response racing a newer mutation result).
        if (known == null || known.revision <= node.revision) {
          nodes[node.id] = node;
        }
      }
    }
    for (final raw in (changes['tombstones'] as List? ?? const [])) {
      final tombstone = Map<String, dynamic>.from(raw as Map);
      nodes.remove(tombstone['entityId']);
    }
    sequence = (changes['sequence'] as num).toInt();
  }

  /// Records one accepted mutation result (entity is null when deleted).
  void applyAccepted(Map<String, dynamic> result) {
    // A historical ACK may arrive after its change was already covered by a
    // complete feed. In particular, it must not resurrect a later tombstone or
    // let an old already-missing DELETE remove a subsequently created node.
    final acceptedSequence = result['sequence'];
    if (acceptedSequence is num && acceptedSequence <= sequence) return;
    final id = result['entityId'] as String;
    if (result['deleted'] == true || result['entity'] == null) {
      nodes.remove(id);
      if (result['entityType'] == 'ITEM') {
        nodes.removeWhere(
          (_, n) => n.kind == MenuKind.variant && n.fields['menuItemId'] == id,
        );
      }
      return;
    }
    final node = CanonicalNode.fromWire(
      MenuKindWire.parse(result['entityType'] as String),
      Map<String, dynamic>.from(result['entity'] as Map),
    );
    final known = nodes[id];
    if (known == null || known.revision <= node.revision) nodes[id] = node;
  }

  /// Optimistic local application of a pending change (projection only).
  void applyLocal(MenuKind kind, String operation, String id, Map patch) {
    if (operation == 'DELETE') {
      nodes.remove(id);
      if (kind == MenuKind.item) {
        nodes.removeWhere(
          (_, n) => n.kind == MenuKind.variant && n.fields['menuItemId'] == id,
        );
      }
      return;
    }
    final known = nodes[id];
    final fields = known == null
        ? <String, Object?>{if (kind == MenuKind.item) 'enabled': true}
        : Map<String, Object?>.from(known.fields);
    patch.forEach((key, value) => fields[key as String] = value);
    if (kind == MenuKind.item && patch.containsKey('categoryId')) {
      fields['subcategoryId'] = null;
    }
    if (kind == MenuKind.item && patch.containsKey('subcategoryId')) {
      fields['categoryId'] = null;
    }
    nodes[id] = CanonicalNode(
      kind: kind,
      id: id,
      revision: known?.revision ?? 0,
      fields: fields,
    );
  }

  String toJsonString() => jsonEncode({
    'venueId': venueId,
    'sequence': sequence,
    'nodes': nodes.values.map((n) => n.toJson()).toList(),
  });

  static CanonicalMenu fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final menu = CanonicalMenu(
      venueId: json['venueId'] as String,
      sequence: (json['sequence'] as num).toInt(),
    );
    for (final raw in json['nodes'] as List) {
      final node = CanonicalNode.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      menu.nodes[node.id] = node;
    }
    return menu;
  }

  List<CanonicalNode> _ofKind(MenuKind kind) =>
      nodes.values.where((n) => n.kind == kind).toList();

  /// Nodes the POS operates on: every category/subcategory, and enabled items
  /// (with their variants). Disabled products stay canonical but unsellable.
  Set<String> visibleIds() {
    final hiddenItems = {
      for (final n in _ofKind(MenuKind.item))
        if (n.fields['enabled'] == false) n.id,
    };
    return {
      for (final n in nodes.values)
        if (!(n.kind == MenuKind.item && hiddenItems.contains(n.id)) &&
            !(n.kind == MenuKind.variant &&
                hiddenItems.contains(n.fields['menuItemId'])))
          n.id,
    };
  }

  static int _byOrder(CanonicalNode a, CanonicalNode b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }

  /// The operational POS menu tree (the existing Hive model, unchanged).
  List<MenuCategoryDB> toHive() {
    final visible = visibleIds();
    bool show(CanonicalNode n) => visible.contains(n.id);
    List<MenuVariantDB> variantsOf(String itemId) {
      final list =
          _ofKind(
              MenuKind.variant,
            ).where((v) => show(v) && v.fields['menuItemId'] == itemId).toList()
            ..sort((a, b) {
              final size = (a.fields['size'] as num).compareTo(
                b.fields['size'] as num,
              );
              return size != 0 ? size : a.id.compareTo(b.id);
            });
      return [
        for (final v in list)
          MenuVariantDB(
            size: (v.fields['size'] as num).toDouble(),
            price: (v.fields['price'] as num).toDouble(),
            id: v.id,
          ),
      ];
    }

    MenuItemDB item(CanonicalNode n) {
      final variants = variantsOf(n.id);
      final price = (n.fields['price'] as num?)?.toDouble() ?? 0;
      return MenuItemDB(
        translationsEn: {'name': (n.fields['nameEn'] as String?) ?? ''},
        translationsKa: {'name': (n.fields['nameKa'] as String?) ?? ''},
        // The POS models "priced by size" as a null base price.
        price: variants.isNotEmpty && price == 0 ? null : price,
        variants: variants.isEmpty ? null : variants,
        sendToKitchen: n.fields['sendToKitchen'] as bool? ?? true,
        id: n.id,
      );
    }

    List<MenuItemDB> itemsWhere(bool Function(CanonicalNode) where) {
      final list = _ofKind(
        MenuKind.item,
      ).where((n) => show(n) && where(n)).toList()..sort(_byOrder);
      return list.map(item).toList();
    }

    final categories = _ofKind(MenuKind.category)..sort(_byOrder);
    return [
      for (final c in categories)
        () {
          final subs =
              _ofKind(
                  MenuKind.subcategory,
                ).where((s) => s.fields['categoryId'] == c.id).toList()
                ..sort(_byOrder);
          return MenuCategoryDB(
            slug: (c.fields['slug'] as String?) ?? c.id,
            translationsEn: {'name': (c.fields['nameEn'] as String?) ?? ''},
            translationsKa: {'name': (c.fields['nameKa'] as String?) ?? ''},
            items: itemsWhere((i) => i.fields['categoryId'] == c.id),
            subcategories: subs.isEmpty
                ? null
                : [
                    for (final s in subs)
                      MenuSubcategoryDB(
                        slug: (s.fields['slug'] as String?) ?? s.id,
                        translationsEn: {
                          'name': (s.fields['nameEn'] as String?) ?? '',
                        },
                        translationsKa: {
                          'name': (s.fields['nameKa'] as String?) ?? '',
                        },
                        items: itemsWhere(
                          (i) => i.fields['subcategoryId'] == s.id,
                        ),
                        id: s.id,
                      ),
                  ],
            sendToKitchen: c.fields['sendToKitchen'] as bool? ?? true,
            id: c.id,
          );
        }(),
    ];
  }

  /// Wire-shaped view of an operational Hive menu (ids + POS fields).
  static Map<
    String,
    ({MenuKind kind, Map<String, Object?> fields, int position})
  >
  readHive(Iterable<MenuCategoryDB> categories) {
    final out =
        <
          String,
          ({MenuKind kind, Map<String, Object?> fields, int position})
        >{};
    void addItem(MenuItemDB item, String? categoryId, String? subId, int pos) {
      final id = item.id;
      if (id == null) return;
      out[id] = (
        kind: MenuKind.item,
        fields: {
          'categoryId': categoryId,
          'subcategoryId': subId,
          'nameKa': item.translationsKa['name'] ?? '',
          'nameEn': item.translationsEn['name'] ?? '',
          'price': _money(item.price ?? 0),
          'sendToKitchen': item.sendToKitchen,
        },
        position: pos,
      );
      for (final (index, v)
          in (item.variants ?? const <MenuVariantDB>[]).indexed) {
        if (v.id == null) continue;
        out[v.id!] = (
          kind: MenuKind.variant,
          fields: {'menuItemId': id, 'size': v.size, 'price': _money(v.price)},
          position: index,
        );
      }
    }

    for (final (ci, c) in categories.indexed) {
      final cid = c.id;
      if (cid == null) continue;
      out[cid] = (
        kind: MenuKind.category,
        fields: {
          'slug': c.slug,
          'nameKa': c.translationsKa['name'] ?? '',
          'nameEn': c.translationsEn['name'] ?? '',
          'sendToKitchen': c.sendToKitchen,
        },
        position: ci,
      );
      for (final (si, s)
          in (c.subcategories ?? const <MenuSubcategoryDB>[]).indexed) {
        final sid = s.id;
        if (sid == null) continue;
        out[sid] = (
          kind: MenuKind.subcategory,
          fields: {
            'categoryId': cid,
            'slug': s.slug,
            'nameKa': s.translationsKa['name'] ?? '',
            'nameEn': s.translationsEn['name'] ?? '',
          },
          position: si,
        );
        for (final (ii, item) in s.items.indexed) {
          addItem(item, null, sid, ii);
        }
      }
      for (final (ii, item) in (c.items ?? const <MenuItemDB>[]).indexed) {
        addItem(item, cid, null, ii);
      }
    }
    return out;
  }

  static double _money(double value) => (value * 100).roundToDouble() / 100;

  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }

  /// What the local operator changed relative to [baseline] (the projection
  /// last written to the operational menu). This is the POS's OWN edits only —
  /// never a multi-writer snapshot — so a node missing locally is a local
  /// delete. Order: creates/updates parent-first, deletes child-first.
  static List<MenuChange> diff(
    CanonicalMenu baseline,
    Iterable<MenuCategoryDB> local,
  ) {
    final visible = baseline.visibleIds();
    final seen = readHive(local);
    final upserts = <MenuChange>[];
    final deletes = <MenuChange>[];
    // Sibling order for new nodes: after everything already in the baseline.
    final maxOrder = <String?, int>{};
    for (final n in baseline.nodes.values) {
      final key = '${n.kind.wire}:${n.parentId}';
      if (n.sortOrder > (maxOrder[key] ?? -1)) maxOrder[key] = n.sortOrder;
    }
    for (final kind in _kindOrder) {
      for (final entry in seen.entries.where((e) => e.value.kind == kind)) {
        final id = entry.key;
        final local = entry.value;
        final known = baseline.nodes[id];
        if (known == null) {
          final patch = <String, Object?>{
            for (final f in posFields[kind]!)
              if (local.fields[f] != null) f: local.fields[f],
          };
          if (kind != MenuKind.variant) {
            final parent = switch (kind) {
              MenuKind.subcategory => local.fields['categoryId'],
              MenuKind.item =>
                local.fields['subcategoryId'] ?? local.fields['categoryId'],
              _ => null,
            };
            final key = '${kind.wire}:$parent';
            final next = (maxOrder[key] ?? -1) + 1;
            maxOrder[key] = next;
            patch['sortOrder'] = next;
          }
          upserts.add(
            MenuChange(
              kind: kind,
              operation: 'UPSERT',
              entityId: id,
              patch: patch,
            ),
          );
          continue;
        }
        if (!visible.contains(id) || known.kind != kind) continue;
        final patch = <String, Object?>{};
        for (final f in posFields[kind]!) {
          final before = f == 'price'
              ? _money(((known.fields[f] as num?) ?? 0).toDouble())
              : known.fields[f];
          if (!_same(before, local.fields[f])) patch[f] = local.fields[f];
        }
        if (kind == MenuKind.item &&
            (patch.containsKey('categoryId') ||
                patch.containsKey('subcategoryId'))) {
          // An item has exactly one parent; send the one it now has.
          patch.remove('categoryId');
          patch.remove('subcategoryId');
          final sub = local.fields['subcategoryId'];
          if (sub != null) {
            patch['subcategoryId'] = sub;
          } else {
            patch['categoryId'] = local.fields['categoryId'];
          }
        }
        // Slug is display metadata the server may have made unique; POS
        // edits to names regenerate it, so only send it with a name change.
        if (patch.keys.every((k) => k == 'slug')) patch.remove('slug');
        if (patch.isNotEmpty) {
          upserts.add(
            MenuChange(
              kind: kind,
              operation: 'UPSERT',
              entityId: id,
              patch: patch,
            ),
          );
        }
      }
    }
    for (final kind in _kindOrder.reversed) {
      for (final node in baseline.nodes.values.where((n) => n.kind == kind)) {
        if (!visible.contains(node.id) || seen.containsKey(node.id)) continue;
        // A deleted item's variants go with it (the server tombstones them).
        if (kind == MenuKind.variant &&
            !seen.containsKey(node.fields['menuItemId'])) {
          continue;
        }
        deletes.add(
          MenuChange(
            kind: kind,
            operation: 'DELETE',
            entityId: node.id,
            patch: const {},
          ),
        );
      }
    }
    return [...upserts, ...deletes];
  }

  static String newMutationId() => const Uuid().v4();
}
