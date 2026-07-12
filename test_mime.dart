// Quick test for MimeDecoder UTF-7 decoding
// Run: dart run test_mime.dart

import 'lib/data/services/mime_decoder.dart';

void main() {
  // Test 1: Raw UTF-7 from screenshot (what enough_mail returns after partial decoding)
  final raw1 = '+BB0EMARHBDAEOwQ+ +BEAEMAQxBD4EQgRL +BEE Tilda';
  final decoded1 = MimeDecoder.safeDecode(raw1);
  print('Test 1 (raw UTF-7):');
  print('  Input:   $raw1');
  print('  Output:  $decoded1');
  print('  OK: ${decoded1 != raw1}');
  print('');

  // Test 2: Full RFC 2047 encoded-word with UTF-7
  final raw2 = '=?UTF-7?Q?+BBQEPgQxBEAEPg=20+BD=38EPgQ=32BDAEOwQ+BDIEMARCBEwAIQ-?=';
  final decoded2 = MimeDecoder.safeDecode(raw2);
  print('Test 2 (RFC 2047 + UTF-7):');
  print('  Input:   $raw2');
  print('  Output:  $decoded2');
  print('  OK: ${decoded2 != raw2}');
  print('');

  // Test 3: UTF-8 Base64 encoded (common case)
  final raw3 = '=?UTF-8?B?0JTQvtCx0YDQviDQv9C+0LbQsNC70L7QstCw0YLRjCE=?=';
  final decoded3 = MimeDecoder.safeDecode(raw3);
  print('Test 3 (RFC 2047 + UTF-8 B64):');
  print('  Input:   $raw3');
  print('  Output:  $decoded3');
  print('  Expected: Добро пожаловать!');
  print('  OK: ${decoded3 == "Добро пожаловать!"}');
  print('');

  // Test 4: Already decoded text (should pass through)
  final raw4 = 'Обычная тема письма';
  final decoded4 = MimeDecoder.safeDecode(raw4);
  print('Test 4 (pass-through):');
  print('  Input:   $raw4');
  print('  Output:  $decoded4');
  print('  OK: ${decoded4 == raw4}');
}
