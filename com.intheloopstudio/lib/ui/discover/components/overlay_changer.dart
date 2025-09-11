import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';

class OverlayChanger extends StatelessWidget {
  const OverlayChanger({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      builder: (context, state) {
        final cubit = context.read<DiscoverCubit>();
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  cubit.onMapOverlayChange(
                    MapOverlay.venues,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('showing venues'),
                      dismissDirection: DismissDirection.up,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      margin: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height - 150,
                        left: 10,
                        right: 10,
                      ),
                    ),
                  );
                },
                child: const Icon(CupertinoIcons.building_2_fill),
              ),
              const Divider(),
              InkWell(
                onTap: () {
                  cubit.onMapOverlayChange(
                    MapOverlay.opportunities,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('showing gig opportunities'),
                      dismissDirection: DismissDirection.up,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      margin: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height - 150,
                        left: 10,
                        right: 10,
                      ),
                    ),
                  );
                },
                child: const Icon(CupertinoIcons.money_dollar_circle),
              ),
            ],
          ),
        );
      },
    );
  }
}
