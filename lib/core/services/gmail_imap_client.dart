import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/qris_email_parser.dart';

class GmailRawMessage {
  const GmailRawMessage({
    required this.uid,
    required this.from,
    required this.subject,
    required this.body,
    this.date,
  });

  final String uid;
  final String from;
  final String subject;
  final String body;
  final DateTime? date;
}

class _ImapHeaderEntry {
  const _ImapHeaderEntry({
    required this.uid,
    required this.from,
    required this.subject,
    this.date,
  });

  final String uid;
  final String from;
  final String subject;
  final DateTime? date;
}

/// Klien Gmail IMAP ringan berbasis `dart:io` SecureSocket (TLS port 993).
/// Memakai mode read-only `EXAMINE INBOX` dan `BODY.PEEK` agar tidak pernah mengubah
/// status terbaca/belum terbaca pada email pengguna.
class GmailImapClient {
  GmailImapClient();

  static const _host = 'imap.gmail.com';
  static const _port = 993;

  SecureSocket? _socket;
  final List<int> _buffer = [];
  Completer<void>? _dataWaiter;
  StreamSubscription<List<int>>? _sub;
  bool _closed = false;
  int _tagCounter = 1;

  Future<void> _connect() async {
    _socket = await SecureSocket.connect(
      _host,
      _port,
      timeout: const Duration(seconds: 12),
    );
    _sub = _socket!.listen(
      (chunk) {
        _buffer.addAll(chunk);
        final w = _dataWaiter;
        if (w != null && !w.isCompleted) {
          _dataWaiter = null;
          w.complete();
        }
      },
      onDone: () {
        _closed = true;
        final w = _dataWaiter;
        if (w != null && !w.isCompleted) {
          _dataWaiter = null;
          w.complete();
        }
      },
      onError: (Object err) {
        _closed = true;
        final w = _dataWaiter;
        if (w != null && !w.isCompleted) {
          _dataWaiter = null;
          w.completeError(err);
        }
      },
    );
    // Baca greeting `* OK ...`
    final greeting = await _readLine();
    if (!greeting.startsWith('* OK')) {
      throw const FormatException(
        'Server Gmail IMAP tidak merespons dengan benar.',
      );
    }
  }

  Future<void> _waitForData() async {
    if (_closed) {
      throw const SocketException('Koneksi IMAP terputus.');
    }
    _dataWaiter = Completer<void>();
    await _dataWaiter!.future.timeout(const Duration(seconds: 15));
  }

  Future<String> _readLine() async {
    while (true) {
      final nlIndex = _buffer.indexOf(10); // '\n'
      if (nlIndex >= 0) {
        final lineBytes = _buffer.sublist(0, nlIndex + 1);
        _buffer.removeRange(0, nlIndex + 1);
        return utf8.decode(lineBytes, allowMalformed: true).trimRight();
      }
      if (_closed) {
        if (_buffer.isNotEmpty) {
          final rest = utf8.decode(_buffer, allowMalformed: true);
          _buffer.clear();
          return rest.trimRight();
        }
        throw const SocketException('Koneksi IMAP berakhir tak terduga.');
      }
      await _waitForData();
    }
  }

  Future<String> _readExactBytes(int count) async {
    while (_buffer.length < count) {
      if (_closed) break;
      await _waitForData();
    }
    final take = _buffer.length < count ? _buffer.length : count;
    final bytes = _buffer.sublist(0, take);
    _buffer.removeRange(0, take);
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _nextTag() => 'A${(_tagCounter++).toString().padLeft(4, '0')}';

  String _quote(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Kirim perintah IMAP dan kumpulkan seluruh respons (termasuk blok literal `{N}`).
  Future<List<String>> _sendCommand(String command) async {
    final tag = _nextTag();
    _socket!.write('$tag $command\r\n');
    await _socket!.flush();

    final lines = <String>[];
    final literalRegex = RegExp(r'\{(\d+)\}$');

    while (true) {
      final line = await _readLine();
      if (line.startsWith('$tag ')) {
        if (!line.startsWith('$tag OK')) {
          throw FormatException(line.substring(tag.length + 1).trim());
        }
        return lines;
      }

      final litMatch = literalRegex.firstMatch(line);
      if (litMatch != null) {
        final len = int.tryParse(litMatch.group(1) ?? '0') ?? 0;
        final payload = len > 0 ? await _readExactBytes(len) : '';
        lines.add('$line\n$payload');
      } else {
        lines.add(line);
      }
    }
  }

  Future<void> _login(String email, String appPassword) async {
    final cleanPass = appPassword.replaceAll(' ', '');
    try {
      await _sendCommand('LOGIN ${_quote(email.trim())} ${_quote(cleanPass)}');
    } on FormatException {
      throw const FormatException(
        'Login Gmail gagal. Pastikan email benar, 2FA aktif, IMAP aktif, dan App Password 16 huruf sesuai.',
      );
    }
  }

  Future<void> _disconnect() async {
    try {
      if (_socket != null && !_closed) {
        _socket!.write('${_nextTag()} LOGOUT\r\n');
        await _socket!.flush();
      }
    } catch (_) {}
    await _sub?.cancel();
    _socket?.destroy();
    _socket = null;
  }

  /// Tes kredensial Gmail IMAP + App Password.
  Future<void> testConnection({
    required String email,
    required String appPassword,
  }) async {
    try {
      await _connect();
      await _login(email, appPassword);
      await _sendCommand('EXAMINE INBOX');
    } finally {
      await _disconnect();
    }
  }

  /// Tarik email kandidat transaksi QRIS dari INBOX dalam [lookbackDays] hari terakhir.
  /// [alreadyImportedUids] dilewati sebelum mengunduh body agar cepat dan hemat kuota.
  /// Jika [ignoreOnOrBeforeDayKey] diatur (YYYYMMDD), email pada tanggal tersebut dan sebelumnya
  /// tidak akan diunduh atau diperiksa.
  Future<List<GmailRawMessage>> fetchRecentQrisEmails({
    required String email,
    required String appPassword,
    required int lookbackDays,
    required Set<String> alreadyImportedUids,
    int? ignoreOnOrBeforeDayKey,
    int maxScanHeaders = 80,
  }) async {
    try {
      await _connect();
      await _login(email, appPassword);
      await _sendCommand('EXAMINE INBOX');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var since = today.subtract(Duration(days: lookbackDays));
      if (ignoreOnOrBeforeDayKey != null) {
        final cutoffDate = AppDateUtils.fromDayKey(ignoreOnOrBeforeDayKey);
        if (cutoffDate.isAfter(since)) {
          since = cutoffDate;
        }
      }
      const imapMonths = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final sinceStr =
          '${since.day}-${imapMonths[since.month - 1]}-${since.year}';

      final searchLines = await _sendCommand('UID SEARCH SINCE $sinceStr');
      final allUids = <String>[];
      for (final line in searchLines) {
        if (line.startsWith('* SEARCH')) {
          final parts = line
              .substring('* SEARCH'.length)
              .trim()
              .split(RegExp(r'\s+'));
          for (final p in parts) {
            if (p.isNotEmpty && RegExp(r'^\d+$').hasMatch(p)) {
              allUids.add(p);
            }
          }
        }
      }
      if (allUids.isEmpty) return const [];

      // Ambil N UID terbaru saja
      final recentUids = allUids.length > maxScanHeaders
          ? allUids.sublist(allUids.length - maxScanHeaders)
          : allUids;
      final unseenUids = recentUids
          .where((u) => !alreadyImportedUids.contains('gmail_uid:$u'))
          .toList();
      if (unseenUids.isEmpty) return const [];

      // Fetch header sekaligus (1 batch request)
      final uidSet = unseenUids.join(',');
      final headerLines = await _sendCommand(
        'UID FETCH $uidSet (UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])',
      );
      final headers = _parseHeaderFetch(headerLines);

      final candidates = headers.where((h) {
        if (ignoreOnOrBeforeDayKey != null && h.date != null) {
          final headerDay = AppDateUtils.toDayKey(h.date!.toLocal());
          if (headerDay <= ignoreOnOrBeforeDayKey) return false;
        }
        return QrisEmailParser.isLikelyQrisHeader(h.from, h.subject);
      }).toList();
      if (candidates.isEmpty) return const [];

      final results = <GmailRawMessage>[];
      for (final item in candidates) {
        final bodyLines = await _sendCommand(
          'UID FETCH ${item.uid} (BODY.PEEK[TEXT]<0.32768>)',
        );
        final body = _extractLiteralBody(bodyLines);
        results.add(
          GmailRawMessage(
            uid: 'gmail_uid:${item.uid}',
            from: item.from,
            subject: item.subject,
            body: body,
            date: item.date,
          ),
        );
      }
      return results;
    } finally {
      await _disconnect();
    }
  }

  List<_ImapHeaderEntry> _parseHeaderFetch(List<String> lines) {
    final entries = <_ImapHeaderEntry>[];
    final uidRegex = RegExp(r'UID\s+(\d+)', caseSensitive: false);

    for (final block in lines) {
      if (!block.contains('FETCH')) continue;
      final uidMatch = uidRegex.firstMatch(block);
      if (uidMatch == null) continue;
      final uid = uidMatch.group(1)!;

      final firstNl = block.indexOf('\n');
      if (firstNl < 0) continue;
      final rawHeaders = block.substring(firstNl + 1);
      // Unfold multi-line RFC 5322 headers
      final unfolded = rawHeaders.replaceAll(RegExp(r'\r?\n[ \t]+'), ' ');

      String from = '';
      String subject = '';
      String dateRaw = '';
      for (final hLine in unfolded.split(RegExp(r'\r?\n'))) {
        final colon = hLine.indexOf(':');
        if (colon <= 0) continue;
        final key = hLine.substring(0, colon).trim().toLowerCase();
        final val = hLine.substring(colon + 1).trim();
        if (key == 'from') from = QrisEmailParser.decodeRfc2047(val);
        if (key == 'subject') subject = QrisEmailParser.decodeRfc2047(val);
        if (key == 'date') dateRaw = val;
      }

      entries.add(
        _ImapHeaderEntry(
          uid: uid,
          from: from,
          subject: subject,
          date: dateRaw.isNotEmpty
              ? QrisEmailParser.parseEmailDate(dateRaw)
              : null,
        ),
      );
    }
    return entries;
  }

  String _extractLiteralBody(List<String> lines) {
    final buf = StringBuffer();
    for (final block in lines) {
      final firstNl = block.indexOf('\n');
      if (firstNl >= 0) {
        buf.writeln(block.substring(firstNl + 1));
      }
    }
    return buf.toString();
  }
}
