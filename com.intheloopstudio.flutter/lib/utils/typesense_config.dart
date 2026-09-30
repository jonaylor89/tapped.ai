class TypesenseConfig {
  static const String host = String.fromEnvironment(
    'TYPESENSE_HOST',
    defaultValue: 'search.tapped.ai',
  );

  static const String port = String.fromEnvironment(
    'TYPESENSE_PORT',
    defaultValue: '443',
  );

  static const String protocol = String.fromEnvironment(
    'TYPESENSE_PROTOCOL',
    defaultValue: 'https',
  );

  static const String searchApiKey = String.fromEnvironment(
    'TYPESENSE_SEARCH_API_KEY',
    defaultValue: 'sRkjhWNnQ5klpbiH98F3Qhr2S9Ynyzx4',
  );
}
