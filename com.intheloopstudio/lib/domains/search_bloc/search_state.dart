part of 'search_bloc.dart';

class SearchState extends Equatable {
  const SearchState({
    this.searchResults = const [],
    this.searchTerm = '',
    this.lastRememberedSearchTerm = '',
    this.loading = false,
    this.occupations = const [],
    this.genres = const [],
    this.labels = const [],
    this.place = const None(),
    this.placeId = const None(),
  });

  final List<UserModel> searchResults;
  final String searchTerm;
  final String lastRememberedSearchTerm;

  final List<String> occupations;
  final List<Genre> genres;
  final List<String> labels;

  final Option<PlaceData> place;
  final Option<String> placeId;

  final bool loading;

  bool get isNotSearching => searchTerm.isEmpty &&
      occupations.isEmpty &&
      genres.isEmpty &&
      labels.isEmpty &&
      place.isNone() &&
      placeId.isNone();

  @override
  List<Object?> get props => [
        searchResults,
        searchTerm,
        lastRememberedSearchTerm,
        loading,
        occupations,
        genres,
        labels,
        place,
        placeId,
      ];

  SearchState copyWith({
    List<UserModel>? searchResults,
    String? searchTerm,
    String? lastRememberedSearchTerm,
    List<String>? occupations,
    List<Genre>? genres,
    List<String>? labels,
    Option<PlaceData>? place,
    Option<String>? placeId,
    bool? loading,
  }) {
    return SearchState(
      searchResults: searchResults ?? this.searchResults,
      searchTerm: searchTerm ?? this.searchTerm,
      lastRememberedSearchTerm:
          lastRememberedSearchTerm ?? this.lastRememberedSearchTerm,
      occupations: occupations ?? this.occupations,
      genres: genres ?? this.genres,
      labels: labels ?? this.labels,
      place: place ?? this.place,
      placeId: placeId ?? this.placeId,
      loading: loading ?? this.loading,
    );
  }
}
