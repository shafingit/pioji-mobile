/// Every error a repository can return. Widgets never see `DioException`.
sealed class AppFailure implements Exception {
  const AppFailure();

  /// One user-facing sentence.
  String get message;
}

class OfflineFailure extends AppFailure {
  const OfflineFailure();
  @override
  String get message => "You're offline. Check your connection and try again.";
}

class TimeoutFailure extends AppFailure {
  const TimeoutFailure();
  @override
  String get message => 'The server is taking too long. Try again.';
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([this.serverMessage]);
  final String? serverMessage;
  @override
  String get message => serverMessage ?? 'Your session expired. Sign in again.';
}

class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure();
  @override
  String get message => "You don't have access to this.";
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure();
  @override
  String get message => "We couldn't find that. It may have been removed.";
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(this.serverMessage, this.fieldErrors);
  final String serverMessage;
  final Map<String, String> fieldErrors;
  @override
  String get message =>
      fieldErrors.isEmpty ? serverMessage : 'Check the highlighted fields.';
}

class DuplicateFailure extends AppFailure {
  const DuplicateFailure(this.serverMessage);
  final String serverMessage;
  @override
  String get message => serverMessage;
}

class ServerFailure extends AppFailure {
  const ServerFailure([this.status, this.serverMessage]);
  final int? status;

  /// The server's own message. On 500s it can contain SQL or a stack trace,
  /// so it is shown only when it reads as a plain sentence.
  final String? serverMessage;
  @override
  String get message => plainServerMessage(serverMessage) ?? 'Something went wrong on our side. Try again.';
}

final _technical = RegExp(
  r'sql|select |insert |update |delete from|database|exception|error:|stack|trace|\.php|::|->|undefined|call to|null|column|table|syntax|\{|\}|\\',
  caseSensitive: false,
);

/// [m] when it is a short, plain sentence meant for people (such as "No
/// unbatched samples found for 2026-11-20"), otherwise null.
String? plainServerMessage(String? m) {
  final t = m?.trim();
  if (t == null || t.isEmpty || t.length > 160 || t.contains('\n')) return null;
  if (t.toLowerCase() == 'server error' || _technical.hasMatch(t)) return null;
  return t;
}

class UnknownFailure extends AppFailure {
  const UnknownFailure(this.error);
  final Object error;
  @override
  String get message => 'Something went wrong. Try again.';
}
