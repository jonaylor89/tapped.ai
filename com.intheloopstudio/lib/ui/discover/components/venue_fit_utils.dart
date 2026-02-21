import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/user_model.dart';

bool isVenueGoodFit(UserModel currentUser, UserModel venue) {
  final category = currentUser.performerInfo.map((t) => t.category);
  final userGenres = currentUser.performerInfo
      .map((t) => t.genres)
      .getOrElse(() => []);
  final goodCapFit = venue.venueInfo
      .flatMap((t) => t.capacity)
      .map2(category, (cap, cat) {
    return cat.suggestedMaxCapacity >= cap;
  }).getOrElse(() => false);
  final genreFit = venue.venueInfo.map((t) {
    final one = Set<String>.from(t.genres.map((e) => e.toLowerCase()));
    final two = Set<String>.from(userGenres.map((e) => e.toLowerCase()));
    final intersect = one.intersection(two);
    return intersect.isNotEmpty;
  }).getOrElse(() => false);

  return goodCapFit && genreFit;
}

List<UserModel> sortVenuesByFit(UserModel currentUser, List<UserModel> venues) {
  return List<UserModel>.from(venues)
    ..sort((a, b) {
      final aFit = isVenueGoodFit(currentUser, a);
      final bFit = isVenueGoodFit(currentUser, b);
      if (aFit && !bFit) return -1;
      if (!aFit && bFit) return 1;
      return 0;
    });
}
