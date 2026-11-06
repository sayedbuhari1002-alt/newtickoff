import 'package:flutter/material.dart';

/// Pushes a Material bottom-sheet route and waits until its reverse transition
/// has fully completed and the route's overlay entries have been removed.
///
/// The future returned directly by `Navigator.push` completes when the route
/// is popped. [ModalRoute.completed] is the later lifecycle signal that says
/// the transition itself is over. Waiting for both avoids racing a second
/// navigation operation against a still-dismissing modal.
Future<T?> showModalBottomSheetAndWait<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
}) async {
  final NavigatorState navigator =
      Navigator.of(context, rootNavigator: useRootNavigator);
  final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  final ModalBottomSheetRoute<T> route = ModalBottomSheetRoute<T>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    backgroundColor: backgroundColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    modalBarrierColor:
        barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
  );

  final T? result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

/// Pushes a Material dialog and waits until its reverse transition completes.
///
/// This mirrors the default behavior of `showDialog` (including its root
/// Navigator, captured themes, barrier styling, and caller Theme/MediaQuery)
/// while exposing the route-completion point needed by follow-up navigation.
Future<T?> showDialogAndWait<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useSafeArea = true,
}) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final CapturedThemes themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  final ThemeData theme = Theme.of(context);
  final MediaQueryData mediaQuery = MediaQuery.of(context);
  final TextDirection textDirection = Directionality.of(context);
  final Color resolvedBarrierColor = barrierColor ??
      DialogTheme.of(context).barrierColor ??
      theme.dialogTheme.barrierColor ??
      Colors.black54;

  final DialogRoute<T> route = DialogRoute<T>(
    context: context,
    builder: (BuildContext _) {
      return Directionality(
        textDirection: textDirection,
        child: Theme(
          data: theme,
          child: MediaQuery(
            data: mediaQuery,
            child: Builder(builder: builder),
          ),
        ),
      );
    },
    themes: themes,
    barrierColor: resolvedBarrierColor,
    barrierDismissible: barrierDismissible,
    barrierLabel: localizations.modalBarrierDismissLabel,
    useSafeArea: useSafeArea,
  );

  final T? result = await navigator.push<T>(route);
  await route.completed;
  return result;
}
