/// What failed in a [HybridPrefsError].
enum HybridPrefsErrorKind {
  /// Reading from the secure store failed.
  secureRead,

  /// Writing to the secure store failed.
  secureWrite,

  /// Deleting from the secure store failed.
  secureDelete,

  /// A stored value couldn't be decoded to the key's type.
  decode,
}

/// A failure reported to `HybridPrefs.init(onError: ...)`. These are
/// reported whether or not HybridPrefs recovered from them.
class HybridPrefsError {
  /// Creates an error report.
  const HybridPrefsError(this.key, this.kind, this.error, this.stackTrace);

  /// Name of the key involved.
  final String key;

  /// What failed.
  final HybridPrefsErrorKind kind;

  /// The underlying error.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String toString() => 'HybridPrefsError(${kind.name}, "$key"): $error';
}

/// Receives every [HybridPrefsError].
typedef HybridPrefsErrorCallback = void Function(HybridPrefsError error);
