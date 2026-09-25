import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/create_service/components/description_text_field.dart';
import 'package:intheloopapp/ui/create_service/components/edit_service_button.dart';
import 'package:intheloopapp/ui/create_service/components/rate_type_selector.dart';
import 'package:intheloopapp/ui/create_service/components/submit_service_button.dart';
import 'package:intheloopapp/ui/create_service/components/title_text_field.dart';
import 'package:intheloopapp/ui/create_service/create_service_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/rate_text_field.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class CreateServiceView extends StatelessWidget {
  const CreateServiceView({
    required this.service,
    required this.onSubmit,
    super.key,
  });

  final Option<Service> service;
  final void Function(Service) onSubmit;

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final nav = context.nav;
    final payments = context.payments;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final ownerId = service.fold(
          () => currentUser.id,
          (value) => value.userId,
        );
        return BlocProvider<CreateServiceCubit>(
          create: (context) => CreateServiceCubit(
            database: database,
            nav: nav,
            ownerId: ownerId,
          )..initFields(service),
          child: GlassPage(
            title: service.isSome() ? 'edit service' : 'new service',
            padding: EdgeInsets.zero,
            bottomBar: switch (service) {
              None() => SubmitServiceButton(onCreated: onSubmit),
              Some(:final value) => EditServiceButton(
                onEdited: onSubmit,
                service: value,
              ),
            },
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TitleTextField(),
                          SizedBox(height: TappedSpacing.md),
                          DescriptionTextField(),
                        ],
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: (() async {
                        if (ownerId == currentUser.id) {
                          return currentUser.hasValidConnectedAccount(payments);
                        }

                        final owner = await database.getUserById(ownerId);
                        return owner.fold(
                          () => Future.value(false),
                          (t) => t.hasValidConnectedAccount(payments),
                        );
                      })(),
                      builder: (context, snapshot) {
                        final isValid = snapshot.data;
                        return switch (isValid) {
                          null => const Padding(
                            padding: EdgeInsets.all(TappedSpacing.xl),
                            child: Center(child: GlassLoading()),
                          ),
                          false => GlassSection(
                            header: 'pricing',
                            children: [
                              GlassListTile(
                                leadingIcon: CupertinoIcons.creditcard,
                                leadingColor: TappedColors.accent,
                                title: 'connect your bank',
                                subtitle:
                                    'required to make this a paid '
                                    'service',
                                onTap: () => context.push(SettingsPage()),
                              ),
                            ],
                          ),
                          true => GlassSection(
                            header: 'pricing',
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(
                                  TappedSpacing.md,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    BlocBuilder<
                                      CreateServiceCubit,
                                      CreateServiceState
                                    >(
                                      builder: (context, state) {
                                        return RateTextField(
                                          initialValue: state.rate,
                                          onChanged: (input) => context
                                              .read<CreateServiceCubit>()
                                              .onRateChange(input),
                                        );
                                      },
                                    ),
                                    const SizedBox(
                                      height: TappedSpacing.md,
                                    ),
                                    const RateTypeSelector(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        };
                      },
                    ),
                    const SizedBox(height: GlassMetrics.bottomBarClearance),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
