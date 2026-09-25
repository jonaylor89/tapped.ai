import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_background.dart';
import 'package:intheloopapp/ui/design/glass/glass_button.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// The standard pushed screen.
///
/// There is no opaque navigation bar. Content is full-bleed and scrolls
/// underneath a row of floating glass controls (back on the left, actions on
/// the right). The title starts large at the top of the content and, as it
/// scrolls away, an inline glass title pill fades in between the controls —
/// the iOS large-title behaviour, rebuilt for floating chrome.
///
/// Supply either [slivers] (preferred) or [child] (wrapped in
/// `SliverFillRemaining`). [bottomBar] floats over the bottom edge and the
/// scroll view is padded so content can clear it.
class GlassPage extends StatefulWidget {
  const GlassPage({
    this.title,
    this.slivers,
    this.child,
    this.actions = const [],
    this.leading,
    this.showBack = true,
    this.bottomBar,
    this.largeTitle = true,
    this.scrollController,
    this.onRefresh,
    this.padding = const EdgeInsets.symmetric(horizontal: GlassMetrics.edgeInset),
    this.subtitle,
    this.background,
    super.key,
  }) : assert(
          slivers != null || child != null,
          'Provide slivers or a child',
        );

  final String? title;
  final String? subtitle;
  final List<Widget>? slivers;
  final Widget? child;

  /// Floating controls on the right, usually [GlassIconButton]s.
  final List<Widget> actions;

  /// Replaces the default back button.
  final Widget? leading;
  final bool showBack;

  /// A floating bottom control cluster, usually a [GlassButton.primary].
  final Widget? bottomBar;

  /// Show the large title above the content. Set false for modal-style pages
  /// that only need the inline title.
  final bool largeTitle;
  final ScrollController? scrollController;
  final Future<void> Function()? onRefresh;

  /// Horizontal padding applied to the large title only. Content padding is
  /// the caller's responsibility so full-bleed rows remain possible.
  final EdgeInsets padding;

  /// Replaces the ambient background (e.g. a hero image).
  final Widget? background;

  @override
  State<GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<GlassPage> {
  late final ScrollController _controller =
      widget.scrollController ?? ScrollController();
  double _inlineOpacity = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (widget.scrollController == null) _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final offset = _controller.offset;
    final threshold = widget.largeTitle ? GlassMetrics.navBarLargeTitle : 0.0;
    final next = ((offset - threshold + 24) / 24).clamp(0.0, 1.0);
    if (next != _inlineOpacity) setState(() => _inlineOpacity = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final chromeHeight = topInset + GlassMetrics.navBarInline;
    final title = widget.title;

    final slivers = <Widget>[
      SliverToBoxAdapter(child: SizedBox(height: chromeHeight)),
      if (widget.onRefresh != null)
        CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
      if (title != null && widget.largeTitle)
        SliverToBoxAdapter(
          child: Padding(
            padding: widget.padding.copyWith(
              top: TappedSpacing.xs,
              bottom: TappedSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: TappedSpacing.xs),
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (widget.slivers != null) ...widget.slivers!,
      if (widget.child != null)
        SliverFillRemaining(hasScrollBody: false, child: widget.child!),
      SliverToBoxAdapter(
        child: SizedBox(
          height: widget.bottomBar != null
              ? GlassMetrics.bottomBarClearance + bottomInset
              : TappedSpacing.xxxl + bottomInset,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.background ?? const GlassAmbientBackground(),
          CustomScrollView(
            controller: _controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: slivers,
          ),
          GlassNavChrome(
            title: title,
            inlineOpacity: widget.largeTitle ? _inlineOpacity : 1,
            leading: widget.leading,
            showBack: widget.showBack,
            actions: widget.actions,
          ),
          if (widget.bottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomBar(child: widget.bottomBar!),
            ),
        ],
      ),
    );
  }
}

/// The floating top controls: back/close, inline title pill, actions.
///
/// Reusable on screens that own their scroll view (profile, map).
class GlassNavChrome extends StatelessWidget {
  const GlassNavChrome({
    this.title,
    this.inlineOpacity = 1,
    this.leading,
    this.showBack = true,
    this.actions = const [],
    this.onBack,
    this.backIcon,
    super.key,
  });

  final String? title;
  final double inlineOpacity;
  final Widget? leading;
  final bool showBack;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final IconData? backIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    final leadingWidget = leading ??
        (showBack && canPop
            ? GlassIconButton(
                icon: backIcon ?? CupertinoIcons.chevron_back,
                onPressed: onBack ?? () => context.pop(),
                semanticsLabel: 'back',
              )
            : null);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GlassMetrics.edgeInset,
            vertical: TappedSpacing.xs,
          ),
          child: SizedBox(
            height: GlassMetrics.iconControl,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (title != null)
                  IgnorePointer(
                    ignoring: inlineOpacity < 0.5,
                    child: AnimatedOpacity(
                      opacity: inlineOpacity,
                      duration: GlassMotion.reveal,
                      child: LiquidGlass.capsule(
                        height: 38,
                        padding: const EdgeInsets.symmetric(
                          horizontal: TappedSpacing.lg,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.sizeOf(context).width * 0.5,
                            ),
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    if (leadingWidget != null) leadingWidget,
                    const Spacer(),
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: TappedSpacing.sm),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating bottom container with a soft fade so scrolling content dims as
/// it approaches the controls. Children are laid out in a row.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.85)],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: TappedSpacing.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GlassMetrics.edgeInset,
            TappedSpacing.xxl,
            GlassMetrics.edgeInset,
            TappedSpacing.sm,
          ),
          child: child,
        ),
      ),
    );
  }
}
