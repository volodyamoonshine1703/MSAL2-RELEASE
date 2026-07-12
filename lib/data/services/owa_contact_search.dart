import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/log.dart' as logger;

class ConversationMessage {
  final String messageId;
  final String subject;
  final String fromName;
  final String fromEmail;
  final String body;
  final DateTime date;

  ConversationMessage({
    required this.messageId,
    required this.subject,
    required this.fromName,
    required this.fromEmail,
    required this.body,
    required this.date,
  });
}

class OwaContact {
  final String personaId;
  final String displayName;
  final String email;
  
  // Extended details
  final String? title;
  final String? department;
  final String? officeLocation;
  final String? phone;
  final String? adObjectId;

  const OwaContact({
    required this.personaId,
    required this.displayName,
    required this.email,
    this.title,
    this.department,
    this.officeLocation,
    this.phone,
    this.adObjectId,
  });

  OwaContact copyWith({
    String? title,
    String? department,
    String? officeLocation,
    String? phone,
    String? adObjectId,
  }) {
    return OwaContact(
      personaId: personaId,
      displayName: displayName,
      email: email,
      title: title ?? this.title,
      department: department ?? this.department,
      officeLocation: officeLocation ?? this.officeLocation,
      phone: phone ?? this.phone,
      adObjectId: adObjectId ?? this.adObjectId,
    );
  }

  @override
  String toString() => '$displayName <$email>';
}

class OwaSession {
  final String username;
  final String password;
  
  Map<String, String> _cookies = {};
  String? _canary;
  final Map<String, Uint8List?> _photoCache = {};

  OwaSession({required this.username, required this.password});

  bool get isAuthenticated => _cookies.containsKey('X-OWA-CANARY') && _cookies.containsKey('X-BackEndCookie');

  Future<File> _getCacheFile(String email, String size) async {
    final dir = await getApplicationCacheDirectory();
    final hash = md5.convert(utf8.encode('${email.toLowerCase()}_$size')).toString();
    return File('${dir.path}/avatar_$hash.jpg');
  }

  Future<Uint8List?> fetchPhoto(String email, {bool allowRetry = true, String size = 'HR96x96'}) async {
    final normalizedEmail = email.toLowerCase();
    final cacheKey = '${normalizedEmail}_$size';
    
    // 1. Check Memory Cache
    if (_photoCache.containsKey(cacheKey)) return _photoCache[cacheKey];

    // 2. Check Disk Cache
    try {
      final file = await _getCacheFile(normalizedEmail, size);
      if (await file.exists()) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        if (age.inDays < 7) {
          final bytes = await file.readAsBytes();
          _photoCache[cacheKey] = bytes;
          logger.log('[OWA-PHOTO] Loaded from Disk: $normalizedEmail ($size)');
          return bytes;
        } else {
          logger.log('[OWA-PHOTO] Disk cache expired for $normalizedEmail');
        }
      }
    } catch (e) {
      logger.log('[OWA-PHOTO] Disk cache read error: $e');
    }

    // 3. Network Fetch
    final httpClient = _createClient();

    try {
      final encodedEmail = Uri.encodeComponent(normalizedEmail);
      final uri = Uri.parse('https://mail.msal.ru/owa/service.svc/s/GetPersonaPhoto?email=$encodedEmail&UA=0&size=$size');
      logger.log('[OWA-PHOTO] Requesting Network: $uri');
      
      final request = await httpClient.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      
      if (_cookies.isNotEmpty) {
        request.headers.set('Cookie', _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }

      final response = await request.close();
      final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
      logger.log('[OWA-PHOTO] Network Response for $normalizedEmail ($size): ${response.statusCode}, Content-Type: $contentType');

      if (response.statusCode == 200) {
        if (contentType.contains('gif')) {
          _photoCache[cacheKey] = null;
          await response.drain();
          return null;
        }
        
        final bytes = await _readAllBytes(response);
        if (bytes.length < 100) {
          _photoCache[cacheKey] = null;
          return null;
        }

        // Save to Memory and Disk
        _photoCache[cacheKey] = bytes;
        try {
          final file = await _getCacheFile(normalizedEmail, size);
          await file.writeAsBytes(bytes);
        } catch (e) {
          logger.log('[OWA-PHOTO] Disk cache write error: $e');
        }

        return bytes;
      } else if ((response.statusCode == 301 || response.statusCode == 302) && allowRetry) {
        await response.drain();
        await login();
        return fetchPhoto(normalizedEmail, allowRetry: false, size: size);
      } else {
        _photoCache[cacheKey] = null;
        await response.drain();
        return null;
      }
    } catch (e) {
      logger.log('[OWA-PHOTO] Network Error for $normalizedEmail ($size): $e');
      return null;
    } finally {
      httpClient.close();
    }
  }

  Future<Uint8List> _readAllBytes(Stream<List<int>> stream) async {
    final builder = BytesBuilder();
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  HttpClient _createClient() {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => host == 'mail.msal.ru';
    return client;
  }

  Future<void> login() async {
    logger.log('[OWA-AUTH] Starting multi-step FBA login for $username...');
    
    final httpClient = _createClient();
    Map<String, String> currentCookies = {};
    String currentUrl = 'https://mail.msal.ru/owa/auth/owaauth.dll';
    String currentMethod = 'POST';
    final bodyString = 'destination=https%3A%2F%2Fmail.msal.ru%2Fowa%2F'
        '&flags=4&forcedownlevel=0'
        '&username=${Uri.encodeComponent(username)}'
        '&password=${Uri.encodeComponent(password)}'
        '&isUtf8=1';

    try {
      for (int step = 1; step <= 10; step++) {
        final uri = Uri.parse(currentUrl);
        final request = await httpClient.openUrl(currentMethod, uri);
        request.followRedirects = false; 

        if (currentCookies.isNotEmpty) {
          request.headers.set('Cookie', currentCookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
        }
        
        request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        
        if (currentMethod == 'POST' && step == 1) {
          final bodyBytes = utf8.encode(bodyString);
          request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
          request.contentLength = bodyBytes.length;
          request.add(bodyBytes);
        }

        final response = await request.close();
        
        final setCookies = response.headers['set-cookie'] ?? [];
        for (var raw in setCookies) {
          final cookiePart = raw.split(';').first.trim();
          final eqIdx = cookiePart.indexOf('=');
          if (eqIdx > 0) {
            final name = cookiePart.substring(0, eqIdx);
            final value = cookiePart.substring(eqIdx + 1);
            currentCookies[name] = value;
          }
        }

        logger.log('[OWA-AUTH] Step $step: $currentMethod $currentUrl → status=${response.statusCode}, cookies: ${currentCookies.length}');

        if (currentCookies.containsKey('X-OWA-CANARY') && currentCookies.containsKey('X-BackEndCookie')) {
          _cookies = currentCookies;
          _canary = currentCookies['X-OWA-CANARY'];
          logger.log('[OWA-AUTH] Success! Canary and BackEndCookie found at step $step.');
          await response.drain();
          
          // Proactive Preloading
          unawaited(_preloadRecentAvatars());
          
          return;
        }

        if (response.statusCode >= 300 && response.statusCode < 400) {
          String? location = response.headers.value('location');
          if (location == null) {
            await response.drain();
            throw Exception('Step $step: Redirect status ${response.statusCode} but no Location header');
          }
          
          if (location.startsWith('/')) {
            currentUrl = '${uri.scheme}://${uri.host}$location';
          } else {
            currentUrl = location;
          }
          currentMethod = 'GET';
          await response.drain();
        } else {
          final bodyStr = await utf8.decodeStream(response);
          if (response.statusCode == 200 && bodyStr.contains('owaauth.dll')) {
            logger.log('[OWA-AUTH] Still on login page (status 200). Check credentials.');
          }
          break;
        }
      }
      
      throw Exception('OWA Login failed: canary not found after 10 steps. Cookies: ${currentCookies.keys.join(", ")}');
    } finally {
      httpClient.close();
    }
  }

  Future<void> _preloadRecentAvatars() async {
    try {
      logger.log('[OWA-PRELOAD] Preloading recent avatars...');
      final conversations = await _findConversations('');
      final emails = <String>{};
      for (final conv in conversations) {
        final participants = conv['UniqueSenders'];
        if (participants is List) {
          for (final p in participants) {
            if (p is String) emails.add(p);
          }
        }
      }
      logger.log('[OWA-PRELOAD] Found ${emails.length} recent participants');
      await Future.wait(
        emails.map((e) => fetchPhoto(e, size: 'HR96x96')),
        eagerError: false,
      );
      logger.log('[OWA-PRELOAD] Completed');
    } catch (e) {
      logger.log('[OWA-PRELOAD] Error: $e');
    }
  }

  Future<List<ConversationMessage>> getThreadBySubject(String subject) async {
    // 1. Find the ConversationId by subject
    final conversations = await _findConversations(subject);
    if (conversations.isEmpty) return [];
    
    final convId = conversations.first['ConversationId']?['Id'];
    if (convId == null) return [];

    // 2. Get items for this conversation
    return await _getConversationItems(convId);
  }

  Future<List<Map<String, dynamic>>> _findConversations(String query) async {
    final uri = Uri.parse('https://mail.msal.ru/owa/service.svc?action=FindConversation&EP=1');
    final httpClient = _createClient();
    try {
      final request = await httpClient.postUrl(uri);
      authHeaders.forEach((k, v) => request.headers.set(k, v));
      
      final payload = {
        '__type': 'FindConversationJsonRequest:#Exchange',
        'Header': {
          '__type': 'JsonRequestHeaders:#Exchange',
          'RequestServerVersion': 'Exchange2013',
        },
        'Body': {
          '__type': 'FindConversationRequest:#Exchange',
          'IndexedPageItemView': {
            '__type': 'IndexedPageViewType:#Exchange',
            'BasePoint': 'Beginning',
            'Offset': 0,
            'MaxEntriesReturned': 5
          },
          'ParentFolderId': {
            '__type': 'TargetFolderIdType:#Exchange',
            'DistinguishedFolderId': {'__type': 'DistinguishedFolderIdType:#Exchange', 'Id': 'inbox'}
          },
          'QueryString': query,
        }
      };

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.write(jsonEncode(payload));

      final response = await request.close();
      if (response.statusCode != 200) return [];

      final resBody = await utf8.decodeStream(response);
      final data = jsonDecode(resBody);
      final list = data['Body']?['Conversations'];
      return list is List ? list.cast<Map<String, dynamic>>() : [];
    } catch (e) {
      logger.log('[OWA] _findConversations error: $e');
      return [];
    } finally {
      httpClient.close();
    }
  }

  Future<List<ConversationMessage>> _getConversationItems(String convId) async {
    final uri = Uri.parse('https://mail.msal.ru/owa/service.svc?action=GetConversationItems&EP=1');
    final httpClient = _createClient();
    try {
      final request = await httpClient.postUrl(uri);
      authHeaders.forEach((k, v) => request.headers.set(k, v));
      
      final payload = {
        '__type': 'GetConversationItemsJsonRequest:#Exchange',
        'Header': {
          '__type': 'JsonRequestHeaders:#Exchange',
          'RequestServerVersion': 'Exchange2013',
        },
        'Body': {
          '__type': 'GetConversationItemsRequest:#Exchange',
          'Conversations': [
            {
              '__type': 'ConversationRequestType:#Exchange',
              'ConversationId': {'__type': 'ItemIdType:#Exchange', 'Id': convId}
            }
          ],
          'ItemShape': {
            '__type': 'ItemResponseShapeType:#Exchange',
            'BaseShape': 'IdOnly',
            'AdditionalProperties': [
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'ItemSubject'},
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'ItemDateTimeReceived'},
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'ItemFrom'},
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'ItemUniqueBody'},
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'ItemBody'},
            ]
          }
        }
      };

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.write(jsonEncode(payload));

      final response = await request.close();
      if (response.statusCode != 200) return [];

      final resBody = await utf8.decodeStream(response);
      final data = jsonDecode(resBody);
      final convNodes = data['Body']?['Conversations'];
      if (convNodes == null || convNodes.isEmpty) return [];

      final items = convNodes[0]['Items'];
      if (items is! List) return [];

      final results = <ConversationMessage>[];
      for (final item in items) {
        final from = item['From'];
        final fromName = from?['Mailbox']?['Name'] ?? 'Unknown';
        final fromEmail = from?['Mailbox']?['EmailAddress'] ?? '';
        final subject = item['Subject'] ?? '';
        final dateStr = item['DateTimeReceived'];
        final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
        
        // Prefer UniqueBody (only the new part of the message)
        final bodyNode = item['UniqueBody'] ?? item['Body'];
        final body = bodyNode?['Value'] ?? '';

        results.add(ConversationMessage(
          messageId: item['ItemId']?['Id'] ?? '',
          subject: subject,
          fromName: fromName,
          fromEmail: fromEmail,
          body: body,
          date: date,
        ));
      }
      
      // Sort by date ascending to show history correctly
      results.sort((a, b) => a.date.compareTo(b.date));
      return results;
    } catch (e) {
      logger.log('[OWA] _getConversationItems error: $e');
      return [];
    } finally {
      httpClient.close();
    }
  }

  Map<String, String> get authHeaders => {
    'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    'X-OWA-CANARY': _cookies['X-OWA-CANARY'] ?? _canary ?? '',
    'Content-Type': 'application/json; charset=utf-8',
    'X-Requested-With': 'XMLHttpRequest',
    'Action': 'FindPeople',
    'X-OWA-ClientBuildVersion': '15.1.2507.6',
    'X-OWA-ActionName': 'ComposeForms',
    'X-OWA-Attempt': '1',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  /// Sends an email via OWA's CreateItem action (when SMTP is blocked).
  Future<void> sendMessage({
    required List<String> toEmails,
    required String subject,
    required String bodyText,
    String? ccEmail,
  }) async {
    if (!isAuthenticated) {
      await login();
    }

    final uri = Uri.parse('https://mail.msal.ru/owa/service.svc?action=CreateItem&ID=-45&AC=1');
    final httpClient = _createClient();

    try {
      final request = await httpClient.postUrl(uri);
      final headers = authHeaders;
      headers['Action'] = 'CreateItem';
      headers['X-OWA-ActionName'] = 'CreateItemAction';
      headers.forEach((k, v) => request.headers.set(k, v));

      // Build HTML body
      final htmlBody = '<html><head>'
          '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
          '</head><body dir="ltr">'
          '<div id="divtagdefaultwrapper" dir="ltr" style="font-size:12pt;color:#000000;font-family:Calibri,Helvetica,sans-serif;">'
          '${bodyText.replaceAll('\n', '<br>')}'
          '</div></body></html>';

      // Build recipients
      final toRecipients = toEmails.map((email) => {
        'Name': email,
        'EmailAddress': email,
        'RoutingType': 'SMTP',
        'MailboxType': 'Mailbox',
      }).toList();

      final ccRecipients = <Map<String, String>>[];
      if (ccEmail != null && ccEmail.isNotEmpty) {
        ccRecipients.add({
          'Name': ccEmail,
          'EmailAddress': ccEmail,
          'RoutingType': 'SMTP',
          'MailboxType': 'Mailbox',
        });
      }

      final payload = {
        '__type': 'CreateItemJsonRequest:#Exchange',
        'Header': {
          '__type': 'JsonRequestHeaders:#Exchange',
          'RequestServerVersion': 'V2015_10_15',
          'TimeZoneContext': {
            '__type': 'TimeZoneContext:#Exchange',
            'TimeZoneDefinition': {
              '__type': 'TimeZoneDefinitionType:#Exchange',
              'Id': 'Russian Standard Time',
            },
          },
        },
        'Body': {
          '__type': 'CreateItemRequest:#Exchange',
          'MessageDisposition': 'SendAndSaveCopy',
          'Items': [
            {
              '__type': 'Message:#Exchange',
              'Subject': subject,
              'Body': {
                '__type': 'BodyContentType:#Exchange',
                'BodyType': 'HTML',
                'Value': htmlBody,
              },
              'ToRecipients': toRecipients,
              'CcRecipients': ccRecipients,
              'BccRecipients': <Map<String, String>>[],
              'IsDeliveryReceiptRequested': false,
              'IsReadReceiptRequested': false,
              'Importance': 'Normal',
            },
          ],
        },
      };

      final bytes = utf8.encode(jsonEncode(payload));
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close();
      final resBody = await utf8.decodeStream(response);

      if (response.statusCode != 200) {
        throw Exception('OWA CreateItem failed: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(resBody);
      final items = data['Body']?['ResponseMessages']?['Items'];
      if (items is List && items.isNotEmpty) {
        final responseCode = items[0]['ResponseCode'];
        if (responseCode != 'NoError') {
          throw Exception('OWA send error: $responseCode');
        }
      }

      logger.log('[OWA-SEND] Message sent successfully via OWA CreateItem');
    } finally {
      httpClient.close();
    }
  }
}

class OwaContactSearch {
  static OwaSession? _session;
  static int _globalGeneration = 0;
  Timer? _debounceTimer;

  final String username;
  final String password;

  OwaContactSearch({required this.username, required this.password});

  static HttpClient _createClient() {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => host == 'mail.msal.ru';
    return client;
  }

  void ensureSession() {
    _session ??= OwaSession(username: username, password: password);
    if (!_session!.isAuthenticated) {
      unawaited(_session!.login().catchError((e) => logger.log('[OWA] Pre-init login error: $e')));
    }
  }

  static Future<List<ConversationMessage>> getThread(String subject) async {
    if (_session == null) return [];
    return _session!.getThreadBySubject(subject);
  }

  static Future<Uint8List?> getPhoto(String email, {String size = 'HR96x96'}) async {
    if (_session == null) {
      logger.log('[OWA-PHOTO] getPhoto called but _session is null for $email');
      return null;
    }
    return _session!.fetchPhoto(email, size: size);
  }

  /// Send an email via OWA (fallback when SMTP is blocked).
  static Future<void> sendViaOwa({
    required List<String> to,
    required String subject,
    required String body,
    String? cc,
  }) async {
    if (_session == null) {
      throw StateError('OWA session not initialized. Connect to mail first.');
    }
    await _session!.sendMessage(
      toEmails: to,
      subject: subject,
      bodyText: body,
      ccEmail: cc,
    );
  }

  static Future<OwaContact?> getPersonaDetails(OwaContact contact) async {
    if (_session == null) return null;
    
    final uri = Uri.parse('https://mail.msal.ru/owa/service.svc?action=GetPersona&EP=1&ID=-99&AC=1');
    final httpClient = _createClient();

    try {
      final request = await httpClient.postUrl(uri);
      
      final headers = _session!.authHeaders;
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('X-OWA-ActionName', 'PersonaCard_2');
      
      final payload = {
        '__type': 'GetPersonaJsonRequest:#Exchange',
        'Header': {
          '__type': 'JsonRequestHeaders:#Exchange',
          'RequestServerVersion': 'Exchange2013',
          'TimeZoneContext': {
            '__type': 'TimeZoneContext:#Exchange',
            'TimeZoneDefinition': {
              '__type': 'TimeZoneDefinitionType:#Exchange',
              'Id': 'Russian Standard Time'
            }
          }
        },
        'Body': {
          '__type': 'GetPersonaRequest:#Exchange',
          'PersonaId': {'__type': 'ItemId:#Exchange', 'Id': contact.personaId}
        }
      };

      // OWA GetPersona often requires payload in X-OWA-UrlPostData header instead of body
      final jsonPayload = jsonEncode(payload);
      request.headers.set('X-OWA-UrlPostData', Uri.encodeComponent(jsonPayload));
      request.contentLength = 0; // Empty body

      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }

      final resBody = await utf8.decodeStream(response);
      final data = jsonDecode(resBody);
      
      final persona = data['Body']?['Persona'];
      if (persona == null) return null;

      String? office;
      final offices = persona['OfficeLocationsArray'];
      if (offices is List && offices.isNotEmpty) {
        office = offices[0]['Value'];
      }

      String? phone;
      final phones = persona['BusinessPhoneNumbersArray'];
      if (phones is List && phones.isNotEmpty) {
        phone = phones[0]['Value']?['Number'];
      }

      // After getting persona details, we might want to preload the larger photo
      _session?.fetchPhoto(contact.email, size: 'HR96x96');

      return contact.copyWith(
        title: persona['Title'],
        department: persona['Department'],
        officeLocation: office,
        phone: phone,
        adObjectId: persona['ADObjectId'],
      );
    } catch (e) {
      logger.log('[OWA] GetPersona error: $e');
      return null;
    } finally {
      httpClient.close();
    }
  }

  Future<List<OwaContact>> findPeople(String query) async {
    // 2. Minimum 2 characters
    if (query.trim().length < 2) return [];

    _debounceTimer?.cancel();
    final completer = Completer<List<OwaContact>>();
    
    // 3. Generation tracking
    _globalGeneration++;
    final myGeneration = _globalGeneration;

    // 1. Debounce 400ms using Timer
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        _session ??= OwaSession(username: username, password: password);
        
        if (!_session!.isAuthenticated) {
          await _session!.login();
        }

        // Check generation before request
        if (myGeneration != _globalGeneration) {
          if (!completer.isCompleted) completer.complete([]);
          return;
        }

        final results = await _doRequest(query);

        // Check generation after request
        if (myGeneration != _globalGeneration) {
          if (!completer.isCompleted) completer.complete([]);
          return;
        }

        // Preload photos in background
        for (final c in results) {
          _session?.fetchPhoto(c.email, size: 'HR96x96');
        }

        completer.complete(results);
      } catch (e) {
        if (e.toString().contains('401') || e.toString().contains('449') || e.toString().contains('OwaSerializationException')) {
          logger.log('[OWA] Auth or Serialization error (${e.toString()}), re-logging in...');
          try {
            await _session!.login();
            if (myGeneration == _globalGeneration) {
              final retryResults = await _doRequest(query);
              if (myGeneration == _globalGeneration) {
                // Preload photos for retried results
                for (final c in retryResults) {
                  _session?.fetchPhoto(c.email, size: 'HR96x96');
                }
                if (!completer.isCompleted) completer.complete(retryResults);
                return;
              }
            }
          } catch (loginErr) {
             if (!completer.isCompleted) completer.completeError(loginErr);
             return;
          }
        }
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    return completer.future;
  }

  Future<List<OwaContact>> _doRequest(String query) async {
    final uri = Uri.parse('https://mail.msal.ru/owa/service.svc?action=FindPeople');
    final httpClient = _createClient();

    try {
      final request = await httpClient.postUrl(uri);
      _session!.authHeaders.forEach((k, v) => request.headers.set(k, v));
      
      final payload = {
        '__type': 'FindPeopleJsonRequest:#Exchange',
        'Header': {
          '__type': 'JsonRequestHeaders:#Exchange',
          'RequestServerVersion': 'Exchange2013',
          'TimeZoneContext': {
            '__type': 'TimeZoneContext:#Exchange',
            'TimeZoneDefinition': {
              '__type': 'TimeZoneDefinitionType:#Exchange',
              'Id': 'Russian Standard Time'
            }
          }
        },
        'Body': {
          '__type': 'FindPeopleRequest:#Exchange',
          'IndexedPageItemView': {
            '__type': 'IndexedPageView:#Exchange',
            'BasePoint': 'Beginning',
            'Offset': 0,
            'MaxEntriesReturned': 20
          },
          'QueryString': query,
          'AggregationRestriction': {
            '__type': 'RestrictionType:#Exchange',
            'Item': {
              '__type': 'Or:#Exchange',
              'Items': [
                {
                  '__type': 'Exists:#Exchange',
                  'Item': {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'PersonaEmailAddress'}
                },
                {
                  '__type': 'IsEqualTo:#Exchange',
                  'Item': {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'PersonaType'},
                  'FieldURIOrConstant': {
                    '__type': 'FieldURIOrConstantType:#Exchange',
                    'Item': {'__type': 'Constant:#Exchange', 'Value': 'DistributionList'}
                  }
                }
              ]
            }
          },
          'PersonaShape': {
            '__type': 'PersonaResponseShape:#Exchange',
            'BaseShape': 'Default',
            'AdditionalProperties': [
              {'__type': 'PropertyUri:#Exchange', 'FieldURI': 'PersonaAttributions'}
            ]
          },
          'ShouldResolveOneOffEmailAddress': true,
          'SearchPeopleSuggestionIndex': false,
          'Context': [
            {'__type': 'ContextProperty:#Exchange', 'Key': 'AppName', 'Value': 'OWA'},
            {'__type': 'ContextProperty:#Exchange', 'Key': 'AppScenario', 'Value': 'NewMail.To'}
          ]
        }
      };

      final bytes = utf8.encode(jsonEncode(payload));
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);
      final response = await request.close();

      if (response.statusCode == 401 || response.statusCode == 449) {
        await response.drain();
        throw Exception('Status ${response.statusCode} - session likely expired');
      }

      if (response.statusCode != 200) {
        final errBody = await utf8.decodeStream(response);
        throw Exception('OWA Error ${response.statusCode}: $errBody');
      }

      final resBody = await utf8.decodeStream(response);
      final data = jsonDecode(resBody);
      return _parseFindPeopleResponse(data);
    } finally {
      httpClient.close();
    }
  }

  List<OwaContact> _parseFindPeopleResponse(Map<String, dynamic> data) {
    final List<OwaContact> results = [];
    
    try {
      final body = data['Body'];
      if (body == null) return [];
      
      final resultSet = body['ResultSet'];
      if (resultSet == null || resultSet is! List) return [];

      for (final item in resultSet) {
        final displayName = item['DisplayName'] ?? '';
        final emailAddress = item['EmailAddress'];
        final personaIdMap = item['PersonaId'];
        
        String? email;
        if (emailAddress is Map) {
          email = emailAddress['EmailAddress'];
        }

        String? personaId;
        if (personaIdMap is Map) {
          personaId = personaIdMap['Id'];
        }

        if (displayName.isNotEmpty && email != null && email.isNotEmpty && personaId != null) {
          results.add(OwaContact(personaId: personaId, displayName: displayName, email: email));
        }
      }
    } catch (e) {
      logger.log('[OWA] Parse error: $e');
    }
    
    return results;
  }
}
