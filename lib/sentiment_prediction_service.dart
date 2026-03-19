import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum PredictionInterval {
  twelveHours('12 hours'),
  oneDay('One day'),
  threeDays('Three days'),
  oneWeek('One week'),
  twoWeeks('Two weeks'),
  threeWeeks('Three weeks');

  const PredictionInterval(this.label);
  final String label;

  String get apiKey => name;
}

class PlatformSentiment {
  final String platform;
  final int sentiment;
  final int reliability;

  PlatformSentiment({
    required this.platform,
    required this.sentiment,
    required this.reliability,
  });
}

class PricePrediction {
  final String intervalLabel;
  final double? predictedPrice;
  final int confidence;

  PricePrediction({
    required this.intervalLabel,
    this.predictedPrice,
    required this.confidence,
  });
}

class StockSentimentAnalysis {
  final String symbol;
  final List<PlatformSentiment> platformSentiments;
  final int mentionVolumePercentVsLastWeek;
  final int overallSentiment;
  final Map<PredictionInterval, PricePrediction> predictions;
  final bool isDemo;

  final bool isFallbackPrediction;
  final bool usingSampleMentions;
  final bool historicalPricesSynced;
  final double? correlationUsed;

  StockSentimentAnalysis({
    required this.symbol,
    required this.platformSentiments,
    required this.mentionVolumePercentVsLastWeek,
    required this.overallSentiment,
    required this.predictions,
    this.isDemo = false,
    this.isFallbackPrediction = false,
    this.usingSampleMentions = false,
    this.historicalPricesSynced = false,
    this.correlationUsed,
  });
}

class SentimentPredictionService {
  String? get baseUrl => dotenv.env['SENTIMENT_API_BASE_URL']?.trim();
  bool get isConfigured => baseUrl != null && baseUrl!.isNotEmpty;

  Future<StockSentimentAnalysis?> getAnalysisForSymbol({
    required String symbol,
    required double currentPrice,
    double? fallbackPrice,
  }) async {
    final price = currentPrice > 0 ? currentPrice : (fallbackPrice ?? 0);
    if (!isConfigured) return null;
    if (price <= 0) return null;

    try {
      final uri = Uri.parse('$baseUrl/analysis/$symbol').replace(
        queryParameters: {'current_price': price.toStringAsFixed(2)},
      );

      final response = await http
          .get(uri)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('timeout'),
      );

      if (response.statusCode != 200) return null;

      final map = jsonDecode(response.body) as Map<String, dynamic>;
      if (map.containsKey('error')) return null;

      return _parseResponse(symbol, map);
    } catch (_) {
      return null;
    }
  }

  static StockSentimentAnalysis getDemoAnalysis(
      String symbol,
      double currentPrice,
      ) {
    final sym = symbol.toUpperCase();
    final p = currentPrice > 0 ? currentPrice : defaultPriceForSymbol(sym);

    final platforms = [
      PlatformSentiment(platform: 'Reddit', sentiment: 58, reliability: 52),
      PlatformSentiment(platform: 'Twitter', sentiment: 62, reliability: 58),
      PlatformSentiment(platform: 'News', sentiment: 71, reliability: 85),
      PlatformSentiment(platform: 'StockTwits', sentiment: 55, reliability: 52),
    ];

    final intervals = PredictionInterval.values;
    final predictions = <PredictionInterval, PricePrediction>{};
    final factors = [1.0005, 1.001, 1.002, 1.003, 1.005, 1.008];

    for (var i = 0; i < intervals.length; i++) {
      predictions[intervals[i]] = PricePrediction(
        intervalLabel: intervals[i].label,
        predictedPrice: p * (i < factors.length ? factors[i] : 1.002),
        confidence: 50,
      );
    }

    return StockSentimentAnalysis(
      symbol: sym,
      platformSentiments: platforms,
      mentionVolumePercentVsLastWeek: 0,
      overallSentiment: 62,
      predictions: predictions,
      isDemo: true,
      isFallbackPrediction: true,
      usingSampleMentions: true,
      historicalPricesSynced: false,
      correlationUsed: null,
    );
  }

  static double defaultPriceForSymbol(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'TSLA':
        return 250.0;
      case 'AAPL':
        return 225.0;
      case 'MSFT':
        return 420.0;
      case 'GOOGL':
      case 'GOOG':
        return 175.0;
      case 'AMZN':
        return 195.0;
      case 'NVDA':
        return 135.0;
      case 'META':
        return 575.0;
      default:
        return 100.0;
    }
  }

  StockSentimentAnalysis _parseResponse(
      String symbol,
      Map<String, dynamic> map,
      ) {
    final platforms = <PlatformSentiment>[];
    final list = map['platform_sentiments'] as List<dynamic>?;

    if (list != null) {
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        platforms.add(
          PlatformSentiment(
            platform: (m['platform'] ?? '').toString(),
            sentiment: _toInt(m['sentiment']).clamp(0, 100),
            reliability: _toInt(m['reliability']).clamp(0, 100),
          ),
        );
      }
    }

    final mentionPct = _toInt(map['mention_volume_percent_vs_last_week']);
    final overall = _toInt(map['overall_sentiment']);

    final predMap = <PredictionInterval, PricePrediction>{};
    final predictionsJson = map['predictions'] as Map<String, dynamic>?;

    if (predictionsJson != null) {
      for (final entry in PredictionInterval.values) {
        final v = predictionsJson[entry.apiKey] as Map<String, dynamic>?;
        if (v != null) {
          final price = (v['predicted_price'] as num?)?.toDouble();
          final conf = _toInt(v['confidence']);

          predMap[entry] = PricePrediction(
            intervalLabel: entry.label,
            predictedPrice: price,
            confidence: conf.clamp(0, 100),
          );
        }
      }
    }

    final correlation = (map['correlation_used'] as num?)?.toDouble();

    return StockSentimentAnalysis(
      symbol: symbol.toUpperCase(),
      platformSentiments: platforms,
      mentionVolumePercentVsLastWeek: mentionPct,
      overallSentiment: overall.clamp(1, 100),
      predictions: predMap,
      isFallbackPrediction: map['is_fallback_prediction'] == true,
      usingSampleMentions: map['using_sample_mentions'] == true,
      historicalPricesSynced: map['historical_prices_synced'] == true,
      correlationUsed: correlation,
    );
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }
}