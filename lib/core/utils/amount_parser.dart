/// Parser nominal pintar untuk Rupiah (integer) dengan dukungan singkatan & kalkulator sederhana.
///
/// Contoh yang didukung:
/// - `15000`, `1.250.000`, `Rp 25.000` -> `15000`, `1250000`, `25000`
/// - `15k`, `15rb`, `15ribu` -> `15000`
/// - `1,5jt`, `1.5jt`, `1,5juta` -> `1500000`
/// - `2,5k` -> `2500`
/// - Ekspresi aritmetika: `15k+5k`, `25000*3`, `100k-15k`, `100000÷4`, `20k+10k×2`
class AmountParser {
  AmountParser._();

  static int? parse(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll('rp', '')
        .replaceAll(' ', '')
        .replaceAll('×', '*')
        .replaceAll('x', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-');

    if (cleaned.isEmpty) return null;

    // Jika hanya angka/singkatan tanpa operator
    if (!_hasOperator(cleaned)) {
      return _parseSingleNumber(cleaned);
    }

    // Evaluasi ekspresi aritmetika sederhana dengan urutan operasi (* / dulu, lalu + -)
    try {
      final value = _evaluateExpression(cleaned);
      if (value == null || value.isNaN || value.isInfinite) return null;
      final rounded = value.round();
      return rounded >= 0 ? rounded : null;
    } catch (_) {
      return null;
    }
  }

  static bool hasExpression(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll('rp', '')
        .replaceAll(' ', '')
        .replaceAll('×', '*')
        .replaceAll('x', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-');
    return _hasOperator(cleaned);
  }

  static bool _hasOperator(String s) {
    for (var i = 1; i < s.length; i++) {
      final c = s[i];
      if (c == '+' || c == '-' || c == '*' || c == '/') {
        return true;
      }
    }
    return false;
  }

  static double? _evaluateExpression(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      final isOp = ch == '+' || ch == '-' || ch == '*' || ch == '/';
      if (isOp && i > 0 && buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
        tokens.add(ch);
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    // Hapus operator menggantung di akhir (saat pengguna masih mengetik)
    while (tokens.isNotEmpty && _isOpToken(tokens.last)) {
      tokens.removeLast();
    }
    if (tokens.isEmpty) return null;

    // Konversi operand ke double
    final values = <double>[];
    final ops = <String>[];

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (i.isEven) {
        final parsed = _parseSingleDouble(t);
        if (parsed == null) return null;
        values.add(parsed);
      } else {
        if (!_isOpToken(t)) return null;
        ops.add(t);
      }
    }

    if (values.length != ops.length + 1) return null;

    // Pass 1: * dan /
    var idx = 0;
    while (idx < ops.length) {
      final op = ops[idx];
      if (op == '*' || op == '/') {
        final left = values[idx];
        final right = values[idx + 1];
        if (op == '/' && right == 0) return null;
        final res = op == '*' ? left * right : left / right;
        values[idx] = res;
        values.removeAt(idx + 1);
        ops.removeAt(idx);
      } else {
        idx++;
      }
    }

    // Pass 2: + dan -
    var total = values[0];
    for (var i = 0; i < ops.length; i++) {
      if (ops[i] == '+') {
        total += values[i + 1];
      } else {
        total -= values[i + 1];
      }
    }
    return total;
  }

  static bool _isOpToken(String token) =>
      token == '+' || token == '-' || token == '*' || token == '/';

  static int? _parseSingleNumber(String token) {
    final val = _parseSingleDouble(token);
    if (val == null || val.isNaN || val.isInfinite) return null;
    final rounded = val.round();
    return rounded >= 0 ? rounded : null;
  }

  static double? _parseSingleDouble(String token) {
    if (token.isEmpty) return null;

    var multiplier = 1.0;
    var numPart = token;

    if (numPart.endsWith('juta')) {
      multiplier = 1000000.0;
      numPart = numPart.substring(0, numPart.length - 4);
    } else if (numPart.endsWith('jt')) {
      multiplier = 1000000.0;
      numPart = numPart.substring(0, numPart.length - 2);
    } else if (numPart.endsWith('m')) {
      // miliar
      multiplier = 1000000000.0;
      numPart = numPart.substring(0, numPart.length - 1);
    } else if (numPart.endsWith('ribu')) {
      multiplier = 1000.0;
      numPart = numPart.substring(0, numPart.length - 4);
    } else if (numPart.endsWith('rb')) {
      multiplier = 1000.0;
      numPart = numPart.substring(0, numPart.length - 2);
    } else if (numPart.endsWith('k')) {
      multiplier = 1000.0;
      numPart = numPart.substring(0, numPart.length - 1);
    }

    if (numPart.isEmpty) return null;

    if (multiplier > 1.0) {
      // Dengan suffix (mis. 1,5jt atau 1.5jt): koma/titik tunggal = desimal.
      final normalized = numPart.replaceAll(',', '.');
      final parsed = double.tryParse(normalized);
      return parsed == null ? null : parsed * multiplier;
    }

    // Tanpa suffix: titik dianggap pemisah ribuan Indonesia (1.250.000).
    // Jika ada koma, anggap desimal (jarang di IDR tapi aman).
    final withoutThousands = numPart.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withoutThousands);
  }
}
