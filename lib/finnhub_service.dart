import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SymbolResult {
  final String symbol;
  final String name;

  SymbolResult({
    required this.symbol,
    required this.name,
  });
}

class QuoteResult {
  final double price;
  final double previousClose;

  QuoteResult({
    required this.price,
    required this.previousClose,
  });
}

/// Live quotes, search, and daily history via [Finnhub](https://finnhub.io/docs/api).
class FinnhubService {
  static const _base = 'https://finnhub.io/api/v1';

  String get _token => dotenv.env['FINNHUB_API_KEY']?.trim() ?? '';

  // ------------------------------
  // SYMBOL SEARCH
  // ------------------------------
  Future<SymbolResult?> verifySymbol(String input) async {
    final query = input.trim().toUpperCase();
    if (query.isEmpty || _token.isEmpty) return null;

    // Fast-path: if quote resolves, the symbol is tradable enough for our app.
    final quoteUrl = Uri.parse(
      '$_base/quote?symbol=${Uri.encodeComponent(query)}&token=$_token',
    );
    final quoteRes = await http.get(quoteUrl);
    if (quoteRes.statusCode == 429) {
      throw Exception('Finnhub rate limit — wait a minute and try again.');
    }
    if (quoteRes.statusCode == 200) {
      final q = jsonDecode(quoteRes.body) as Map<String, dynamic>;
      final c = (q['c'] as num?)?.toDouble();
      if (c != null && c > 0) {
        return SymbolResult(symbol: query, name: query);
      }
    }

    final url = Uri.parse(
      '$_base/search?q=${Uri.encodeComponent(query)}&token=$_token',
    );

    final response = await http.get(url);
    if (response.statusCode == 429) {
      throw Exception('Finnhub rate limit — wait a minute and try again.');
    }
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['result'];
    if (results is! List || results.isEmpty) return null;

    for (final raw in results) {
      if (raw is! Map<String, dynamic>) continue;
      final sym = (raw['symbol'] ?? '').toString().toUpperCase();
      final plain = sym.contains(':') ? sym.split(':').last : sym;
      if (plain == query) {
        final name = (raw['description'] ?? plain).toString();
        return SymbolResult(symbol: plain, name: name);
      }
    }

    return null;
  }

  // ------------------------------
  // CURRENT PRICE ONLY
  // ------------------------------
  Future<double?> fetchCurrentPrice(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _token.isEmpty) return null;

    final url = Uri.parse(
      '$_base/quote?symbol=${Uri.encodeComponent(sym)}&token=$_token',
    );

    final response = await http.get(url);
    if (response.statusCode == 429) {
      throw Exception('Finnhub rate limit — wait a minute and try again.');
    }
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final c = (data['c'] as num?)?.toDouble();
    if (c == null || c <= 0) return null;
    return c;
  }

  // ------------------------------
  // DAILY CANDLES: last two closes (fallback)
  // ------------------------------
  Future<QuoteResult?> _fetchQuoteFromCandles(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _token.isEmpty) return null;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final fromSec = nowSec - 21 * 86400;

    final url = Uri.parse(
      '$_base/stock/candle?symbol=${Uri.encodeComponent(sym)}'
      '&resolution=D&from=$fromSec&to=$nowSec&token=$_token',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['s'] != 'ok') return null;

    final tRaw = data['t'];
    final cRaw = data['c'];
    if (tRaw is! List || cRaw is! List || tRaw.length < 2 || tRaw.length != cRaw.length) {
      return null;
    }

    final pairs = <List<num>>[];
    for (var i = 0; i < tRaw.length; i++) {
      final ts = tRaw[i];
      final close = cRaw[i];
      if (ts is num && close is num && close > 0) {
        pairs.add([ts, close]);
      }
    }
    if (pairs.length < 2) return null;

    pairs.sort((a, b) => a[0].compareTo(b[0]));
    final last = pairs[pairs.length - 1][1].toDouble();
    final prev = pairs[pairs.length - 2][1].toDouble();
    if (last <= 0 || prev <= 0) return null;

    return QuoteResult(price: last, previousClose: prev);
  }

  // ------------------------------
  // QUOTE + PREVIOUS CLOSE
  // ------------------------------
  Future<QuoteResult?> fetchQuoteWithPreviousClose(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _token.isEmpty) return null;

    final url = Uri.parse(
      '$_base/quote?symbol=${Uri.encodeComponent(sym)}&token=$_token',
    );

    final response = await http.get(url);
    if (response.statusCode == 429) {
      throw Exception('Finnhub rate limit — wait a minute and try again.');
    }
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

    final c = (data['c'] as num?)?.toDouble();
    final pc = (data['pc'] as num?)?.toDouble();

    if (c != null && pc != null && c > 0 && pc > 0) {
      return QuoteResult(price: c, previousClose: pc);
    }

    return _fetchQuoteFromCandles(sym);
  }
}
