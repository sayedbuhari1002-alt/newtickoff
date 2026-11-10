# Suggested Next ListTile Material fix

## Issue
The Productivity widget test failed when Suggested Next displayed task recommendations. Each tappable ListTile was placed inside the `_Panel` Container decoration without its own Material surface. Flutter reported that the decorated background could hide the ListTile background and ink splash.

## Fix
Wrapped each Suggested Next ListTile in `Material(color: Colors.transparent)`. This gives the ListTile its own Material ancestor so its ink effects paint above the panel decoration. The existing layout, colors, labels, recommendation logic, and navigation remain unchanged.

## Validation
The change was checked against the failure reported in the supplied GitHub Actions log. Run the GitHub Actions workflow after committing to verify the widget test and complete release pipeline.
