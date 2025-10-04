class TypesenseConfig {
  static const String host = String.fromEnvironment(
    'TYPESENSE_HOST',
    defaultValue: '104.197.126.110',
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
    defaultValue: 'wVoV9Wg2dS7qLVRegvoLor2AvXmUypqr',
  );
}
