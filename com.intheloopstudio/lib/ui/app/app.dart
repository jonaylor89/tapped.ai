import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/domains/bookings_bloc/bookings_bloc.dart';
import 'package:intheloopapp/domains/deep_link_bloc/deep_link_bloc.dart';
import 'package:intheloopapp/domains/down_for_maintenance_bloc/down_for_maintenance_bloc.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/domains/opportunity_bloc/opportunity_bloc.dart';
import 'package:intheloopapp/domains/subscription_bloc/subscription_bloc.dart'
    hide Uninitialized;
import 'package:intheloopapp/ui/app_theme_cubit.dart';
import 'package:intheloopapp/ui/common/down_for_maintenance_view.dart';
import 'package:intheloopapp/ui/loading/loading_view.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_view.dart';
import 'package:intheloopapp/ui/premium_theme_cubit.dart';
import 'package:intheloopapp/ui/shell/shell_view.dart';
import 'package:intheloopapp/ui/splash/splash_view.dart';
import 'package:intheloopapp/ui/themes.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:upgrader/upgrader.dart';

class App extends StatelessWidget {
  const App({
    required this.repositories,
    required this.blocs,
    required this.streamClient,
    required this.navigatorKey,
    super.key,
  });

  final List<RepositoryProvider<Object>> repositories;
  final List<BlocProvider> blocs;
  final StreamChatClient streamClient;
  final GlobalKey<NavigatorState> navigatorKey;

  static final _analytics = FirebaseAnalytics.instance;
  static final _observer = FirebaseAnalyticsObserver(analytics: _analytics);

  Widget _authenticated(
    BuildContext context,
    String currentAuthUserId,
  ) {
    context.subscriptions.add(
      CheckSubscriptionStatus(
        userId: currentAuthUserId,
      ),
    );
    context.onboarding.add(
      OnboardingCheck(
        userId: currentAuthUserId,
      ),
    );
    context.read<DeepLinkBloc>().add(MonitorDeepLinks());

    return BlocBuilder<OnboardingBloc, OnboardingState>(
      builder: (context, onboardState) {
        return switch (onboardState) {
          Onboarded() => () {
              context.notifications.saveDeviceToken(
                userId: currentAuthUserId,
              );
              context.stream.connectUser(currentAuthUserId);
              // context.read<ActivityBloc>().add(InitListenerEvent());
              context.read<OpportunityBloc>().add(const InitQuotaListener());
              context.bookings.add(FetchBookings());
              context.database.publishLatestAppVersion(currentAuthUserId);

              return const ShellView();
            }(),
          Onboarding() => const OnboardingView(),
          Unonboarded() => const LoadingView(),
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    initializeDateFormatting('en-US');

    return MultiRepositoryProvider(
      providers: repositories,
      child: MultiBlocProvider(
        providers: blocs,
        child: BlocBuilder<PremiumThemeCubit, bool>(
          builder: (context, isPremium) {
            // final accentColor = isPremium ? Colors.purple : tappedAccent;
            return BlocBuilder<AppThemeCubit, bool>(
              builder: (context, isDark) {
                final appTheme = isDark ? buildDarkTheme() : buildLightTheme();

                final defaultStreamTheme =
                    StreamChatThemeData.fromTheme(appTheme);
                final streamTheme = defaultStreamTheme;

                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: 'tapped',
                  theme: appTheme,
                  navigatorObservers: <NavigatorObserver>[
                    _observer,
                    PosthogObserver(),
                  ],
                  navigatorKey: navigatorKey,
                  builder: EasyLoading.init(
                    builder: (context, widget) {
                      try {
                        return StreamChat(
                          client: streamClient,
                          streamChatThemeData: streamTheme,
                          child: widget,
                        );
                      } catch (e, s) {
                        FirebaseCrashlytics.instance.recordError(e, s);
                        return widget ?? Container();
                      }
                    },
                  ),
                  home: UpgradeAlert(
                    dialogStyle: UpgradeDialogStyle.cupertino,
                    child: BlocBuilder<DownForMaintenanceBloc,
                        DownForMaintenanceState>(
                      builder: (context, downState) {
                        // return const SplashView();
                        // return const OnboardingView();

                        if (downState.downForMaintenance) {
                          FlutterNativeSplash.remove();
                          return const DownForMainenanceView();
                        }

                        FlutterNativeSplash.remove();
                        return BlocBuilder<AuthenticationBloc,
                            AuthenticationState>(
                          builder: (
                            BuildContext context,
                            AuthenticationState authState,
                          ) {
                            try {
                              return switch (authState) {
                                Uninitialized() => const LoadingView(),
                                Authenticated() => _authenticated(
                                    context,
                                    authState.currentAuthUser.uid,
                                  ),
                                Unauthenticated() => const SplashView(),
                              };
                            } catch (e, s) {
                              FirebaseCrashlytics.instance.recordError(
                                e,
                                s,
                                fatal: true,
                              );
                              FlutterNativeSplash.remove();
                              return const LoadingView();
                            }
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
