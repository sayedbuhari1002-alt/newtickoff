# Progressive Task Slider

Progressive tasks can now be updated directly with a slider instead of entering a number in a dialog.

- Added a shared progress slider to progressive task cards on the Dashboard and Tasks screens, including child tasks inside parent groups.
- Added the same slider to the progressive task details screen.
- Percentage tasks store the selected percentage; count-based tasks convert the slider position to the configured target and unit.
- A drag is committed once when the user releases the slider, so the app records one progress event per adjustment rather than writing on every pointer movement.
- Paused tasks show a message and disable the slider. Moving a completed task below 100% reopens it through the existing progress-update logic.
- Added a widget test that checks count-based slider updates persist and create progress history.
