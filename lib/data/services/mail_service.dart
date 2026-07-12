import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/mail_service.dart
// enough_mail 2.1.x — IMAP читаем + SMTP отправляем

import 'dart:io';
import 'package:enough_mail/enough_mail.dart';
import 'mime_decoder.dart';
import 'owa_contact_search.dart';
import '../../core/utils/log.dart' as logger;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MailAttachment {
  final String filename;
  final String contentType;
  final int size;
  final int partIndex;

  const MailAttachment({
    required this.filename,
    required this.contentType,
    required this.size,
    required this.partIndex,
  });

  String get sizeLabel {
    if (size < 1024) return '$size Б';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} КБ';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

class MailMessage {
  final int uid;
  final String subject;
  final String from;
  final String fromEmail;
  final DateTime? date;
  final bool isSeen;
  final String? textBody;
  final String? htmlBody;
  final bool hasAttachments;
  final List<MailAttachment> attachments;

  const MailMessage({
    required this.uid,
    required this.subject,
    required this.from,
    required this.fromEmail,
    this.date,
    required this.isSeen,
    this.textBody,
    this.htmlBody,
    this.hasAttachments = false,
    this.attachments = const [],
  });
}

class MailFolder {
  final String name;
  final String path;
  final int? messageCount;
  final int? unseenCount;

  const MailFolder({
    required this.name,
    required this.path,
    this.messageCount,
    this.unseenCount,
  });
}

class MailContact {
  final String name;
  final String email;
  final OwaContact? owaContact;
  
  const MailContact({
    required this.name,
    required this.email,
    this.owaContact,
  });
}

class MailService {
  final Ref ref;
  MailService(this.ref);

  ImapClient? _imap;
  SmtpClient? _smtp;
  String? _email;
  bool _connected = false;
  static const _secureStorage = FlutterSecureStorage();

  bool get isConnected => _connected;

  // ── Подключение ────────────────────────────────────────────────────────────

  Future<void> connect(String login, [String? explicitPassword]) async {
    _email    = login.contains('@') ? login : '$login@edu.msal.ru';
    
    final password = explicitPassword ?? await _secureStorage.read(key: 'saved_password');
    if (password == null) throw Exception('Password missing');

    try {
      // Очистка старой сессии если есть
      if (_imap != null) {
        try { await _imap!.logout(); } catch (_) {}
        _imap = null;
      }

      _imap = ImapClient(isLogEnabled: kDebugMode); 
      logger.log('[MailService] Connecting to mail.msal.ru:993...');
      
      await _imap!.connectToServer('mail.msal.ru', 993, isSecure: true);
      logger.log('[MailService] Connected. Logging in as $_email...');
      
      await _imap!.login(_email!, password);
      logger.log('[MailService] Login successful.');
      
      // Initialize OWA session for photos/search
      try {
        OwaContactSearch(username: _email!, password: password).ensureSession();
      } catch (e) {
        logger.log('[MailService] OWA Pre-init failed (non-critical): $e');
      }
      
      _connected = true;
    } catch (e) {
      logger.log('[MailService] Connection/Login error: $e');
      _connected = false;
      rethrow;
    }
  }

  Future<void> _ensureSmtp() async {
    if (_smtp != null) return;
    
    final password = await _secureStorage.read(key: 'saved_password');
    if (password == null) throw Exception('Password missing for SMTP');

    _smtp = SmtpClient('mail.msal.ru', isLogEnabled: false);
    // Try STARTTLS on 587, fallback to 465 SSL
    try {
      await _smtp!.connectToServer('mail.msal.ru', 587, isSecure: false);
      await _smtp!.ehlo();
      await _smtp!.startTls();
    } catch (_) {
      _smtp = SmtpClient('mail.msal.ru', isLogEnabled: false);
      await _smtp!.connectToServer('mail.msal.ru', 465, isSecure: true);
      await _smtp!.ehlo();
    }
    // Try PLAIN then LOGIN
    bool authOk = false;
    for (final mech in [AuthMechanism.plain, AuthMechanism.login]) {
      try {
        await _smtp!.authenticate(_email!, password, mech);
        authOk = true;
        break;
      } catch (_) {}
    }
    if (!authOk) throw StateError('SMTP auth failed for $_email');
  }

  void _ensureConnected() {
    if (_imap == null || !_imap!.isConnected || !_connected) {
      throw Exception('Почтовая сессия не активна. Попробуйте войти заново.');
    }
  }

  Future<void> disconnect() async {
    try { await _imap?.logout(); }  catch (_) {}
    try { await _smtp?.disconnect(); } catch (_) {}
    _connected = false;
    _imap = null;
    _smtp = null;
  }

  // ── IMAP — Папки ──────────────────────────────────────────────────────────

  Future<List<MailFolder>> listFolders() async {
    Future<List<MailFolder>> doList() async {
      _ensureConnected();
      final mailboxes = await _imap!.listMailboxes();
      return mailboxes.map((m) => MailFolder(
        name: _friendlyName(m.name),
        path: m.encodedPath,
        messageCount: m.messagesExists,
        unseenCount:  m.messagesUnseen,
      )).toList();
    }

    try {
      return await doList();
    } catch (e) {
      logger.log('[MailService] listFolders error, attempting reconnect: $e');
      if (_email != null) {
        await connect(_email!);
        return await doList();
      }
      rethrow;
    }
  }

  // ── IMAP — Список писем ───────────────────────────────────────────────────

  Future<List<MailMessage>> fetchMessages(String folderPath, {int limit = 50}) async {
    Future<List<MailMessage>> doFetch() async {
      _ensureConnected();
      final mailbox = await _imap!.selectMailboxByPath(folderPath);
      final total   = mailbox.messagesExists;
      if (total == 0) return [];

      final from     = total > limit ? total - limit + 1 : 1;
      final sequence = MessageSequence.fromRange(from, total);
      final result   = await _imap!.fetchMessages(sequence, '(UID FLAGS ENVELOPE)')
          .timeout(const Duration(seconds: 15));

      return result.messages.reversed
          .map(_toMailMessage)
          .whereType<MailMessage>()
          .toList();
    }

    try {
      return await doFetch();
    } catch (e) {
      logger.log('[MailService] fetchMessages error, attempting reconnect: $e');
      if (_email != null) {
        await connect(_email!);
        return await doFetch();
      }
      rethrow;
    }
  }

  // ── IMAP — Чтение письма ──────────────────────────────────────────────────

  Future<MailMessage?> fetchMessageBody(String folderPath, int uid) async {
    Future<MailMessage?> doFetch() async {
      _ensureConnected();
      await _imap!.selectMailboxByPath(folderPath);
      final sequence = MessageSequence.fromId(uid, isUid: true);
      // Fetch specifically what we need. BODY[] is heavy but necessary for content.
      final result = await _imap!.uidFetchMessages(sequence, '(UID FLAGS ENVELOPE BODY[])')
          .timeout(const Duration(seconds: 20));
      
      if (result.messages.isEmpty) return null;
      final msg = result.messages.first;

      // Extract attachment info safely
      final attachments = <MailAttachment>[];
      try {
        final parts = msg.findContentInfo();
        for (int i = 0; i < parts.length; i++) {
          final info = parts[i];
          if (info.fileName != null && info.fileName!.isNotEmpty) {
            attachments.add(MailAttachment(
              filename: MimeDecoder.safeDecode(info.fileName!),
              contentType: info.contentType?.toString() ?? 'application/octet-stream',
              size: info.size ?? 0,
              partIndex: i,
            ));
          }
        }
      } catch (e) {
        logger.log('[MailService] Attachment extraction error: $e');
      }

      final fromEmail = (msg.envelope?.from?.isNotEmpty == true) ? msg.envelope!.from!.first.email : '';
      
      // Decode subject: try decodeSubject() first, then envelope, then fallback
      String subject;
      try {
        subject = msg.decodeSubject() ?? '';
      } catch (_) {
        subject = msg.envelope?.subject ?? '';
      }
      subject = MimeDecoder.safeDecode(subject);
      if (subject.isEmpty) subject = '(без темы)';

      return MailMessage(
        uid:             msg.uid ?? uid,
        subject:         subject,
        from:            _formatAddress(msg.envelope?.from),
        fromEmail:       fromEmail,
        date:            msg.envelope?.date,
        isSeen:          msg.flags?.contains(r'\Seen') ?? false,
        textBody:        msg.decodeTextPlainPart(),
        htmlBody:        msg.decodeTextHtmlPart(),
        hasAttachments:  msg.hasAttachments(),
        attachments:     attachments,
      );
    }

    try {
      return await doFetch();
    } catch (e) {
      logger.log('[MailService] Fetch body error, attempting reconnect: $e');
      try {
        // Simple retry with reconnect
        if (_email != null) {
          await connect(_email!);
          return await doFetch();
        }
      } catch (retryErr) {
        logger.log('[MailService] Reconnect & Fetch failed: $retryErr');
      }
      rethrow;
    }
  }

  // ── IMAP — Скачивание вложения ──────────────────────────────────────────

  Future<List<int>?> downloadAttachment(String folderPath, int uid, int partIndex) async {
    _ensureConnected();
    await _imap!.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    final result = await _imap!.uidFetchMessages(sequence, '(UID BODY[])');
    if (result.messages.isEmpty) return null;
    final msg = result.messages.first;
    try {
      final parts = msg.findContentInfo();
      if (partIndex >= 0 && partIndex < parts.length) {
        final info = parts[partIndex];
        final data = msg.decodeContentBinary();
        return data;
      }
    } catch (_) {}
    return null;
  }

  // ── IMAP — Пометить прочитанным ───────────────────────────────────────────

  Future<void> markSeen(String folderPath, int uid) async {
    _ensureConnected();
    await _imap!.selectMailboxByPath(folderPath);
    final seq = MessageSequence.fromId(uid, isUid: true);
    try {
      await _imap!.uidStore(seq, [r'\Seen']);
    } catch (_) {}
  }

  // ── Отправка — OWA первый, SMTP фоллбэк ────────────────────────────────────

  Future<void> sendMessage({
    required List<String> to,
    required String subject,
    required String body,
    String? cc,
    List<File> attachments = const [],
  }) async {
    _ensureConnected();

    // Try OWA first (more reliable — bypasses SMTP restrictions)
    try {
      logger.log('[MailService] Trying to send via OWA...');
      await OwaContactSearch.sendViaOwa(
        to: to,
        subject: subject,
        body: body,
        cc: cc,
      );
      logger.log('[MailService] Message sent via OWA successfully.');
      return;
    } catch (e) {
      logger.log('[MailService] OWA send failed: $e, falling back to SMTP...');
    }

    // Fallback to SMTP
    Future<void> doSend() async {
      await _ensureSmtp();

      // enough_mail 2.x: use prepareMultipartAlternativeMessage
      final builder = MessageBuilder.prepareMultipartAlternativeMessage(
        plainText: body.isNotEmpty ? body : ' ',
      );
      builder.from    = [MailAddress(null, _email!)];
      builder.to      = to.map((e) => MailAddress(null, e)).toList();
      builder.subject = subject;

      if (cc != null && cc.isNotEmpty) {
        builder.cc = [MailAddress(null, cc)];
      }

      // Add attachments
      for (final file in attachments) {
        try {
          final bytes    = await file.readAsBytes();
          final filename = file.path.split('/').last.split('\\').last;
          final mt = _mediaTypeFor(filename);
          builder.addBinary(bytes, mt, filename: filename);
        } catch (_) {}
      }

      final mime = builder.buildMimeMessage();
      await _smtp!.sendMessage(mime);
    }

    try {
      await doSend();
    } catch (_) {
      try { await _smtp?.disconnect(); } catch (_) {}
      _smtp = null;
      await doSend();
    }
  }

  // ── Поиск адресатов ───────────────────────────────────────────────────────

  Future<List<MailContact>> searchContacts(String query) async {
    _ensureConnected();
    if (query.trim().length < 2) return [];

    final results = <MailContact>[];
    final seen    = <String>{};

    // Scan OWA Corporate Directory
    bool owaAvailable = false;
    try {
      if (_email != null) {
        owaAvailable = true;
        final owaSearch = OwaContactSearch(username: _email!, password: (await _secureStorage.read(key: 'saved_password'))!);

        final owaContacts = await owaSearch.findPeople(query)
            .timeout(const Duration(seconds: 10), onTimeout: () => []);

        for (final c in owaContacts) {
          if (!seen.contains(c.email.toLowerCase())) {
            seen.add(c.email.toLowerCase());
            results.add(MailContact(name: c.displayName, email: c.email, owaContact: c));
          }
        }
      }
    } catch (e) {
      logger.log('[MailService] OWA search error: $e');
    }

    // If OWA results found, return them
    if (owaAvailable && results.isNotEmpty) {
      results.sort((a, b) => a.name.compareTo(b.name));
      return results.take(20).toList();
    }

    // Fallback to IMAP only when EWS is not available
    try {
      for (final folder in ['Sent', 'SENT', 'Sent Items', 'Отправленные']) {
        try {
          final mailbox = await _imap!.selectMailboxByPath(folder);
          if (mailbox.messagesExists > 0) {
            final total = mailbox.messagesExists;
            final from  = total > 200 ? total - 200 + 1 : 1;
            final seq   = MessageSequence.fromRange(from, total);
            final res   = await _imap!.fetchMessages(seq, '(UID ENVELOPE)');
            for (final msg in res.messages) {
              for (final addr in [...?msg.envelope?.to, ...?msg.envelope?.cc]) {
                final email = addr.email.toLowerCase();
                final name  = addr.personalName ?? addr.email;
                if (!seen.contains(email) &&
                    (name.toLowerCase().contains(query.toLowerCase()) ||
                        email.contains(query.toLowerCase()))) {
                  seen.add(email);
                  results.add(MailContact(name: name, email: addr.email));
                }
              }
            }
          }
          break;
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final mailbox = await _imap!.selectMailboxByPath('INBOX');
      if (mailbox.messagesExists > 0) {
        final total = mailbox.messagesExists;
        final from  = total > 300 ? total - 300 + 1 : 1;
        final seq   = MessageSequence.fromRange(from, total);
        final res   = await _imap!.fetchMessages(seq, '(UID ENVELOPE)');
        for (final msg in res.messages) {
          for (final addr in [...?msg.envelope?.from]) {
            final email = addr.email.toLowerCase();
            final name  = addr.personalName ?? addr.email;
            if (!seen.contains(email) &&
                !email.contains('noreply') &&
                (name.toLowerCase().contains(query.toLowerCase()) ||
                    email.contains(query.toLowerCase()))) {
              seen.add(email);
              results.add(MailContact(name: name, email: addr.email));
            }
          }
        }
      }
    } catch (_) {}

    results.sort((a, b) => a.name.compareTo(b.name));
    return results.take(20).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Determine MediaType from file extension for attachments
  MediaType _mediaTypeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':  return MediaType.fromText('application/pdf');
      case 'png':  return MediaType.fromText('image/png');
      case 'jpg':
      case 'jpeg': return MediaType.fromText('image/jpeg');
      case 'gif':  return MediaType.fromText('image/gif');
      case 'doc':
      case 'docx': return MediaType.fromText('application/msword');
      case 'xls':
      case 'xlsx': return MediaType.fromText('application/vnd.ms-excel');
      case 'txt':  return MediaType.fromText('text/plain');
      case 'zip':  return MediaType.fromText('application/zip');
      default:     return MediaType.fromText('application/octet-stream');
    }
  }

  MailMessage? _toMailMessage(MimeMessage msg) {
    try {
      // Decode subject: try decodeSubject() first, then envelope, with MIME decoding
      String subject;
      try {
        subject = msg.decodeSubject() ?? '';
      } catch (_) {
        subject = msg.envelope?.subject ?? '';
      }
      subject = MimeDecoder.safeDecode(subject);
      if (subject.isEmpty) subject = '(без темы)';

      return MailMessage(
        uid:            msg.uid ?? 0,
        subject:        subject,
        from:           _formatAddress(msg.envelope?.from),
        fromEmail:      (msg.envelope?.from?.isNotEmpty == true) ? msg.envelope!.from!.first.email : '',
        date:           msg.envelope?.date,
        isSeen:         msg.flags?.contains(r'\Seen') ?? false,
        hasAttachments: msg.hasAttachments(),
      );
    } catch (_) {
      return null;
    }
  }

  String _formatAddress(List<MailAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) return 'Неизвестный';
    final addr = addresses.first;
    if (addr.personalName?.isNotEmpty == true) {
      return MimeDecoder.safeDecode(addr.personalName!);
    }
    return addr.email;
  }

  String _friendlyName(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'INBOX':        return 'Входящие';
      case 'SENT':
      case 'SENT ITEMS':   return 'Отправленные';
      case 'DRAFTS':       return 'Черновики';
      case 'TRASH':
      case 'DELETED':      return 'Корзина';
      case 'SPAM':
      case 'JUNK':         return 'Спам';
      default:             return raw ?? 'Папка';
    }
  }
}
