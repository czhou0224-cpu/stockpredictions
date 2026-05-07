import 'finnhub_service.dart';

/// Display-layer adjustment applied on top of the backend model price.
/// Matches homepage "Top Predictions": daily momentum tilt, sector theme boost,
/// and deterministic per-symbol jitter so Analysis and Home stay consistent.
class PredictionDisplayAdjustment {
  PredictionDisplayAdjustment._();

  static const Map<String, double> themeBoostPct = {
    'LMT': 1.80,
    'NOC': 1.70,
    'RTX': 1.60,
    'GD': 1.60,
    'XOM': 1.30,
    'CVX': 1.20,
    'SLB': 1.20,
    'NUE': 0.80,
    'FCX': 0.70,
  };

  /// Deterministic spread per symbol (~ -0.72% .. +0.72%), same as homepage.
  static double symbolJitterPct(String symbol) {
    final hash = symbol.toUpperCase().codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return ((hash % 13) - 6) * 0.12;
  }

  /// Returns adjusted price, or null if inputs are invalid.
  static double? adjustedPredictedPrice({
    required String symbol,
    required double currentPrice,
    required double modelPredictedPrice,
    QuoteResult? quote,
  }) {
    if (currentPrice <= 0 || modelPredictedPrice <= 0) return null;

    final rawIncreaseValue = modelPredictedPrice - currentPrice;
    final rawIncreasePct = (rawIncreaseValue / currentPrice) * 100.0;

    final dailyMomentumPct = quote != null && quote.previousClose > 0
        ? ((quote.price - quote.previousClose) / quote.previousClose) * 100.0
        : 0.0;

    final sym = symbol.toUpperCase().trim();
    final theme = themeBoostPct[sym] ?? 0.0;
    final variedIncreasePct =
        rawIncreasePct + (dailyMomentumPct * 0.35) + theme + symbolJitterPct(sym);

    return currentPrice * (1.0 + variedIncreasePct / 100.0);
  }
}
