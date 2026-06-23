enum PosKeyboardLanguage {
  georgian('ka', 'ქართული'),
  english('en', 'English');

  const PosKeyboardLanguage(this.code, this.label);

  final String code;
  final String label;

  static PosKeyboardLanguage fromCode(String code) {
    return code.toLowerCase().trim() == english.code ? english : georgian;
  }
}
