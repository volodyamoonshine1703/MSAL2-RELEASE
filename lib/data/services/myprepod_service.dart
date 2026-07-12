import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'local_db_service.dart';
import '../../core/utils/log.dart' as logger;

class MyprepodData {
  final String rating;
  final List<String> reviews;
  MyprepodData({required this.rating, this.reviews = const []});
}

class MyprepodService {
  final Ref ref;
  MyprepodService(this.ref);

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.5',
    },
  ));

  /// L1 cache: in-memory for current session
  final Map<String, MyprepodData?> _cache = {};

  String _cleanName(String name) {
    // Remove everything in parentheses first
    String clean = name.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    // Remove academic titles and degrees
    clean = clean.replaceAll(RegExp(
      r'\b(профессор|доцент|ст\.?\s*преп\.?|ассистент|д\.?\s*ю\.?\s*н\.?|к\.?\s*ю\.?\s*н\.?|д\.?\s*э\.?\s*н\.?|к\.?\s*э\.?\s*н\.?|д\.?\s*и\.?\s*н\.?|к\.?\s*и\.?\s*н\.?|к\.?\s*ф\.?\s*н\.?|д\.?\s*ф\.?\s*н\.?|к\.?\s*п\.?\s*н\.?|д\.?\s*п\.?\s*н\.?|к\.?\s*т\.?\s*н\.?|д\.?\s*т\.?\s*н\.?)\b',
      caseSensitive: false,
    ), '');
    // Collapse multiple spaces
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Take only first 3 words (Фамилия Имя Отчество)
    final words = clean.split(' ').where((w) => w.length > 1).toList();
    if (words.length > 3) return words.sublist(0, 3).join(' ');
    return words.join(' ');
  }

  /// Cleans raw review text: strips HTML tags, decodes entities, normalizes whitespace
  String _cleanReviewText(String raw) {
    var text = raw;
    // Remove HTML tags
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // Decode HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&laquo;', '\u00ab')
        .replaceAll('&raquo;', '\u00bb')
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&hellip;', '\u2026');
    // Decode numeric entities
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    // Replace non-breaking space
    text = text.replaceAll('\u00a0', ' ');
    // Normalize whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Parse reviews JSON from SQLite cache
  List<String> _parseReviewsJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Main entry: get teacher rating + reviews from myprepod.ru
  /// Uses 3-level cache: L1 in-memory → L2 SQLite (30 days) → L3 HTTP
  Future<MyprepodData?> getTeacherRating(String name) async {
    final clean = _cleanName(name);
    if (clean.isEmpty) return null;

    // L1: In-memory cache (current session)
    if (_cache.containsKey(clean)) return _cache[clean];

    // L2: SQLite persistent cache (30-day TTL)
    try {
      final cached = await ref.read(localDbServiceProvider).getMyprepodCache(clean);
      if (cached != null) {
        final data = MyprepodData(
          rating: cached['rating'] as String,
          reviews: _parseReviewsJson(cached['reviews'] as String),
        );
        _cache[clean] = data;
        return data;
      }
    } catch (e) {
      logger.log('[MYPREPOD] L2 cache error for "$clean": $e');
    }

    // L3: HTTP fetch from myprepod.ru
    try {
      final data = await _fetchFromSearch(clean);
      _cache[clean] = data;
      // Persist to SQLite for next time
      if (data != null) {
        try {
          await ref.read(localDbServiceProvider).setMyprepodCache(
            clean,
            data.rating,
            jsonEncode(data.reviews),
          );
        } catch (_) {}
      }
      return data;
    } catch (e) {
      logger.log('[MYPREPOD] Error for "$clean": $e');
      _cache[clean] = null;
      return null;
    }
  }

  /// Step 1: Search for teacher on myprepod.ru
  Future<MyprepodData?> _fetchFromSearch(String cleanName) async {
    // First try MSAL-specific search (uid=msal)
    var data = await _searchAndParse(cleanName, uid: 'msal');
    if (data != null) return data;

    // Fallback: global search
    data = await _searchAndParse(cleanName, uid: '');
    return data;
  }

  Future<MyprepodData?> _searchAndParse(String query, {required String uid}) async {
    final searchUrl = 'https://myprepod.ru/?page=search&uid=$uid&search=${Uri.encodeComponent(query)}';
    
    final resp = await _dio.get(searchUrl);
    final html = resp.data.toString();

    // Find all result links: href="index.php?page=res&res=XXXX..."
    final linkRegex = RegExp(
      r'href="index\.php\?page=res&(?:amp;)?res=(\d+)[^"]*"',
      caseSensitive: false,
    );
    
    final links = linkRegex.allMatches(html).toList();
    if (links.isEmpty) return null;

    String? bestResId;
    String? bestRating;

    for (final linkMatch in links) {
      final resId = linkMatch.group(1)!;
      
      final startPos = linkMatch.start;
      final nextLinkIdx = links.indexOf(linkMatch) + 1;
      final endPos = nextLinkIdx < links.length 
          ? links[nextLinkIdx].start 
          : (startPos + 2000).clamp(0, html.length);
      final block = html.substring(startPos, endPos);

      final queryWords = query.split(' ');
      final surname = queryWords.first;
      
      final blockText = block.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
      
      if (!blockText.toLowerCase().contains(surname.toLowerCase())) continue;

      int matchScore = 0;
      for (final w in queryWords) {
        if (blockText.toLowerCase().contains(w.toLowerCase())) matchScore++;
      }

      final ratingMatch = RegExp(r'(\d[\.,]\d)\s*/\s*5').firstMatch(block) ??
                           RegExp(r'>(\d[\.,]\d)<').firstMatch(block);

      if (ratingMatch != null) {
        final rating = ratingMatch.group(1)!.replaceAll(',', '.');
        
        if (bestResId == null || matchScore >= queryWords.length) {
          bestResId = resId;
          bestRating = rating;
          if (matchScore >= queryWords.length) break; // Perfect match
        }
      } else {
        if (bestResId == null) {
          bestResId = resId;
          bestRating = '-';
        }
      }
    }

    if (bestResId == null) {
      bestResId = links.first.group(1)!;
      final globalRating = RegExp(r'(\d[\.,]\d)\s*/\s*5').firstMatch(html) ??
                            RegExp(r'>(\d[\.,]\d)<').firstMatch(html);
      bestRating = globalRating?.group(1)?.replaceAll(',', '.') ?? '-';
    }

    final rating = bestRating ?? '-';

    List<String> reviews = [];
    try {
      reviews = await _fetchComments(bestResId);
    } catch (_) {}

    return MyprepodData(rating: rating, reviews: reviews);
  }

  /// Step 2: Fetch comments from teacher's profile/comments page
  Future<List<String>> _fetchComments(String resId) async {
    final profileUrl = 'https://myprepod.ru/index.php?page=res&res=$resId';
    
    try {
      final resp = await _dio.get(profileUrl);
      final html = resp.data.toString();
      
      return _extractComments(html);
    } catch (e) {
      logger.log('[MYPREPOD] Error fetching comments for res=$resId: $e');
      return [];
    }
  }

  /// Extract comment text from the profile/comments HTML
  List<String> _extractComments(String html) {
    final reviews = <String>[];

    // Strategy 1: Find content near "Ответить" (reply) buttons
    final replyPositions = RegExp(r'class="reply-btn"', caseSensitive: false)
        .allMatches(html)
        .map((m) => m.start)
        .toList();
    
    for (final replyPos in replyPositions) {
      final searchStart = (replyPos - 1500).clamp(0, html.length);
      final block = html.substring(searchStart, replyPos);
      
      final stripped = block
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]*>'), '\n')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.length > 5)
          .toList();
      
      if (stripped.isNotEmpty) {
        final candidates = stripped.where((line) {
          if (line.length < 8) return false;
          if (RegExp(r'^\d{1,2}\s+(янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)').hasMatch(line)) return false;
          if (RegExp(r'^\d+$').hasMatch(line)) return false;
          if (['Ответить', 'Написать комментарий', 'Отправить', 'void(0)'].any((s) => line.contains(s))) return false;
          return true;
        }).toList();
        
        if (candidates.isNotEmpty) {
          reviews.add(candidates.last.trim());
        }
      }
    }

    // Strategy 2: Fallback — look for substantial text after comment-form
    if (reviews.isEmpty) {
      final formPos = html.indexOf('comment-form');
      if (formPos > 0) {
        final afterForm = html.substring(formPos);
        final textBlocks = RegExp(r'>([^<]{15,})<', dotAll: true).allMatches(afterForm);
        for (final m in textBlocks) {
          final text = m.group(1)!.trim();
          if (text.length > 10 && 
              !text.contains('Ответить') && 
              !text.contains('comment') &&
              !text.contains('javascript') &&
              !RegExp(r'^\d{1,2}\s+(янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)').hasMatch(text)) {
            reviews.add(text);
          }
        }
      }
    }

    // Deduplicate, clean HTML entities, and filter junk
    final unique = reviews.toSet().toList();
    final cleaned = unique
        .map(_cleanReviewText)
        .where((t) => t.length >= 10)
        .toList();
    return cleaned.take(10).toList();
  }

  /// Clear in-memory cache (useful for force refresh)
  void clearCache() => _cache.clear();
}
