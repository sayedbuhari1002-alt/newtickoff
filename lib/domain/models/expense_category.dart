import 'package:flutter/foundation.dart';

@immutable
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.iconKey = 'category',
    this.colorValue = 0xFFFFC62B,
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
  final bool isBuiltIn;

  ExpenseCategory copyWith({
    String? name,
    String? iconKey,
    int? colorValue,
    int? sortOrder,
  }) => ExpenseCategory(
        id: id,
        name: name ?? this.name,
        iconKey: iconKey ?? this.iconKey,
        colorValue: colorValue ?? this.colorValue,
        sortOrder: sortOrder ?? this.sortOrder,
        isBuiltIn: isBuiltIn,
      );

  @override
  bool operator ==(Object other) => other is ExpenseCategory &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.colorValue == colorValue &&
      other.sortOrder == sortOrder &&
      other.isBuiltIn == isBuiltIn;

  @override
  int get hashCode => Object.hash(id, name, iconKey, colorValue, sortOrder, isBuiltIn);
}
