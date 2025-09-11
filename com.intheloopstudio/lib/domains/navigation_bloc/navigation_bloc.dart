import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

part 'navigation_event.dart';

part 'navigation_state.dart';

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  /// build the bloc and defines event handlers
  NavigationBloc({
    required this.database,
    required this.navigationKey,
  }) : super(const NavigationState()) {
    on<Push>((event, emit) {
      final route = event.route;
      navigationKey.currentState?.push(
        MaterialWithModalsPageRoute<Widget>(
          settings: RouteSettings(name: route.routeName),
          builder: (context) => Material(
            child: route.view,
          ),
        ),
      );
      emit(state);
    });
    on<Pop>((event, emit) {
      try {
        navigationKey.currentState?.pop();

        emit(state);
      } catch (e, s) {
        logger.error(
          'error popping route',
          error: e,
          stackTrace: s,
        );
      }
    });
  }

  final DatabaseRepository database;
  final GlobalKey<NavigatorState> navigationKey;
}

extension RoutingHelpers on NavigationBloc {
  void push(TappedRoute route) {
    add(Push(route));
  }

  void pop() {
    add(const Pop());
  }

  void popUntilHome() {
    navigationKey.currentState?.popUntil((route) => route.isFirst);
  }
}

extension Routing on BuildContext {
  void push(TappedRoute route) {
    read<NavigationBloc>().add(Push(route));
  }

  void pop() {
    read<NavigationBloc>().add(const Pop());
  }

  void popUntilHome() {
    read<NavigationBloc>().popUntilHome();
  }
}
