import 'package:flutter_riverpod/flutter_riverpod.dart';

extension FreshRead on WidgetRef {
  /// Reads a list for a picker that is opening. If the last load failed or
  /// came back empty (as it does offline), it is fetched again first, so a
  /// dropdown fills in once the phone is back online.
  Future<T> fresh<T>(FutureProvider<T> provider, {bool Function(T value)? isEmpty}) {
    if (isStale(provider, isEmpty: isEmpty)) invalidate(provider);
    return read(provider.future);
  }

  /// Whether [provider] failed, or loaded nothing.
  bool isStale<T>(FutureProvider<T> provider, {bool Function(T value)? isEmpty}) {
    final now = read(provider);
    if (now.hasError) return true;
    final v = now.value;
    if (v == null) return false;
    return isEmpty?.call(v) ?? (v is Iterable && v.isEmpty);
  }
}
