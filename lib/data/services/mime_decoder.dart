// lib/data/services/mime_decoder.dart
// RFC 2047 MIME encoded-word decoder with full charset support
// Handles UTF-7, Windows-1251, KOI8-R, ISO-8859-1, UTF-8
// Needed because enough_mail doesn't decode UTF-7 headers from Outlook/Exchange

import 'dart:convert';
import 'dart:typed_data';

/// Characters valid inside a UTF-7 modified-Base64 block (RFC 2152 §3)
const _b64Set = <int>{
  // A-Z
  0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,
  0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,
  // a-z
  0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,
  0x6E,0x6F,0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,
  // 0-9
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,
  // + /
  0x2B, 0x2F,
};

/// Pre-compiled regex for RFC 2047 encoded-word
final _rfc2047Re = RegExp(r'=\?([^?]+)\?([QqBb])\?([^?]*)\?=');

/// Pre-compiled regex for adjacent encoded-word folding
final _foldedRe = RegExp(r'\?=\s+=\?');

/// Detects raw UTF-7: + followed by ≥3 base64-alphabet characters
final _rawUtf7Re = RegExp(r'\+[A-Za-z0-9+/]{3,}');

class MimeDecoder {
  MimeDecoder._();

  // ── RFC 2047 ────────────────────────────────────────────────────────────────

  /// Decodes an RFC 2047 encoded header string.
  /// Example input:  =?UTF-7?Q?+BBQEPgQxBEAEPg=20+BD=38EPgQ=32BDAEOwQ+BDIEMARCBEwAIQ-?=
  /// Example output: Добро пожаловать!
  static String decodeHeader(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (!raw.contains('=?')) return raw;

    // Handle folded whitespace between adjacent encoded-words (RFC 2047 §6.2)
    var processed = raw.replaceAll(_foldedRe, '?==?');

    final result = StringBuffer();
    int lastEnd = 0;

    for (final match in _rfc2047Re.allMatches(processed)) {
      if (match.start > lastEnd) {
        result.write(processed.substring(lastEnd, match.start));
      }

      final charset = match.group(1)!.trim().toUpperCase();
      final encoding = match.group(2)!.toUpperCase();
      final encodedText = match.group(3)!;

      try {
        Uint8List bytes;
        if (encoding == 'B') {
          bytes = base64Decode(encodedText);
        } else {
          bytes = _decodeQEncoding(encodedText);
        }

        // For UTF-7: Q-decoding gives us ASCII bytes that form a UTF-7 string.
        // We must convert bytes→string first, then decode UTF-7.
        if (charset == 'UTF-7' || charset == 'UTF7') {
          final utf7Str = latin1.decode(bytes);
          result.write(decodeUtf7String(utf7Str));
        } else {
          result.write(_decodeBytes(bytes, charset));
        }
      } catch (e) {
        result.write(match.group(0));
      }

      lastEnd = match.end;
    }

    if (lastEnd < processed.length) {
      result.write(processed.substring(lastEnd));
    }

    return result.toString();
  }

  /// Decode Q-encoded bytes (RFC 2047 §4.2)
  static Uint8List _decodeQEncoding(String input) {
    final bytes = <int>[];
    int i = 0;
    while (i < input.length) {
      if (input[i] == '_') {
        bytes.add(0x20);
        i++;
      } else if (input[i] == '=' && i + 2 < input.length) {
        final hex = input.substring(i + 1, i + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte != null) {
          bytes.add(byte);
          i += 3;
        } else {
          bytes.add(input.codeUnitAt(i));
          i++;
        }
      } else {
        bytes.add(input.codeUnitAt(i));
        i++;
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Decode bytes using the specified charset
  static String _decodeBytes(Uint8List bytes, String charset) {
    switch (charset) {
      case 'UTF-8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'UTF-7':
      case 'UTF7':
        return decodeUtf7String(latin1.decode(bytes));
      case 'WINDOWS-1251':
      case 'CP1251':
      case 'WIN-1251':
        return _decodeWindows1251(bytes);
      case 'KOI8-R':
      case 'KOI8R':
        return _decodeKoi8r(bytes);
      case 'ISO-8859-1':
      case 'LATIN1':
      case 'LATIN-1':
        return latin1.decode(bytes);
      case 'ISO-8859-5':
        return _decodeIso8859_5(bytes);
      case 'US-ASCII':
      case 'ASCII':
        return ascii.decode(bytes, allowInvalid: true);
      default:
        try {
          return utf8.decode(bytes);
        } catch (_) {
          return latin1.decode(bytes);
        }
    }
  }

  // ── UTF-7 Decoder (RFC 2152) ───────────────────────────────────────────────
  // + enters modified-Base64 mode (UTF-16BE payload)
  // Block ends at first char NOT in {A-Za-z0-9+/}
  // If that char is '-', it's consumed; otherwise it stays as literal output
  // +- is a literal +

  /// Decode a UTF-7 encoded string to a Dart string.
  static String decodeUtf7String(String input) {
    final result = StringBuffer();
    int i = 0;

    while (i < input.length) {
      final ch = input.codeUnitAt(i);

      if (ch == 0x2B /* + */) {
        // Check for +- (literal +)
        if (i + 1 < input.length && input.codeUnitAt(i + 1) == 0x2D /* - */) {
          result.write('+');
          i += 2;
          continue;
        }

        // Scan the modified-base64 block: collect chars while they're in _b64Set
        int end = i + 1;
        while (end < input.length && _b64Set.contains(input.codeUnitAt(end))) {
          end++;
        }

        final b64Str = input.substring(i + 1, end);

        if (b64Str.isNotEmpty) {
          // Pad to a multiple of 4
          var padded = b64Str;
          final rem = padded.length % 4;
          if (rem > 0) padded += '=' * (4 - rem);

          try {
            final decoded = base64Decode(padded);
            // UTF-7 payload is UTF-16BE
            for (int j = 0; j + 1 < decoded.length; j += 2) {
              final hi = decoded[j];
              final lo = decoded[j + 1];
              final codeUnit = (hi << 8) | lo;

              // Handle surrogate pairs (emoji, rare CJK)
              if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && j + 3 < decoded.length) {
                final hi2 = decoded[j + 2];
                final lo2 = decoded[j + 3];
                final low = (hi2 << 8) | lo2;
                if (low >= 0xDC00 && low <= 0xDFFF) {
                  final codePoint = 0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00);
                  result.writeCharCode(codePoint);
                  j += 2; // skip the low surrogate
                  continue;
                }
              }
              result.writeCharCode(codeUnit);
            }
          } catch (_) {
            // Can't decode — output verbatim
            result.write('+');
            result.write(b64Str);
          }
        }

        // If terminated by '-', consume it; otherwise keep it for the next iteration
        if (end < input.length && input.codeUnitAt(end) == 0x2D /* - */) {
          i = end + 1;
        } else {
          i = end;
        }
      } else {
        result.writeCharCode(ch);
        i++;
      }
    }

    return result.toString();
  }

  // ── Windows-1251 ───────────────────────────────────────────────────────────

  static const List<int> _win1251Table = [
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0000, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
  ];

  static String _decodeWindows1251(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80) {
        buffer.writeCharCode(byte);
      } else {
        buffer.writeCharCode(_win1251Table[byte - 0x80]);
      }
    }
    return buffer.toString();
  }

  // ── KOI8-R ─────────────────────────────────────────────────────────────────

  static const List<int> _koi8rTable = [
    0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524,
    0x252C, 0x2534, 0x253C, 0x2580, 0x2584, 0x2588, 0x258C, 0x2590,
    0x2591, 0x2592, 0x2593, 0x2320, 0x25A0, 0x2219, 0x221A, 0x2248,
    0x2264, 0x2265, 0x00A0, 0x2321, 0x00B0, 0x00B2, 0x00B7, 0x00F7,
    0x2550, 0x2551, 0x2552, 0x0451, 0x2553, 0x2554, 0x2555, 0x2556,
    0x2557, 0x2558, 0x2559, 0x255A, 0x255B, 0x255C, 0x255D, 0x255E,
    0x255F, 0x2560, 0x2561, 0x0401, 0x2562, 0x2563, 0x2564, 0x2565,
    0x2566, 0x2567, 0x2568, 0x2569, 0x256A, 0x256B, 0x256C, 0x00A9,
    0x044E, 0x0430, 0x0431, 0x0446, 0x0434, 0x0435, 0x0444, 0x0433,
    0x0445, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E,
    0x043F, 0x044F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0436, 0x0432,
    0x044C, 0x044B, 0x0437, 0x0448, 0x044D, 0x0449, 0x0447, 0x044A,
    0x042E, 0x0410, 0x0411, 0x0426, 0x0414, 0x0415, 0x0424, 0x0413,
    0x0425, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E,
    0x041F, 0x042F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0416, 0x0412,
    0x042C, 0x042B, 0x0417, 0x0428, 0x042D, 0x0429, 0x0427, 0x042A,
  ];

  static String _decodeKoi8r(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80) {
        buffer.writeCharCode(byte);
      } else {
        buffer.writeCharCode(_koi8rTable[byte - 0x80]);
      }
    }
    return buffer.toString();
  }

  // ── ISO-8859-5 ─────────────────────────────────────────────────────────────

  static String _decodeIso8859_5(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0xA0) {
        buffer.writeCharCode(byte);
      } else if (byte == 0xAD) {
        buffer.writeCharCode(0x00AD);
      } else if (byte == 0xF0) {
        buffer.writeCharCode(0x2116);
      } else if (byte == 0xFD) {
        buffer.writeCharCode(0x00A7);
      } else if (byte >= 0xA0 && byte <= 0xFF) {
        buffer.writeCharCode(0x0360 + byte);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Checks if a string still contains undecoded MIME encoded-words.
  static bool isEncoded(String? text) {
    if (text == null || text.isEmpty) return false;
    return text.contains('=?') && text.contains('?=');
  }

  /// Smart decode: handles RFC 2047 wrappers AND raw UTF-7 left over
  /// by libraries that partially decoded the header.
  static String safeDecode(String? text) {
    if (text == null || text.isEmpty) return text ?? '';

    var result = text;

    // 1. Try RFC 2047 decoding if markers are present
    if (isEncoded(result)) {
      try {
        result = decodeHeader(result);
      } catch (_) {}
    }

    // 2. If the result still contains raw UTF-7 base64 blocks
    //    (enough_mail may strip =?UTF-7?Q?...?= but leave the UTF-7 payload)
    if (_rawUtf7Re.hasMatch(result)) {
      try {
        final decoded = decodeUtf7String(result);
        // Only accept if it actually decoded something useful
        // (contains non-ASCII = Cyrillic / CJK / etc.)
        if (decoded != result && _containsNonAscii(decoded)) {
          result = decoded;
        }
      } catch (_) {}
    }

    return result;
  }

  /// Returns true if the string contains characters outside basic ASCII
  static bool _containsNonAscii(String s) {
    for (int i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) > 127) return true;
    }
    return false;
  }
}
