/// A bank account the user has added (bank name + last 4 digits only).
class BankAccount {
  final String id;
  final String bank;
  final String last4;

  const BankAccount({
    required this.id,
    required this.bank,
    required this.last4,
  });

  String get label => '$bank $last4';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank': bank,
      'last4': last4,
    };
  }

  factory BankAccount.fromMap(Map<String, dynamic> map) {
    return BankAccount(
      id: map['id'] as String,
      bank: map['bank'] as String,
      last4: map['last4'] as String,
    );
  }
}