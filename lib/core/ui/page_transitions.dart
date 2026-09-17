import 'package:flutter/material.dart';
import 'package:notes/core/theme/tokens.dart';

/// How a page pushed with a [MaterialPageRoute] arrives and leaves.
///
/// Android's own transition, with its predictive back gesture, but held to
/// [Motion.page]: Flutter's default runs 450ms, past the 300ms every motion in
/// the app keeps under. With reduced motion asked for, the page cross-fades
/// over [Motion.reduced] instead.
class AppPageTransitions extends PageTransitionsBuilder {
  const AppPageTransitions();

  static const _android = PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Duration get reverseTransitionDuration => Motion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      // The route's clock still runs for [Motion.page]; the fade is done in
      // the first stretch of it.
      final fadeEnd =
          Motion.reduced.inMilliseconds / Motion.page.inMilliseconds;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Interval(0, fadeEnd),
        ),
        child: child,
      );
    }
    return _android.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
