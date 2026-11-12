# Tazkiyane 0.6.4+27 — income and expense analytics

## Money transaction entry

- The existing expense form now supports both Expense and Income transactions.
- Income records can be assigned to Salary, Freelance, Business, Investment, Interest, Gift, or Other income categories.
- Users can create additional income categories separately from expense categories.
- Income and expense entries retain amount in integer paise, date, category, description, and payment method/receipt method.
- Daily Log offers separate Add Income and Add Expense shortcuts and shows income, expenses, and daily net cash flow.

## Finance analytics

- Preserved total expenses, daily spending average, highest spending day, expense transaction count, zero-expense days, expense-by-category breakdown, and daily spending chart.
- Added total income, daily income average, income transaction count, highest income day, and income-by-source breakdown.
- Added net cash flow, calculated as total income minus total expenses.
- Added top spending category and top income source summary cards, while retaining full percentage breakdowns.
- Added a daily income-versus-expense bar chart and a transaction summary for the selected month.
- Month navigation and the existing date-based reporting window remain in place.

## Database compatibility

- Advanced the SQLite schema from version 9 to version 10.
- Added `transaction_type` to financial transaction and category tables.
- Existing records migrate as `expense`; existing expense category IDs and all historical amounts/dates are retained.
- Seeded separate built-in income categories through an additive migration.

## Verification

- Added tests for income transaction JSON compatibility, SQLite round-trip persistence, and version-9 database migration without data loss.
- Source-level checks and archive-integrity validation are performed for this package. Flutter/Dart tests and APK compilation must still be run in the project's GitHub Actions environment if the SDK is unavailable locally.
