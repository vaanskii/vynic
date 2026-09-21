class ManagerVenueSelection {
  const ManagerVenueSelection({
    required this.id,
    required this.code,
    required this.name,
    required this.origin,
    this.branchName,
    this.address,
  });
  final String id, code, name, origin;
  final String? branchName, address;
  factory ManagerVenueSelection.fromMap(Map value, {required String origin}) {
    if (value['id'] is! String ||
        value['code'] is! String ||
        value['name'] is! String ||
        (value['code'] as String).isEmpty ||
        (value['name'] as String).isEmpty)
      throw const FormatException('Invalid Venue selection');
    return ManagerVenueSelection(
      id: value['id'] as String,
      code: value['code'] as String,
      name: value['name'] as String,
      origin: origin,
      branchName: value['branchName'] as String?,
      address: value['address'] as String?,
    );
  }
  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'origin': origin,
    'branchName': branchName,
    'address': address,
  };
}
