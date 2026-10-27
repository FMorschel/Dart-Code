import 'dart:convert';

/// Decodes JSON with comments and trailing commas, as used by VS Code files.
///
/// Comments are discarded, so re-encoding the result loses them.
Object? decodeJsonc(String source) {
  final withoutComments = _strip(source, _Mode.comments);
  return jsonDecode(_strip(withoutComments, _Mode.trailingCommas));
}

enum _Mode { comments, trailingCommas }

String _strip(String s, _Mode mode) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') {
      final start = i++;
      while (i < s.length && s[i] != '"') {
        if (s[i] == '\\') i++;
        i++;
      }
      i++;
      out.write(s.substring(start, i.clamp(0, s.length)));
      continue;
    }
    if (mode == _Mode.comments && c == '/' && i + 1 < s.length) {
      if (s[i + 1] == '/') {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        continue;
      }
      if (s[i + 1] == '*') {
        final close = s.indexOf('*/', i + 2);
        i = close == -1 ? s.length : close + 2;
        continue;
      }
    }
    if (mode == _Mode.trailingCommas && c == ',') {
      var j = i + 1;
      while (j < s.length && ' \t\r\n'.contains(s[j])) {
        j++;
      }
      if (j < s.length && (s[j] == '}' || s[j] == ']')) {
        i++;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
