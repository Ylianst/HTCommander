/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/widgets.dart';

/// Inherited flag telling a tab's subtree whether it is the currently-shown tab.
///
/// The main window uses a [TabBarView] whose tabs are marked
/// `AutomaticKeepAliveClientMixin`, so hidden tabs are kept alive (to preserve
/// scroll position and state) rather than disposed. Flutter does not *paint*
/// those off-screen tabs, but their DataBroker subscriptions, timers and stream
/// listeners keep firing — which for a high-frequency source (audio frames, a
/// spectrogram FFT, packet lists) is real, wasted CPU.
///
/// Wrapping each tab with a [TabVisibility] lets its widgets cheaply learn
/// whether they are on-screen and skip that work while hidden. Read it in
/// `build` with [TabVisibility.of] (which subscribes to changes), or cache it in
/// `didChangeDependencies` when the value is needed inside a callback that runs
/// outside of `build` (e.g. a broker handler).
class TabVisibility extends InheritedWidget {
  const TabVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  /// Whether the enclosing tab is the one currently selected/shown.
  final bool visible;

  /// The visibility of the nearest enclosing tab. Defaults to `true` when there
  /// is no [TabVisibility] ancestor (e.g. a tab shown outside the TabBarView,
  /// such as in a detached window), so callers degrade to "always visible".
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TabVisibility>();
    return scope?.visible ?? true;
  }

  @override
  bool updateShouldNotify(TabVisibility oldWidget) =>
      visible != oldWidget.visible;
}

/// Mixin that makes a tab's [State] skip rebuilds while the tab is hidden.
///
/// TabBarView keeps hidden tabs alive, so their DataBroker callbacks keep
/// arriving and calling [setState] even though nothing they draw is visible —
/// each of those rebuilds a subtree that is never painted. This mixin overrides
/// [setState] so that, while hidden, the state mutation is still applied but the
/// rebuild is skipped. Because the state also depends on [TabVisibility], the
/// framework rebuilds the tab automatically the moment it becomes visible again,
/// showing whatever state accumulated while it was off-screen — so nothing is
/// ever stale, there is just no wasted work in between.
///
/// Add it after [AutomaticKeepAliveClientMixin]:
/// ```dart
/// class _FooTabState extends State<FooTab>
///     with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
/// ```
/// Callbacks doing heavy *non*-setState work (e.g. an FFT) should additionally
/// early-return on `!isTabVisible`.
mixin TabVisibilityStateMixin<T extends StatefulWidget> on State<T> {
  bool _tabVisible = true;

  /// Whether this tab is the one currently shown.
  bool get isTabVisible => _tabVisible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading TabVisibility registers a dependency, so this re-runs (and a
    // rebuild is scheduled) whenever the tab is shown or hidden.
    final bool visible = TabVisibility.of(context);
    if (visible != _tabVisible) {
      _tabVisible = visible;
      onTabVisibilityChanged(visible);
    }
  }

  /// Called whenever the tab transitions between shown and hidden. Override to
  /// start/stop work that should only run while on-screen — e.g. poll timers or
  /// live captures. Not called for the initial (visible) build.
  void onTabVisibilityChanged(bool visible) {}

  @override
  void setState(VoidCallback fn) {
    if (_tabVisible) {
      super.setState(fn);
    } else {
      // Apply the change but skip the rebuild while off-screen. The
      // visibility-driven rebuild on becoming visible reflects it.
      fn();
    }
  }
}

