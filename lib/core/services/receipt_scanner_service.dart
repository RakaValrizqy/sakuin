import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sakuin/core/utils/receipt_parser.dart';

class ReceiptScannerService {
  ReceiptScannerService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel('id.rakavalrizqy.sakuin/receipt');
  static const _kGeminiApiKey = 'sakuin_gemini_api_key';

  final FlutterSecureStorage _storage;
  final _sharedImageController = StreamController<String>.broadcast();

  Stream<String> get sharedImageStream => _sharedImageController.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onSharedImage') {
      final path = call.arguments as String?;
      if (path != null && path.isNotEmpty) {
        _sharedImageController.add(path);
      }
    }
  }

  Future<String?> getGeminiApiKey() async {
    try {
      final key = await _storage.read(key: _kGeminiApiKey);
      if (key == null || key.trim().isEmpty) return null;
      return key.trim();
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasGeminiApiKey() async {
    final key = await getGeminiApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<void> saveGeminiApiKey(String? apiKey) async {
    final cleaned = apiKey?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _storage.delete(key: _kGeminiApiKey);
    } else {
      await _storage.write(key: _kGeminiApiKey, value: cleaned);
    }
  }

  Future<String?> captureReceiptPhoto() async {
    try {
      return await _channel.invokeMethod<String>('captureReceiptPhoto');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal membuka kamera');
    }
  }

  Future<String?> pickReceiptImage() async {
    try {
      return await _channel.invokeMethod<String>('pickReceiptImage');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal memilih gambar dari galeri');
    }
  }

  Future<String?> consumePendingSharedImage() async {
    try {
      return await _channel.invokeMethod<String>('getPendingSharedImage');
    } catch (_) {
      return null;
    }
  }

  Future<void> cleanupReceiptCache() async {
    try {
      await _channel.invokeMethod('cleanupReceiptCache');
    } catch (_) {}
  }

  /// Scan struk secara Hybrid (Opsi 3):
  /// - Jika Gemini API Key terpasang & [forceOffline] == false -> coba AI Vision Gemini terlebih dahulu
  ///   (lebih akurat untuk struk panjang, diskon/PPN, & pecah item), dan otomatis fallback ke
  ///   Google ML Kit Offline OCR jika sedang tidak ada internet / kuota habis.
  /// - Jika API key kosong atau [forceOffline] == true -> langsung jalankan ML Kit Offline OCR 100% lokal.
  Future<ParsedReceipt> scanReceipt(
    String filePath, {
    bool forceOffline = false,
  }) async {
    final apiKey = forceOffline ? null : await getGeminiApiKey();
    String? fallbackNotice;

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final aiReceipt = await _scanWithGeminiVision(filePath, apiKey);
        if (aiReceipt != null) {
          return aiReceipt;
        }
        fallbackNotice = 'AI Vision tidak dapat membaca struk — dialihkan otomatis ke OCR Offline.';
      } on SocketException {
        fallbackNotice =
            'Sedang offline — menggunakan OCR Lokal (ML Kit) di perangkat.';
      } on TimeoutException {
        fallbackNotice =
            'Koneksi ke Gemini lambat — dialihkan ke OCR Lokal (ML Kit).';
      } catch (e) {
        fallbackNotice =
            'Gemini tidak tersedia ($e) — dialihkan ke OCR Lokal (ML Kit).';
      }
    }

    final rawText = await _recognizeTextOffline(filePath);
    return ReceiptParser.parseOcrText(
      rawText,
      engineUsed: 'mlkit_offline',
      fallbackNotice: fallbackNotice,
    );
  }

  Future<String> _recognizeTextOffline(String filePath) async {
    try {
      final text = await _channel.invokeMethod<String>('recognizeText', {
        'filePath': filePath,
      });
      return text ?? '';
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal menjalankan OCR lokal');
    }
  }

  Future<ParsedReceipt?> _scanWithGeminiVision(
    String filePath,
    String apiKey,
  ) async {
    var preparedPath = filePath;
    try {
      final compressed = await _channel.invokeMethod<String>(
        'prepareImageForAi',
        {'filePath': filePath},
      );
      if (compressed != null && compressed.isNotEmpty) {
        preparedPath = compressed;
      }
    } catch (_) {}

    final bytes = await File(preparedPath).readAsBytes();
    final b64 = base64Encode(bytes);

    const prompt = '''
Kamu adalah pembaca struk belanja & bukti transaksi Indonesia (Rupiah).
Ekstrak gambar struk ini menjadi JSON MURNI tanpa markdown dengan format persis:
{
  "merchantName": "Nama toko/resto/merchant",
  "date": "YYYY-MM-DD atau null jika tidak terbaca",
  "items": [
    {"name": "Nama produk/menu", "quantity": 1, "totalPrice": 15000, "category": "Makanan & Minuman"}
  ],
  "tax": 0,
  "serviceCharge": 0,
  "discount": 0,
  "total": 15000
}
Aturan penting:
- Semua nominal dalam integer Rupiah tanpa titik/koma (contoh: 15000, bukan "15.000").
- totalPrice pada setiap item adalah total baris item tersebut (qty x harga satuan).
- discount adalah angka positif (total potongan/promo/voucher).
- Jangan masukkan baris TUNAI, KEMBALI, QRIS, DEBIT, atau SUBTOTAL sebagai item.
- Untuk category pilih salah satu dari: "Makanan & Minuman", "Belanja", "Transportasi", "Tagihan & Utilitas", "Kesehatan", "Hiburan", "Lainnya".
''';

    final bodyPayload = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      },
    });

    const models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    Object? lastError;

    for (final model in models) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(apiKey)}',
        );
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        req.write(bodyPayload);
        final res = await req.close().timeout(const Duration(seconds: 16));
        final resBody = await res.transform(utf8.decoder).join();

        if (res.statusCode == 404) {
          lastError = 'Model $model tidak tersedia';
          continue;
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw Exception(
            'API Key Gemini tidak valid (HTTP ${res.statusCode})',
          );
        }
        if (res.statusCode == 429) {
          throw Exception('Kuota Gemini sementara penuh (HTTP 429)');
        }
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }

        final decoded = jsonDecode(resBody);
        if (decoded is! Map<String, dynamic>) return null;
        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) return null;
        final parts =
            ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
        if (parts == null || parts.isEmpty) return null;
        final text = (parts.first as Map)['text'] as String?;
        if (text == null || text.trim().isEmpty) return null;

        return ReceiptParser.parseGeminiJson(text);
      } catch (e) {
        lastError = e;
        if (e is SocketException || e is TimeoutException) rethrow;
      } finally {
        client.close(force: true);
      }
    }

    if (lastError != null) throw lastError;
    return null;
  }

  void dispose() {
    _sharedImageController.close();
  }
}

final receiptScannerServiceProvider = Provider<ReceiptScannerService>((ref) {
  final svc = ReceiptScannerService();
  ref.onDispose(svc.dispose);
  return svc;
});

final hasGeminiApiKeyProvider = FutureProvider<bool>((ref) {
  return ref.watch(receiptScannerServiceProvider).hasGeminiApiKey();
});
