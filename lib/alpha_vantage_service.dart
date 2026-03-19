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

class AlphaVantageService {
  final String _apiKey = dotenv.env['ALPHAVANTAGE_API_KEY'] ?? '';

  // ------------------------------
  // SYMBOL SEARCH
  // ------------------------------
  Future<SymbolResult?> verifySymbol(String input) async {
    final query = input.trim().toUpperCase();

    if (query.isEmpty || _apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://www.alphavantage.co/query'
          '?function=SYMBOL_SEARCH'
          '&keywords=$query'
          '&apikey=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data.containsKey("Error Message")) return null;
    if (data.containsKey("Note")) {
      throw Exception("API rate limit hit. Please wait 1 minute and try again.");
    }

    final List matches = data["bestMatches"] ?? [];
    if (matches.isEmpty) return null;

    final first = matches.first as Map<String, dynamic>;
    final symbol = (first["1. symbol"] ?? "").toString().toUpperCase();
    final name = (first["2. name"] ?? "").toString();

    // strict match
    if (symbol != query) return null;

    return SymbolResult(symbol: symbol, name: name);
  }

  // ------------------------------
  // CURRENT PRICE ONLY (GLOBAL_QUOTE)
  // ------------------------------
  Future<double?> fetchCurrentPrice(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://www.alphavantage.co/query'
          '?function=GLOBAL_QUOTE'
          '&symbol=$sym'
          '&apikey=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data.containsKey("Note")) {
      throw Exception("API rate limit hit. Please wait 1 minute and try again.");
    }
    if (data.containsKey("Error Message")) return null;

    final quote = data["Global Quote"];
    if (quote is! Map) return null;

    final priceStr = (quote["05. price"] ?? "").toString().trim();
    final price = double.tryParse(priceStr);

    if (price == null || price <= 0) return null;
    return price;
  }

  // ------------------------------
  // FALLBACK: DAILY series to get last close + previous close
  // Uses TIME_SERIES_DAILY_ADJUSTED because it’s usually reliable.
  // ------------------------------
  Future<QuoteResult?> _fetchFromDailySeries(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://www.alphavantage.co/query'
          '?function=TIME_SERIES_DAILY_ADJUSTED'
          '&symbol=$sym'
          '&outputsize=compact'
          '&apikey=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data.containsKey("Note")) {
      throw Exception("API rate limit hit. Please wait 1 minute and try again.");
    }
    if (data.containsKey("Error Message")) return null;

    final ts = data["Time Series (Daily)"];
    if (ts is! Map) return null;

    // keys are dates like "2026-02-14"
    final dates = ts.keys.map((e) => e.toString()).toList()..sort((a, b) => b.compareTo(a));
    if (dates.length < 2) return null;

    final latest = ts[dates[0]];
    final prev = ts[dates[1]];
    if (latest is! Map || prev is! Map) return null;

    // Adjusted close preferred; fallback to close
    final latestCloseStr = (latest["5. adjusted close"] ?? latest["4. close"] ?? "").toString().trim();
    final prevCloseStr = (prev["5. adjusted close"] ?? prev["4. close"] ?? "").toString().trim();

    final latestClose = double.tryParse(latestCloseStr);
    final prevClose = double.tryParse(prevCloseStr);

    if (latestClose == null || prevClose == null || latestClose <= 0 || prevClose <= 0) return null;

    return QuoteResult(price: latestClose, previousClose: prevClose);
  }

  // ------------------------------
  // CURRENT PRICE + PREVIOUS CLOSE
  // 1) Try GLOBAL_QUOTE
  // 2) If missing/blank previous close, fallback to DAILY series
  // ------------------------------
  Future<QuoteResult?> fetchQuoteWithPreviousClose(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty || _apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://www.alphavantage.co/query'
          '?function=GLOBAL_QUOTE'
          '&symbol=$sym'
          '&apikey=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data.containsKey("Note")) {
      throw Exception("API rate limit hit. Please wait 1 minute and try again.");
    }
    if (data.containsKey("Error Message")) return null;

    final quote = data["Global Quote"];
    if (quote is Map) {
      final priceStr = (quote["05. price"] ?? "").toString().trim();
      final prevStr = (quote["08. previous close"] ?? "").toString().trim();

      final price = double.tryParse(priceStr);
      final prev = double.tryParse(prevStr);

      // If both exist and valid, use GLOBAL_QUOTE
      if (price != null && prev != null && price > 0 && prev > 0) {
        return QuoteResult(price: price, previousClose: prev);
      }
    }

    // Fallback to daily series if GLOBAL_QUOTE is incomplete
    return _fetchFromDailySeries(sym);
  }
}