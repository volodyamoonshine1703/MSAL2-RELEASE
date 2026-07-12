import '../../../core/providers.dart';
// lib/presentation/screens/mail/mail_detail_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/mail_service.dart';
import '../../../data/services/owa_contact_search.dart';
import '../../widgets/contact_avatar.dart';
import 'compose_screen.dart';

final _messageBodyProvider = FutureProvider.family<MailMessage?, ({String folder, int uid})>(
    (ref, args) async {
  return ref.read(mailServiceProvider).fetchMessageBody(args.folder, args.uid);
});

final _threadProvider = FutureProvider.family<List<ConversationMessage>, String>((ref, subject) async {
  final cleanSubject = subject.replaceAll(RegExp(r'^(Re|Fwd|Отв|Пересл):\s*', caseSensitive: false), '').trim();
  return OwaContactSearch.getThread(cleanSubject);
});

/// Checks if the text contains meaningful HTML tags (not just plain text)
bool _isHtml(String text) {
  return RegExp(
    r'<(p|div|br|table|td|tr|span|a|img|h[1-6]|ul|ol|li|b|i|strong|em|blockquote|section|article|header|footer|style)\b',
    caseSensitive: false,
  ).hasMatch(text);
}

/// Pre-compiled regexes for HTML sanitization (avoid re-creating on every call)
final _reScript     = RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false);
final _reCondStart  = RegExp(r'<!--\[if[^\]]*\]>.*?<!\[endif\]-->', dotAll: true, caseSensitive: false);
final _reComment    = RegExp(r'<!--.*?-->', dotAll: true);
final _reVml        = RegExp(r'<v:[^>]*>.*?</v:[^>]*>', dotAll: true, caseSensitive: false);
final _reOml        = RegExp(r'<o:[^>]*>.*?</o:[^>]*>', dotAll: true, caseSensitive: false);
final _reWml        = RegExp(r'<w:[^>]*>.*?</w:[^>]*>', dotAll: true, caseSensitive: false);
final _reXml        = RegExp(r'<\?xml[^>]*\?>', caseSensitive: false);
final _reXmlns      = RegExp(r'\s+xmlns(:[a-z]+)?="[^"]*"', caseSensitive: false);
final _reStyleBlock = RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false);
final _reBgColor    = RegExp(r'\s+bgcolor="[^"]*"', caseSensitive: false);
final _reColorAttr  = RegExp(r'\s+color="[^"]*"', caseSensitive: false);
final _reBody       = RegExp(r'<body', caseSensitive: false);

/// Matches inline style="..." and rewrites it to strip color-related properties.
final _reStyleAttr  = RegExp(r'style="([^"]*)"', caseSensitive: false);

/// Prepares raw HTML for safe dark-theme rendering.
String _prepareHtml(String html) {
  var h = html;

  // ── 1. Remove dangerous/broken content ──
  h = h.replaceAll(_reScript, '');
  h = h.replaceAll(_reCondStart, '');
  h = h.replaceAll(_reComment, '');
  h = h.replaceAll(_reVml, '');
  h = h.replaceAll(_reOml, '');
  h = h.replaceAll(_reWml, '');
  h = h.replaceAll(_reXml, '');
  h = h.replaceAll(_reXmlns, '');

  // ── 2. Strip <style> blocks (Outlook CSS overrides our theme) ──
  h = h.replaceAll(_reStyleBlock, '');

  // ── 3. Strip color-related properties from inline style="" attributes ──
  // This is precise: only touches style="..." values, not other HTML text.
  h = h.replaceAllMapped(_reStyleAttr, (m) {
    var css = m.group(1) ?? '';
    // Remove color properties (word-boundary to not eat "background-color" partially)
    css = css.replaceAll(RegExp(r'(?:^|;\s*)color\s*:[^;]*;?', caseSensitive: false), ';');
    css = css.replaceAll(RegExp(r'background(?:-color)?\s*:[^;]*;?', caseSensitive: false), '');
    css = css.replaceAll(RegExp(r';\s*;'), ';'); // clean double semicolons
    css = css.trim();
    if (css.isEmpty || css == ';') return '';
    return 'style="$css"';
  });

  // ── 4. Strip old-school HTML color attributes ──
  h = h.replaceAll(_reBgColor, '');
  h = h.replaceAll(_reColorAttr, '');

  // ── 5. Inject dark-theme CSS at the beginning ──
  const darkCss = '''
<style>
  * { color: #E0DEE6 !important; }
  body { background: transparent !important; }
  a { color: #9C6FFF !important; text-decoration: underline !important; }
  blockquote { border-left: 3px solid #5E5178 !important; padding-left: 12px !important; margin-left: 0 !important; color: #9B8DB8 !important; }
  hr { border-color: #2E2840 !important; }
  table, td, th { border-color: #2E2840 !important; }
  img { max-width: 100% !important; height: auto !important; }
  h1,h2,h3,h4,h5,h6 { color: #F0EBF8 !important; }
</style>''';

  final bodyIdx = h.indexOf(_reBody);
  if (bodyIdx >= 0) {
    h = h.substring(0, bodyIdx) + darkCss + h.substring(bodyIdx);
  } else {
    h = darkCss + h;
  }

  return h;
}

class MailDetailScreen extends ConsumerWidget {
  final MailMessage message;
  final String folder;
  const MailDetailScreen({super.key, required this.message, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyAsync = ref.watch(_messageBodyProvider((folder: folder, uid: message.uid)));

    ref.listen(_messageBodyProvider((folder: folder, uid: message.uid)), (_, next) {
      if (next.hasValue) {
        ref.read(mailServiceProvider).markSeen(folder, message.uid).catchError((_) {});
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: message.subject.isNotEmpty
            ? Text(message.subject,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16))
            : const SizedBox.shrink(),
      ),
      body: bodyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            const Text('Не удалось загрузить письмо',
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('$e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                textAlign: TextAlign.center),
          ]),
        ),
        data: (body) {
          final msg = body ?? message;
          final threadAsync = ref.watch(_threadProvider(msg.subject));
          
          return threadAsync.when(
            loading: () => _MessageBody(preview: message, body: body, folder: folder, thread: []),
            error: (_, __) => _MessageBody(preview: message, body: body, folder: folder, thread: []),
            data: (thread) => _MessageBody(preview: message, body: body, folder: folder, thread: thread),
          );
        },
      ),
    );
  }
}

class _MessageBody extends ConsumerStatefulWidget {
  final MailMessage preview;
  final MailMessage? body;
  final String folder;
  final List<ConversationMessage> thread;
  
  const _MessageBody({
    required this.preview, 
    required this.body, 
    required this.folder,
    required this.thread,
  });

  @override
  ConsumerState<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends ConsumerState<_MessageBody> {
  late List<bool> _expanded;

  @override
  void initState() {
    super.initState();
    _initExpanded();
  }

  @override
  void didUpdateWidget(_MessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.length != widget.thread.length) {
      _initExpanded();
    }
  }

  void _initExpanded() {
    final threadCount = widget.thread.isNotEmpty ? widget.thread.length : 1;
    _expanded = List.generate(threadCount, (i) => i == threadCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.body ?? widget.preview;
    // Prefer HTML body for rich rendering; fallback to text body
    final items = widget.thread.isNotEmpty ? widget.thread : [
      ConversationMessage(
        messageId: msg.uid.toString(),
        subject: msg.subject,
        fromName: msg.from,
        fromEmail: msg.fromEmail,
        body: msg.htmlBody ?? msg.textBody ?? '',
        date: msg.date ?? DateTime.now(),
      )
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 60),
      itemCount: items.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg.subject,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 6),
                Text('${items.length} ${Intl.plural(items.length, one: 'сообщение', few: 'сообщения', many: 'сообщений', other: 'сообщений')}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                if (msg.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ...msg.attachments.map((att) => _AttachmentTile(
                    attachment: att, folder: widget.folder, uid: msg.uid)),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 0.5, color: AppTheme.divider),
              ],
            ),
          );
        }
        
        final idx = i - 1;
        return _ThreadItem(
          item: items[idx], 
          isExpanded: _expanded[idx],
          onToggle: () => setState(() => _expanded[idx] = !_expanded[idx]),
          replyTo: idx > 0 ? items[idx - 1].fromName : null,
        );
      },
    );
  }
}

class _ThreadItem extends ConsumerStatefulWidget {
  final ConversationMessage item;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String? replyTo;

  const _ThreadItem({
    required this.item, 
    required this.isExpanded,
    required this.onToggle,
    this.replyTo,
  });

  @override
  ConsumerState<_ThreadItem> createState() => _ThreadItemState();
}

class _ThreadItemState extends ConsumerState<_ThreadItem> {
  @override
  Widget build(BuildContext context) {
    final rawBody = widget.item.body;
    final isHtmlContent = _isHtml(rawBody);
    final plainPreview = _cleanForPreview(rawBody);
    final timeStr = _formatRelativeDate(widget.item.date);

    return InkWell(
      onTap: widget.isExpanded ? null : widget.onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Outlook-style header: Avatar + Name + Time + Actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ContactAvatar(name: widget.item.fromName, email: widget.item.fromEmail, size: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name row
                      Text(widget.item.fromName,
                          style: const TextStyle(
                            color: AppTheme.textPrimary, 
                            fontSize: 14, 
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      // Email + date row
                      Row(
                        children: [
                          Expanded(
                            child: Text(widget.item.fromEmail,
                                style: const TextStyle(
                                  color: AppTheme.textMuted, fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(timeStr, style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.reply_rounded, size: 18, color: AppTheme.textMuted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _reply(context),
                    ),
                    IconButton(
                      icon: Icon(
                        widget.isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, 
                        size: 18, color: AppTheme.textMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onToggle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // ── Body content ──
          if (widget.isExpanded) ...[
            Padding(
              padding: const EdgeInsets.only(left: 68, right: 16, top: 8, bottom: 16),
              child: isHtmlContent
                  ? HtmlWidget(
                      _prepareHtml(rawBody),
                      textStyle: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                      customStylesBuilder: (element) {
                        final tag = element.localName ?? '';
                        // Force ALL elements to use light text color
                        final styles = <String, String>{
                          'color': '#E0DEE6',
                        };
                        // Links get accent color
                        if (tag == 'a') {
                          styles['color'] = '#9C6FFF';
                          styles['text-decoration'] = 'underline';
                        }
                        // Blockquotes get muted color + border
                        if (tag == 'blockquote') {
                          styles['color'] = '#9B8DB8';
                          styles['border-left'] = '3px solid #5E5178';
                          styles['padding-left'] = '12px';
                          styles['margin-left'] = '0';
                        }
                        // Muted text for small/sub/sup
                        if (tag == 'small' || tag == 'sub' || tag == 'sup') {
                          styles['color'] = '#9B8DB8';
                        }
                        // Headings slightly brighter
                        if (tag.startsWith('h') && tag.length == 2) {
                          styles['color'] = '#F0EBF8';
                          styles['font-weight'] = 'bold';
                        }
                        // Strip any background colors
                        styles['background-color'] = 'transparent';
                        styles['background'] = 'transparent';
                        return styles;
                      },
                      onTapUrl: (url) {
                        return true;
                      },
                    )
                  : SelectableText(
                      plainPreview,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        height: 1.55,
                        letterSpacing: 0.1,
                      ),
                    ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(left: 68, right: 16, bottom: 12),
              child: Text(plainPreview.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
          
          const Divider(height: 1, thickness: 0.5, color: AppTheme.divider),
        ],
      ),
    );
  }

  void _reply(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ComposeScreen(
      initialTo: widget.item.fromEmail,
      initialSubject: widget.item.subject.startsWith('Re:') ? widget.item.subject : 'Re: ${widget.item.subject}',
      replyBody: widget.item.body,
    )));
  }

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Вчера, ${DateFormat('HH:mm').format(date)}';
    }
    if (date.year == now.year) {
      return DateFormat('d MMM, HH:mm', 'ru_RU').format(date);
    }
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  /// Converts HTML to clean plain text for collapsed preview and plain-text fallback.
  String _cleanForPreview(String html) {
    if (html.isEmpty) return '';
    var text = html;

    // 1. Remove <style> and <script> blocks completely
    text = text.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '');

    // 2. Remove VML/conditional comments
    text = text.replaceAll(RegExp(r'<!--\[if[^\]]*\]>.*?<!\[endif\]-->', dotAll: true, caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    // 3. Handle Outlook quote markers — remove forwarded/replied sections
    final quotePatterns = [
      RegExp(r'<div[^>]*id="divRplyFwdMsg"[^>]*>.*', dotAll: true, caseSensitive: false),
      RegExp(r'<div[^>]*class="OutlookMessageHeader"[^>]*>.*', dotAll: true, caseSensitive: false),
      RegExp(r'<div[^>]*class="gmail_quote"[^>]*>.*', dotAll: true, caseSensitive: false),
      // Outlook separator line
      RegExp(r'_{5,}.*', dotAll: true),
    ];
    for (final p in quotePatterns) {
      text = text.replaceAll(p, '');
    }

    // 4. Preserve structure: block-level tags → newlines
    text = text.replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(r'</(p|div|tr|li|h[1-6]|section|article|blockquote)>', caseSensitive: false),
      '\n\n',
    );
    text = text.replaceAll(
      RegExp(r'<(p|div|tr|td|li|h[1-6]|section|article|blockquote)[^>]*>', caseSensitive: false),
      '',
    );

    // 5. Handle list items: <li> → "• "
    text = text.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');

    // 6. Remove all remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 7. Decode HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&ensp;', ' ')
        .replaceAll('&emsp;', ' ')
        .replaceAll('&thinsp;', '')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    
    // Decode numeric entities
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });

    // 8. Replace non-breaking spaces
    text = text.replaceAll('\u00a0', ' ');

    // 9. Clean up whitespace
    text = text.split('\n').map((line) {
      return line.replaceAll(RegExp(r' {2,}'), ' ').trim();
    }).join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return text;
  }
}

class _AttachmentTile extends ConsumerStatefulWidget {
  final MailAttachment attachment;
  final String folder;
  final int uid;
  const _AttachmentTile({required this.attachment, required this.folder, required this.uid});

  @override
  ConsumerState<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<_AttachmentTile> {
  bool _downloading = false;

  IconData _icon() {
    final ct = widget.attachment.contentType.toLowerCase();
    if (ct.contains('image')) return Icons.image_outlined;
    if (ct.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (ct.contains('word') || ct.contains('doc')) return Icons.description_outlined;
    if (ct.contains('excel') || ct.contains('sheet')) return Icons.table_chart_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(mailServiceProvider).downloadAttachment(
          widget.folder, widget.uid, widget.attachment.partIndex);
      if (bytes != null && mounted) {
        final dir = await Directory.systemTemp.createTemp('mail_att');
        final file = File('${dir.path}/${widget.attachment.filename}');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Сохранено: ${widget.attachment.filename}')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось скачать вложение')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        Icon(_icon(), color: AppTheme.accent, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.attachment.filename, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
            overflow: TextOverflow.ellipsis),
          if (widget.attachment.size > 0) Text(widget.attachment.sizeLabel,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ])),
        _downloading
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
          : GestureDetector(onTap: _download,
              child: const Icon(Icons.download_outlined, color: AppTheme.accent, size: 20)),
      ]),
    );
  }
}
