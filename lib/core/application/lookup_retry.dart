import '../errors/app_failure.dart';

/// Retry policy for dropdown and picker lists (`retry:` on their providers).
/// The app turns automatic retry off for screens, which show their own
/// "Try again"; a dropdown has no such button, so a list that fails to load
/// is tried again after 1, 2 and 4 seconds. Failures a retry can't fix
/// (signed out, no access, not found, rejected input) aren't retried.
Duration? lookupRetry(int retryCount, Object error) {
  if (retryCount >= 3) return null;
  if (error is UnauthorizedFailure || error is ForbiddenFailure || error is NotFoundFailure || error is ValidationFailure) {
    return null;
  }
  return Duration(seconds: 1 << retryCount);
}
