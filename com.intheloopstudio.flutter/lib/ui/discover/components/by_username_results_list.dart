import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/search_bloc/search_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_tile.dart';

class ByUsernameResultsList extends StatelessWidget {
  const ByUsernameResultsList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state.loading) {
          return const GlassLoading();
        }

        return state.searchResults.isEmpty
            ? const GlassEmptyState(
                icon: CupertinoIcons.search,
                title: 'no one found',
                message: 'try a different name or username',
              )
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(
                  top: TappedSpacing.sm,
                  bottom: GlassMetrics.bottomBarClearance,
                ),
                itemCount: state.searchResults.length,
                itemBuilder: (context, index) {
                  final user = state.searchResults[index];
                  return UserTile(
                    userId: user.id,
                    user: Option.of(user),
                  );
                },
              );
      },
    );
  }
}
