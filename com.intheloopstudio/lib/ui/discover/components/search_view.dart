import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/discover/components/by_username_results_list.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/components/cancel_icon.dart';
import 'package:intheloopapp/ui/discover/components/tapped_search_bar.dart';

class SearchView extends StatefulWidget {
  SearchView({
    FocusNode? focusNode,
    super.key,
  }) {
    searchFocusNode = focusNode ?? FocusNode();
  }

  late final FocusNode searchFocusNode;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    if (!_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _searchController.dispose();
  }

  late final TextEditingController _searchController;

  FocusNode get _searchFocusNode => widget.searchFocusNode;

  List<Widget> _buildActions() {
    return [
      CancelIcon(
        focusNode: _searchFocusNode,
        searchController: _searchController,
        onTap: context.pop,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GlassMetrics.edgeInset,
                  TappedSpacing.sm,
                  GlassMetrics.edgeInset,
                  TappedSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Expanded(child: TappedSearchBar()),
                    ..._buildActions(),
                  ],
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.06,
                        ),
                      ),
                    ),
                  ),
                  child: const ByUsernameResultsList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
