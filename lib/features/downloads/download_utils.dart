/// Last path segment of [path], for both Windows (`\`) and POSIX (`/`) paths.
/// Returns [fallback] when there is none.
String fileNameOf(String path, {required String fallback}) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? fallback : parts.last;
}
