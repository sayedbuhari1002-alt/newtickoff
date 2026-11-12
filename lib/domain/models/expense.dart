import 'package:flutter/foundation.dart';

import 'enums.dart';

/// A local financial transaction. Amounts are stored as integer paise to
/// avoid floating-point rounding errors in totals and analytics.
@immutable
class Expense {
  const Expense({
    required this.id,
    required this.amountPaise,
    required this.expenseDate,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.description = '',
    this.paymentMethod = '',
    this.transactionType = TransactionType.expense,
  });

  final String id;
  final int amountPaise;
  final DateTime expenseDate;
  final String? categoryId;
  final String description;
  final String paymentMethod;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TransactionType transactionType;

  bool get isIncome => transactionType == TransactionType.income;
  bool get isExpense => transactionType == TransactionType.expense;
  double get amountRupees => amountPaise / 100.0;

  String? validate() {
    if (amountPaise <= 0) return 'Enter an amount greater than zero.';
    if (description.trim().length > 300) return 'Description is too long.';
    return null;
  }

  Expense copyWith({
    int? amountPaise,
    DateTime? expenseDate,
    String? categoryId,
    bool clearCategory = false,
    String? description,
    String? paymentMethod,
    TransactionType? transactionType,
    DateTime? updatedAt,
  }) => Expense(
        id: id,
        amountPaise: amountPaise ?? this.amountPaise,
        expenseDate: expenseDate == null
            ? this.expenseDate
            : DateTime(expenseDate.year, expenseDate.month, expenseDate.day),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        description: description ?? this.description,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        transactionType: transactionType ?? this.transactionType,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'amountPaise': amountPaise,
        'expenseDate': expenseDate.toIso8601String(),
        'categoryId': categoryId,
        'description': description,
        'paymentMethod': paymentMethod,
        'transactionType': transactionType.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> json) {
    final DateTime now = DateTime.now();
    DateTime parseDate(Object? raw) => DateTime.tryParse('$raw') ?? now;
    return Expense(
      id: json['id'] as String,
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      expenseDate: parseDate(json['expenseDate']),
      categoryId: json['categoryId'] as String?,
      description: json['description'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? '',
      transactionType: enumByName(
        TransactionType.values,
        json['transactionType'],
        TransactionType.expense,
      ),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  @override
  bool operator ==(Object other) => other is Expense &&
      other.id == id &&
      other.amountPaise == amountPaise &&
      other.expenseDate == expenseDate &&
      other.categoryId == categoryId &&
      other.description == description &&
      other.paymentMethod == paymentMethod &&
      other.transactionType == transactionType &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        amountPaise,
        expenseDate,
        categoryId,
        description,
        paymentMethod,
        transactionType,
        createdAt,
        updatedAt,
      );
}
