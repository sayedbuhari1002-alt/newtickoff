import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';
import '../../shared/utils/guarded.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/pill_selector.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/tick_text_field.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class ExpenseEditorScreen extends ConsumerStatefulWidget {
  const ExpenseEditorScreen({super.key, this.expenseId, this.initialDate, this.initialType = TransactionType.expense});

  final String? expenseId;
  final DateTime? initialDate;
  final TransactionType initialType;

  @override
  ConsumerState<ExpenseEditorScreen> createState() => _ExpenseEditorScreenState();
}

class _ExpenseEditorScreenState extends ConsumerState<ExpenseEditorScreen> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  DateTime _date = DateTime.now();
  String? _categoryId;
  String _paymentMethod = 'UPI';
  TransactionType _transactionType = TransactionType.expense;
  bool _initialised = false;
  bool _saving = false;

  List<String> get _paymentMethods => _transactionType == TransactionType.income
      ? const <String>['Bank transfer', 'UPI', 'Cash', 'Cheque', 'Other']
      : const <String>['UPI', 'Cash', 'Debit card', 'Credit card', 'Bank transfer', 'Other'];

  String get _typeLabel => _transactionType == TransactionType.income ? 'Income' : 'Expense';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _initialise(AppData data) {
    if (_initialised) return;
    _initialised = true;
    _date = _dateOnly(widget.initialDate ?? DateTime.now());
    _transactionType = widget.initialType;
    if (widget.expenseId != null) {
      final Expense? existing = data.expenses.where((Expense e) => e.id == widget.expenseId).firstOrNull;
      if (existing != null) {
        _amount.text = (existing.amountPaise / 100).toStringAsFixed(existing.amountPaise % 100 == 0 ? 0 : 2);
        _description.text = existing.description;
        _date = existing.expenseDate;
        _categoryId = existing.categoryId;
        _transactionType = existing.transactionType;
        if (existing.paymentMethod.isNotEmpty) _paymentMethod = existing.paymentMethod;
      }
    }
    final List<ExpenseCategory> categories = data.expenseCategoriesForType(_transactionType);
    if (!categories.any((ExpenseCategory c) => c.id == _categoryId)) {
      _categoryId = categories.isEmpty ? null : categories.first.id;
    }
    if (!_paymentMethods.contains(_paymentMethod)) _paymentMethod = _paymentMethods.first;
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _changeType(TransactionType type, AppData data) {
    if (_transactionType == type) return;
    final List<ExpenseCategory> categories = data.expenseCategoriesForType(type);
    setState(() {
      _transactionType = type;
      _categoryId = categories.isEmpty ? null : categories.first.id;
      if (!_paymentMethods.contains(_paymentMethod)) _paymentMethod = _paymentMethods.first;
    });
  }

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Choose $_typeLabel date',
    );
    if (selected != null && mounted) setState(() => _date = _dateOnly(selected));
  }

  Future<void> _addCategory() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('New ${_typeLabel.toLowerCase()} category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final AppData data = ref.read(appDataProvider).valueOrNull!;
    final ExpenseCategory category = ExpenseCategory(
      id: newId(),
      name: name.trim(),
      iconKey: 'category',
      colorValue: _transactionType == TransactionType.income
          ? const Color(0xFF66BB6A).toARGB32()
          : AppColors.gold.toARGB32(),
      sortOrder: data.expenseCategoriesForType(_transactionType).length,
      transactionType: _transactionType,
    );
    final bool saved = await guarded(
      context,
      () => ref.read(appDataProvider.notifier).saveExpenseCategory(category),
      message: 'Could not add category',
    );
    if (saved && mounted) setState(() => _categoryId = category.id);
  }

  Future<void> _save(AppData data) async {
    final String rawAmount = _amount.text.trim().replaceAll(',', '');
    final double? value = double.tryParse(rawAmount);
    if (value == null || !value.isFinite || value <= 0) {
      showMessage(context, 'Enter a valid amount greater than zero.');
      return;
    }
    if (value > 90000000000000) {
      showMessage(context, 'That amount is too large.');
      return;
    }
    setState(() => _saving = true);
    final DateTime now = DateTime.now();
    final Expense? old = widget.expenseId == null
        ? null
        : data.expenses.where((Expense e) => e.id == widget.expenseId).firstOrNull;
    final Expense transaction = Expense(
      id: old?.id ?? newId(),
      amountPaise: (value * 100).round(),
      expenseDate: _date,
      categoryId: _categoryId,
      description: _description.text.trim(),
      paymentMethod: _paymentMethod,
      transactionType: _transactionType,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    final bool saved = await guarded(
      context,
      () => ref.read(appDataProvider.notifier).saveExpense(transaction),
      message: 'Could not save ${_typeLabel.toLowerCase()}',
    );
    if (saved && mounted) context.pop();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(Expense transaction) async {
    final String type = transaction.isIncome ? 'income' : 'expense';
    final bool sure = await showConfirmDialog(
      context,
      title: 'Delete $type?',
      message: 'This $type record will be permanently removed from your records.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final bool deleted = await guarded(
      context,
      () => ref.read(appDataProvider.notifier).deleteExpense(transaction.id),
      message: 'Could not delete $type',
    );
    if (deleted && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    _initialise(data);
    final Expense? existing = widget.expenseId == null
        ? null
        : data.expenses.where((Expense e) => e.id == widget.expenseId).firstOrNull;
    final List<ExpenseCategory> categories = data.expenseCategoriesForType(_transactionType);
    final Color typeColor = _transactionType == TransactionType.income
        ? const Color(0xFF66BB6A)
        : AppColors.gold;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Add $_typeLabel' : 'Edit $_typeLabel'),
        actions: <Widget>[
          if (existing != null)
            IconButton(
              tooltip: 'Delete ${_typeLabel.toLowerCase()}',
              onPressed: () => _delete(existing),
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
          TextButton(
            onPressed: _saving ? null : () => _save(data),
            child: Text(_saving ? 'Saving…' : 'Save', style: TextStyle(color: typeColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pagePadding),
        children: <Widget>[
          SectionCard(
            title: 'Transaction details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PillSelector<TransactionType>(
                  selected: _transactionType,
                  onChanged: (TransactionType type) => _changeType(type, data),
                  options: const <PillOption<TransactionType>>[
                    PillOption<TransactionType>(value: TransactionType.expense, label: 'Expense'),
                    PillOption<TransactionType>(value: TransactionType.income, label: 'Income'),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Amount', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    hintText: '0.00',
                    filled: true,
                    fillColor: AppColors.field,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimens.radiusMd), borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimens.radiusMd), borderSide: BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Date', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                _FieldTile(icon: Icons.calendar_today_outlined, value: _dateLabel(_date), onTap: _chooseDate),
                const SizedBox(height: 18),
                Row(children: <Widget>[
                  Expanded(child: Text('Category', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                  TextButton.icon(onPressed: _addCategory, icon: const Icon(Icons.add, size: 18), label: const Text('New category')),
                ]),
                DropdownButtonFormField<String>(
                  value: categories.any((ExpenseCategory c) => c.id == _categoryId) ? _categoryId : null,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceRaised,
                  decoration: const InputDecoration(filled: true, border: OutlineInputBorder()),
                  hint: const Text('Choose category'),
                  items: categories.map((ExpenseCategory c) => DropdownMenuItem<String>(
                    value: c.id,
                    child: Row(children: <Widget>[Icon(_categoryIcon(c.iconKey), color: Color(c.colorValue), size: 20), const SizedBox(width: 10), Text(c.name)]),
                  )).toList(),
                  onChanged: (String? value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 18),
                Text('Description (optional)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TickTextField(
                  controller: _description,
                  hintText: _transactionType == TransactionType.income
                      ? 'e.g. November salary'
                      : 'What was this expense for?',
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                Text(_transactionType == TransactionType.income ? 'Received via' : 'Payment method', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  dropdownColor: AppColors.surfaceRaised,
                  decoration: const InputDecoration(filled: true, border: OutlineInputBorder()),
                  items: _paymentMethods.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (String? value) => setState(() => _paymentMethod = value ?? _paymentMethods.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(data),
              style: FilledButton.styleFrom(backgroundColor: typeColor, foregroundColor: Colors.black),
              child: Text(
                existing == null ? 'Save $_typeLabel' : 'Update $_typeLabel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({required this.icon, required this.value, required this.onTap});
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.field,
    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: <Widget>[
          Icon(icon, color: AppColors.gold, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ]),
      ),
    ),
  );
}

IconData _categoryIcon(String key) => switch (key) {
  'restaurant' => Icons.restaurant_rounded,
  'directions_car' => Icons.directions_car_rounded,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'school' => Icons.school_outlined,
  'movie' => Icons.movie_outlined,
  'medical_services' => Icons.medical_services_outlined,
  'receipt_long' => Icons.receipt_long_outlined,
  'person' => Icons.person_outline_rounded,
  'payments' => Icons.payments_outlined,
  'work' => Icons.work_outline_rounded,
  'business' => Icons.business_outlined,
  'trending_up' => Icons.trending_up_rounded,
  'savings' => Icons.savings_outlined,
  'card_giftcard' => Icons.card_giftcard_rounded,
  'more_horiz' => Icons.more_horiz_rounded,
  _ => Icons.category_outlined,
};
