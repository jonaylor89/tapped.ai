class TypesenseConfig {
  static const String host = String.fromEnvironment(
    'TYPESENSE_HOST',
    defaultValue: '46.225.133.198',
  );

  static const String port = String.fromEnvironment(
    'TYPESENSE_PORT',
    defaultValue: '8108',
  );

  static const String protocol = String.fromEnvironment(
    'TYPESENSE_PROTOCOL',
    defaultValue: 'http',
  );

  static const String searchApiKey = String.fromEnvironment(
    'TYPESENSE_SEARCH_API_KEY',
    defaultValue: 'sRkjhWNnQ5klpbiH98F3Qhr2S9Ynyzx4',
  );
}
