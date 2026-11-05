import 'package:flutter/material.dart';

/// Waits for a modal route to finish its reverse transition before another
/// route operation is issued against the same Navigator.
///
/// Modal presentation futures can resolve as the route starts popping. The
/// small transition buffer prevents a subsequent pop/replace from consuming
/// the still-dismissing bottom sheet or dialog instead of the page beneath it.
Future<void> waitForModalDismissal() async {
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 350));
}
