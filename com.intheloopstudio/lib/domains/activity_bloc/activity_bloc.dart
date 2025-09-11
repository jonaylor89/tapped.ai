import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/domains/models/activity.dart';
import 'package:intheloopapp/utils/app_logger.dart';

part 'activity_event.dart';
part 'activity_state.dart';

class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  ActivityBloc({
    required this.databaseRepository,
    required this.authenticationBloc,
  }) : super(const ActivityInitial()) {
    currentUserId =
        (authenticationBloc.state as Authenticated).currentAuthUser.uid;
    on<AddActivityEvent>(
      (event, emit) async {
        emit(
          ActivitySuccess(
            activities: List.of(state.activities)..add(event.activity),
          ),
        );
        await FlutterAppBadger.updateBadgeCount(state.unreadActivitiesCount);
      },
    );
    on<InitListenerEvent>(
      (event, emit) => _mapInitListenerEventToState(emit),
    );
    on<FetchActivitiesEvent>(
      (event, emit) => _mapFetchActivitiesEventToState(emit),
    );
    on<MarkActivityAsReadEvent>(
      (event, emit) => _mapMarkActivityAsReadEventToState(emit, event.activity),
    );
    on<MarkAllAsReadEvent>(
      (event, emit) async {
        if (state is ActivitySuccess) {
          await FlutterAppBadger.updateBadgeCount(0);
          final activities = (state as ActivitySuccess).activities;
          for (final activity in activities) {
            await _mapMarkActivityAsReadEventToState(emit, activity);
          }
        }
      },
    );
  }
  DatabaseRepository databaseRepository;
  AuthenticationBloc authenticationBloc;
  late String currentUserId;

  Future<void> _mapInitListenerEventToState(
    Emitter<ActivityState> emit,
  ) async {
    emit(const ActivityInitial());

    try {
      final activitiesAvailable = (await databaseRepository.getActivities(
        currentUserId,
        limit: 1,
      ))
          .isNotEmpty;

      if (!activitiesAvailable) {
        emit(const ActivitySuccess());
      }

      final activityStream =
          databaseRepository.activitiesObserver(currentUserId);

      await for (final activity in activityStream) {
        emit(
          ActivitySuccess(
            activities: List.of(state.activities)..add(activity),
          ),
        );
      }
    } catch (e, s) {
      logger.error(
        'Error initializing activity listener',
        error: e,
        stackTrace: s,
      );
      emit(const ActivityFailure());
    }
  }

  Future<void> _mapFetchActivitiesEventToState(
    Emitter<ActivityState> emit,
  ) async {
    if (state is ActivityEnd) return;

    try {
      if (state is ActivityInitial) return;

      final activities = await databaseRepository.getActivities(
        currentUserId,
        lastActivityId: state.activities.last.id,
      );

      activities.isEmpty
          ? emit(ActivityEnd(activities: state.activities))
          : emit(
              ActivitySuccess(
                activities: List.of(state.activities)..addAll(activities),
              ),
            );
    } catch (e, s) {
      logger.error(
        'error fetching activities',
        error: e,
        stackTrace: s,
      );
      emit(const ActivityFailure());
    }
  }

  Future<void> _mapMarkActivityAsReadEventToState(
    Emitter<ActivityState> emit,
    Activity activity,
  ) async {
    try {
      if (activity.markedRead) return;

      final idx = state.activities.indexOf(activity);
      final updatedActivity = activity.copyAsRead();

      if (idx != -1) {
        await FlutterAppBadger.removeBadge();
        emit(
          ActivitySuccess(
            activities: state.activities..[idx] = updatedActivity,
          ),
        );
      }

      await databaseRepository.markActivityAsRead(updatedActivity);
    } catch (e, s) {
      logger.error(
        'error marking activity as read',
        error: e,
        stackTrace: s,
      );
      emit(const ActivityFailure());
    }
  }
}
