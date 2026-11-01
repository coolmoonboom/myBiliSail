import 'dart:convert';

import '../api_client.dart';
import '../models.dart';
import '../models/message_models.dart';

/// Web Cookie inbox. IDs, sequences and microsecond cursors stay decimal strings.
final class MessageClient {
  const MessageClient(this.api);
  final BiliApiClient api;
  static const _vc = 'api.vc.bilibili.com';

  Future<Map<String, Object?>> _get(
    String host,
    String path,
    String endpoint,
    Map<String, String> query,
    ApiRequestContext? context,
  ) =>
      api.requestJson(Uri.https(host, path, query), endpoint, context: context);

  Future<Map<ApiInboxSection, int>> unread({ApiRequestContext? context}) async {
    const e = 'message_unread';
    final data = await _get(
      'api.bilibili.com',
      '/x/msgfeed/unread',
      e,
      {},
      context,
    );
    return Map.unmodifiable({
      ApiInboxSection.private: _count(data['chat']),
      ApiInboxSection.replies: _count(data['reply']),
      ApiInboxSection.mentions: _count(data['at']),
      ApiInboxSection.likes: _count(data['like']),
      ApiInboxSection.system: _count(data['sys_msg']),
    });
  }

  Future<ApiPage<ApiInboxEntry>> sessions({
    String? cursor,
    ApiRequestContext? context,
  }) async {
    const e = 'message_sessions';
    if (cursor != null) _decimal(cursor, e);
    final data =
        await _get(_vc, '/session_svr/v1/session_svr/get_sessions', e, {
          'session_type': '1',
          'group_fold': '1',
          'unfollow_fold': '0',
          'sort_rule': '2',
          'build': '0',
          'mobi_app': 'web',
          'end_ts': ?cursor,
        }, context);
    if (!data.containsKey('session_list')) _fail(e);
    final rows = <_SessionRow>[];
    for (final value in _list(data['session_list'], e, nullable: true)) {
      if (value is! Map<String, Object?>) continue;
      final mid = _optionalDecimal(value['talker_id']);
      final type = _optionalNumber(value['session_type']);
      // A row without a talker or session type has no usable identity.
      if (mid == null || type == null) continue;
      rows.add((data: value, mid: mid, type: type));
    }
    final mids = {
      for (final row in rows)
        if (row.type == 1 && _count(row.data['system_msg_type']) == 0) row.mid,
    };
    final users = <String, Map<String, Object?>>{};
    if (mids.isNotEmpty) {
      final cards = await _get(
        'api.bilibili.com',
        '/x/polymer/pc-electron/v1/user/cards',
        'message_users',
        {'uids': mids.join(',')},
        context,
      );
      final listed = cards['list'];
      for (final value in listed is List<Object?> ? listed : cards.values) {
        if (value is! Map<String, Object?>) continue;
        final mid = _optionalDecimal(value['mid']);
        if (mid != null) users[mid] = value;
      }
    }
    final entries = rows
        .map((row) {
          final data = row.data;
          final system = _count(data['system_msg_type']) != 0;
          final account = _optionalMap(data['account_info']);
          final user = users[row.mid] ?? account;
          final last = data['last_msg'];
          final message = last is Map<String, Object?> ? _message(last) : null;
          return ApiInboxEntry(
            id: '${row.type}:${row.mid}',
            userMid: row.mid,
            sessionType: row.type,
            system: system,
            title: _text(user['name']).isNotEmpty
                ? _text(user['name'])
                : _text(account['uname']).isNotEmpty
                ? _text(account['uname'])
                : _text(data['group_name']).isNotEmpty
                ? _text(data['group_name'])
                : '用户 ${row.mid}',
            text: message?.text ?? '暂无消息',
            avatarUrl: _uri(
              user['face'] ??
                  account['pic_url'] ??
                  account['pic'] ??
                  data['group_cover'],
            ),
            time: message?.time,
            unread: _count(data['unread_count']),
            lastSequence:
                _optionalDecimal(data['max_seqno'], zero: true) ??
                message?.sequence,
          );
        })
        .toList(growable: false);
    // A missing trailing cursor only stops pagination for the next page.
    final next = rows.isEmpty
        ? null
        : _optionalDecimal(rows.last.data['session_ts'], zero: true);
    return _page(entries, _yes(data['has_more']), next, cursor);
  }

  Future<ApiPage<ApiPrivateMessage>> thread(
    String mid,
    int type, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    const e = 'message_thread';
    _decimal(mid, e);
    if (type != 1 && type != 2) throw ArgumentError('Invalid session type');
    if (cursor != null) _decimal(cursor, e, zero: true);
    final data =
        await _get(_vc, '/svr_sync/v1/svr_sync/fetch_session_msgs', e, {
          'talker_id': mid,
          'session_type': '$type',
          'size': '30',
          'sender_device_id': '1',
          'build': '0',
          'mobi_app': 'web',
          'end_seqno': ?cursor,
        }, context);
    if (!data.containsKey('messages')) _fail(e);
    final messages = <ApiPrivateMessage>[];
    for (final value in _list(data['messages'], e, nullable: true)) {
      if (value is! Map<String, Object?>) continue;
      final message = _message(value);
      // Messages without a sequence cannot be deduplicated or paged.
      if (message.sequence != '0') messages.add(message);
    }
    messages.sort(
      (a, b) => BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
    );
    final next = messages.isEmpty ? null : messages.first.sequence;
    return _page(messages, _yes(data['has_more']), next, cursor);
  }

  Future<ApiPage<ApiInboxEntry>> notifications(
    ApiInboxSection section, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    if (section == ApiInboxSection.private) throw ArgumentError('Use sessions');
    final name = switch (section) {
      ApiInboxSection.replies => 'reply',
      ApiInboxSection.mentions => 'at',
      ApiInboxSection.likes => 'like',
      _ => 'system',
    };
    final e = 'message_$name';
    final query = <String, String>{
      'platform': 'web',
      'build': '0',
      'mobi_app': 'web',
    };
    if (section == ApiInboxSection.system) {
      query['page_size'] = '20';
      if (cursor != null) {
        throw ArgumentError('System notice pagination is unavailable');
      }
    } else if (cursor != null) {
      final parts = cursor.split(':');
      if (parts.length != 2) throw ArgumentError('Invalid notification cursor');
      query['id'] = _decimal(parts[0], e, zero: true);
      query['${name}_time'] = _decimal(parts[1], e, zero: true);
    }
    final data = await _get(
      section == ApiInboxSection.system
          ? 'message.bilibili.com'
          : 'api.bilibili.com',
      section == ApiInboxSection.system
          ? '/x/sys-msg/query_user_notify'
          : '/x/msgfeed/$name',
      e,
      query,
      context,
    );
    if (section == ApiInboxSection.system) {
      // The live Web endpoint returns an empty data object at the end.
      if (data.isEmpty) return const ApiPage([], hasMore: false);
      if (!data.containsKey('system_notify_list') &&
          !data.containsKey('list')) {
        _fail(e);
      }
      final entries =
          _list(data['system_notify_list'] ?? data['list'], e, nullable: true)
              .map((value) {
                if (value is! Map<String, Object?>) return null;
                final row = value;
                final id = _optionalDecimal(row['id']);
                if (id == null) return null;
                return ApiInboxEntry(
                  id: id,
                  title: _text(row['title']).isEmpty
                      ? '系统通知'
                      : _text(row['title']),
                  text: _text(row['content']),
                  time: _time(row['time_at']),
                  targetUrl: _uri(row['link']),
                  system: true,
                  readCursor: _optionalDecimal(row['cursor']),
                );
              })
              .whereType<ApiInboxEntry>()
              .toList();
      // This endpoint exposes no usable cursor in the verified Web response.
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    final total = section == ApiInboxSection.likes
        ? _optionalMap(data['total'])
        : data;
    final latest = section == ApiInboxSection.likes
        ? _optionalMap(data['latest'] ?? data['lastest'])
        : const <String, Object?>{};
    final raw = [
      if (cursor == null && latest.containsKey('items'))
        ..._list(latest['items'], e, nullable: true),
      ..._list(total['items'], e, nullable: true),
    ];
    final entries = <String, ApiInboxEntry>{};
    for (final value in raw) {
      if (value is! Map<String, Object?>) continue;
      final row = value, item = _optionalMap(row['item']);
      final users = row['users'];
      final listedUser = row['user'] is Map<String, Object?>
          ? row['user']
          : users is List<Object?> && users.first is Map<String, Object?>
          ? users.first
          : null;
      final user = listedUser is Map<String, Object?>
          ? listedUser
          : const <String, Object?>{};
      final mid = user['mid'] == null ? null : _optionalDecimal(user['mid']);
      final id = _optionalDecimal(row['id']);
      if (id == null) continue;
      final actor = _text(user['nickname'] ?? user['name']);
      final verb = switch (section) {
        ApiInboxSection.replies => '回复了你',
        ApiInboxSection.mentions => '@了你',
        _ => '赞了你',
      };
      entries[id] = ApiInboxEntry(
        id: id,
        title:
            '${actor.isEmpty ? '用户' : actor}${_count(row['counts']) > 1 ? '等${_count(row['counts'])}人' : ''}$verb',
        text: [
          _text(item['source_content']),
          _text(item['title'] ?? item['desc']),
        ].where((v) => v.isNotEmpty).toSet().join('\n'),
        userMid: mid,
        avatarUrl: _uri(user['avatar'] ?? user['face']),
        time: _time(row['${name}_time']),
        targetUrl: _uri(item['uri']),
      );
    }
    final c = _optionalMap(total['cursor']);
    final cursorId = _optionalDecimal(c['id'], zero: true);
    final cursorTime = _optionalDecimal(c['time'], zero: true);
    final next = cursorId == null || cursorTime == null
        ? null
        : '$cursorId:$cursorTime';
    return _page(entries.values.toList(), !_yes(c['is_end']), next, cursor);
  }

  Future<void> sendText(
    String sender,
    String receiver,
    String text, {
    ApiRequestContext? context,
  }) async {
    const e = 'message_send';
    _decimal(sender, e);
    _decimal(receiver, e);
    if (text.trim().isEmpty || text.runes.length > 1000) {
      throw ArgumentError('Invalid message');
    }
    await api.submitMessageForm('/web_im/v1/web_im/send_msg', e, {
      'msg[sender_uid]': sender,
      'msg[receiver_id]': receiver,
      'msg[receiver_type]': '1',
      'msg[msg_type]': '1',
      'msg[msg_status]': '0',
      'msg[content]': jsonEncode({'content': text}),
      'msg[timestamp]': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'msg[dev_id]': '0',
      'msg[new_face_version]': '1',
      'from_firework': '0',
      'build': '0',
      'mobi_app': 'web',
    }, context: context);
  }

  Future<void> markRead(
    String mid,
    int type,
    String sequence, {
    ApiRequestContext? context,
  }) async {
    const e = 'message_mark_read';
    _decimal(mid, e);
    _decimal(sequence, e, zero: true);
    if (type != 1 && type != 2) throw ArgumentError('Invalid session type');
    await api.submitMessageForm('/session_svr/v1/session_svr/update_ack', e, {
      'talker_id': mid,
      'session_type': '$type',
      'ack_seqno': sequence,
      'build': '0',
      'mobi_app': 'web',
    }, context: context);
  }

  Future<void> markSystemNotificationsRead(
    String cursor, {
    ApiRequestContext? context,
  }) {
    const endpoint = 'message_system_mark_read';
    _decimal(cursor, endpoint);
    return api.acknowledgeSystemNotifications(cursor, context: context);
  }

  /// One unreadable row degrades to a placeholder: an unknown type or odd
  /// payload never removes the rest of the page from the inbox.
  ApiPrivateMessage _message(Map<String, Object?> row) {
    final type = _optionalNumber(row['msg_type']) ?? 0;
    final sequence = _optionalDecimal(row['msg_seqno'], zero: true) ?? '0';
    final sender = _optionalDecimal(row['sender_uid'], zero: true) ?? '0';
    final status = _count(row['msg_status']);
    final revoked = status == 1 || status == 2 || type == 5;
    // The server may still include recalled text: never decode or display it.
    final content = !revoked && row['content'] is String
        ? _decodedContent(row['content'] as String)
        : const <String, Object?>{};
    final image = !revoked && type == 2 ? _uri(content['url']) : null;
    final text = revoked
        ? '消息已撤回'
        : type == 2
        ? '[图片]'
        : _text(content['content']).isNotEmpty
        ? _text(content['content'])
        : [
            _text(content['title']),
            _text(content['text']),
          ].where((s) => s.isNotEmpty).join('\n');
    return ApiPrivateMessage(
      // Some notification messages reuse msg_key=0; sequence is unique per thread.
      id: sequence,
      sequence: sequence,
      senderMid: sender,
      type: type,
      time: _time(row['timestamp']),
      text: text.isEmpty ? '暂不支持的消息类型（$type）' : text,
      imageUrl: image,
      targetUrl: revoked ? null : _uri(content['url'] ?? content['jump_uri']),
    );
  }

  /// Template cards arrive as a JSON object or an array of card objects.
  Map<String, Object?> _decodedContent(String value) {
    if (value.length > 65536) return const {};
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const {};
    }
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is List<Object?>) {
      return decoded.whereType<Map<String, Object?>>().firstOrNull ?? const {};
    }
    return const {};
  }

  ApiPage<T> _page<T>(
    List<T> items,
    bool more,
    String? next,
    String? previous,
  ) => ApiPage(
    List.unmodifiable(items),
    hasMore: more && items.isNotEmpty && next != null && next != previous,
    nextCursor: next,
  );
  Never _fail(String e) => throw ApiFailure(ApiFailureCategory.protocol, e);
  String? _optionalDecimal(Object? v, {bool zero = false}) {
    final text = v is int || v is String ? '$v' : '';
    final pattern = zero ? r'^[0-9]+$' : r'^[1-9][0-9]*$';
    return RegExp(pattern).hasMatch(text) ? text : null;
  }

  int? _optionalNumber(Object? v) => v is int
      ? v
      : v is String
      ? int.tryParse(v)
      : null;

  Map<String, Object?> _optionalMap(Object? v) =>
      v is Map<String, Object?> ? v : const {};
  List<Object?> _list(Object? v, String e, {bool nullable = false}) =>
      v == null && nullable
      ? const []
      : v is List<Object?> && v.length <= 500
      ? v
      : _fail(e);
  String _decimal(Object? v, String e, {bool zero = false}) {
    if (v is! int && v is! String) _fail(e);
    final s = '$v';
    if (!RegExp(zero ? r'^[0-9]+$' : r'^[1-9][0-9]*$').hasMatch(s)) _fail(e);
    return s;
  }

  int _count(Object? v) => v is int && v >= 0 ? v : 0;
  bool _yes(Object? v) => v == 1 || v == true;
  String _text(Object? v) => v is String ? v : '';
  DateTime? _time(Object? v) {
    final n = v is int ? v : int.tryParse('$v');
    return n != null && n > 0 && n < 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
        : v is String
        ? DateTime.tryParse(v)
        : null;
  }

  Uri? _uri(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final uri = Uri.tryParse(v.startsWith('//') ? 'https:$v' : v);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !{'http', 'https'}.contains(uri.scheme)) {
      return null;
    }
    return uri.replace(scheme: 'https');
  }
}

typedef _SessionRow = ({Map<String, Object?> data, String mid, int type});
