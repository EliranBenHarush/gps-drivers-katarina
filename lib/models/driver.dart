class Driver {
  final String id;
  final String name;
  final String pin;

  const Driver({required this.id, required this.name, this.pin = '1111'});

  factory Driver.fromFirestore(Map<String, dynamic> data, String id) {
    return Driver(
      id: id,
      name: data['name'] as String? ?? '',
      pin: data['pin'] as String? ?? '1111',
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'pin': pin};

  @override
  bool operator ==(Object other) => other is Driver && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
