import 'package:flutter/foundation.dart';

import 'enums.dart';

@immutable
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.iconKey = 'category',
    this.colorValue = 0xFFA78BFA,
    this.sortOrder = 0,
    this.isBuiltIn = false,
    this.transactionType = TransactionType.expense,
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
  final bool isBuiltIn;
  final TransactionType transactionType;

  ExpenseCategory copyWith({
    String? name,
    String? iconKey,
    int? colorValue,
    int? sortOrder,
    TransactionType? transactionType,
  }) => ExpenseCategory(
        id: id,
        name: name ?? this.name,
        iconKey: iconKey ?? this.iconKey,
        colorValue: colorValue ?? this.colorValue,
        sortOrder: sortOrder ?? this.sortOrder,
        isBuiltIn: isBuiltIn,
        transactionType: transactionType ?? this.transactionType,
      );

  @override
  bool operator ==(Object other) => other is ExpenseCategory &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.colorValue == colorValue &&
      other.sortOrder == sortOrder &&
      other.isBuiltIn == isBuiltIn &&
      other.transactionType == transactionType;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        iconKey,
        colorValue,
        sortOrder,
        isBuiltIn,
        transactionType,
      );
}
