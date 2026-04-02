import 'package:flutter/material.dart';
import 'alpha_vantage_service.dart';
import 'sentiment_prediction_service.dart';

class Analysispage extends StatefulWidget {
  const Analysispage({super.key});

  @override
  State<Analysispage> createState() => _AnalysispageState();
}

class _AnalysispageState extends State<Analysispage> {
  bool searching = false;
  String _stockSymbol = 'TSLA';
  String _stockDisplayName = 'Tesla';
  PredictionInterval? _selectedInterval;
  StockSentimentAnalysis? _analysis;
  QuoteResult? _quote;
  bool _loading = true;

  final AlphaVantageService _alphaVantage = AlphaVantageService();
  final SentimentPredictionService _sentimentService =
  SentimentPredictionService();

  @override
  void initState() {
    super.initState();
    _selectedInterval = PredictionInterval.oneDay;
    _loadAnalysis();
  }

  String _sentimentApiHelpText() {
    final err = SentimentPredictionService.lastFetchError;
    const base =
        "Live API unreachable (showing demo). Android emulator: SENTIMENT_API_BASE_URL=http://10.0.2.2:5000 in .env; physical phone: use your PC LAN IP. Restart app after .env changes. ";
    if (err == null || err.isEmpty) return base;
    return "$base\nDetail: $err";
  }

  Future<void> _loadAnalysis() async {
    setState(() => _loading = true);

    try {
      QuoteResult? quote =
      await _alphaVantage.fetchQuoteWithPreviousClose(_stockSymbol);

      if (quote == null) {
        await Future.delayed(const Duration(milliseconds: 1500));
        quote = await _alphaVantage.fetchQuoteWithPreviousClose(_stockSymbol);
      }

      final price = quote?.price ?? 0.0;
      if (mounted) setState(() => _quote = quote);

      if (_sentimentService.isConfigured) {
        final fallbackPrice = price <= 0
            ? SentimentPredictionService.defaultPriceForSymbol(_stockSymbol)
            : null;

        final analysis = await _sentimentService.getAnalysisForSymbol(
          symbol: _stockSymbol,
          currentPrice: price,
          fallbackPrice: fallbackPrice,
        );

        if (mounted) {
          setState(() {
            _analysis =
                analysis ??
                    SentimentPredictionService.getDemoAnalysis(_stockSymbol, price);
          });
        }
      } else if (mounted) {
        setState(() {
          _analysis = SentimentPredictionService.getDemoAnalysis(
            _stockSymbol,
            price,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _analysis = SentimentPredictionService.getDemoAnalysis(_stockSymbol, 0);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showReliabilitySheet(String platform, int sentiment, int reliability) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                platform,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                "Platform Reliability: $reliability%",
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                _reliabilityExplanation(reliability),
                style: const TextStyle(color: Colors.white54, fontSize: 15),
              ),
              const SizedBox(height: 25),
            ],
          ),
        );
      },
    );
  }

  String _reliabilityExplanation(int reliability) {
    if (reliability >= 70) {
      return "This platform is highly reliable and strongly correlates with real stock movement.";
    } else if (reliability >= 50) {
      return "This platform has moderate reliability for predicting stock direction.";
    }
    return "This platform shows low correlation with actual performance. Use caution when interpreting sentiment.";
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intervals = PredictionInterval.values;
    final intervalLabels = intervals.map((e) => e.label).toList();

    final currentPrice =
        _quote?.price ??
            (_analysis != null
                ? SentimentPredictionService.defaultPriceForSymbol(_stockSymbol)
                : 0.0);

    final prevClose = _quote?.previousClose;
    final priceChange =
    prevClose != null && currentPrice > 0 && prevClose > 0
        ? currentPrice - prevClose
        : null;

    final interval = _selectedInterval ?? PredictionInterval.oneDay;
    final prediction = _analysis?.predictions[interval];

    final dropdownValue =
    _selectedInterval != null &&
        intervalLabels.contains(_selectedInterval!.label)
        ? _selectedInterval!.label
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blueAccent.shade700,
        title: searching
            ? const TextField(
          autofocus: false,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search stocks...",
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        )
            : Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Stock Analysis",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "AI-powered Insights",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => searching = !searching);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      )
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            children: [
              const SizedBox(height: 25),
              Text(
                _stockDisplayName,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Price Prediction",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                                fontSize: 25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            dropdownColor: Colors.grey[900],
                            hint: const Text(
                              "Select Time Range",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            value: dropdownValue,
                            style: const TextStyle(color: Colors.white),
                            items: intervalLabels.map((String range) {
                              return DropdownMenuItem<String>(
                                value: range,
                                child: Text(
                                  range,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              final idx = intervalLabels.indexOf(value);
                              if (idx >= 0 && idx < intervals.length) {
                                setState(
                                      () => _selectedInterval = intervals[idx],
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_analysis != null)
                        Wrap(
                          children: [
                            if (_analysis!.isDemo)
                              _statusChip("Demo data", Colors.orangeAccent),
                            if (_analysis!.isFallbackPrediction &&
                                !_analysis!.isDemo)
                              _statusChip(
                                "Fallback prediction",
                                Colors.amber,
                              ),
                            if (_analysis!.insufficientNews && !_analysis!.isDemo)
                              _statusChip(
                                "No CNBC/Bloomberg headlines found",
                                Colors.orange,
                              ),
                            if (_analysis!.historicalPricesSynced)
                              _statusChip(
                                "Historical prices synced",
                                Colors.greenAccent,
                              ),
                            if (!_analysis!.historicalPricesSynced &&
                                !_analysis!.isDemo)
                              _statusChip(
                                "No historical price sync",
                                Colors.redAccent,
                              ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  if (prediction != null &&
                                      prediction.predictedPrice != null &&
                                      prediction.predictedPrice! > 0)
                                    Text(
                                      "\$${prediction.predictedPrice!.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  else
                                    const Text(
                                      "—",
                                      style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  Text(
                                    "In ${interval.label}",
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.white70,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_analysis != null &&
                                      _analysis!.correlationUsed != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                      ),
                                      child: Text(
                                        "Correlation used: ${_analysis!.correlationUsed!.toStringAsFixed(3)}",
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white54,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  prediction != null
                                      ? "${prediction.confidence}%"
                                      : "—",
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  "Confidence",
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Current Price: ${currentPrice > 0 ? "\$${currentPrice.toStringAsFixed(2)}" : "—"}",
                              style: const TextStyle(
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              priceChange != null
                                  ? "Change vs. prev. close: ${priceChange >= 0 ? "+" : ""}\$${priceChange.toStringAsFixed(2)}"
                                  : "Change vs. prev. close: —",
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: priceChange != null
                                    ? (priceChange >= 0
                                    ? Colors.green
                                    : Colors.red)
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_analysis != null && _analysis!.isDemo)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _sentimentApiHelpText(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      if (_analysis != null &&
                          _analysis!.insufficientNews &&
                          !_analysis!.isDemo)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "No headlines were returned from CNBC/Bloomberg RSS (Google News + feeds). Try again later or check server logs.",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                      if (_analysis != null &&
                          _analysis!.isFallbackPrediction &&
                          !_analysis!.isDemo)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "Prediction is using fallback drift because historical sentiment-price correlation is not available yet.",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      if (!_sentimentService.isConfigured)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            "Set SENTIMENT_API_BASE_URL in .env and run the sentiment API for predictions based on CNBC + Bloomberg news sentiment.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade200,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "News Sentiment",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 180,
                        child:
                        _analysis != null &&
                            _analysis!.platformSentiments.isNotEmpty
                            ? ListView.builder(
                          itemCount:
                          _analysis!.platformSentiments.length,
                          itemBuilder: (context, index) {
                            final p =
                            _analysis!.platformSentiments[index];
                            return SocialSentimentRow(
                              platform: p.platform,
                              sentiment: p.sentiment.clamp(0, 100),
                              reliability: p.reliability.clamp(
                                0,
                                100,
                              ),
                              onTap: () => _showReliabilitySheet(
                                p.platform,
                                p.sentiment,
                                p.reliability,
                              ),
                            );
                          },
                        )
                            : ListView(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              child: Text(
                                "Platform sentiment from news API (NLP on CNBC + Bloomberg).",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Key Metrics",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _analysis != null
                                        ? "${_analysis!.mentionVolumePercentVsLastWeek >= 0 ? "+" : ""}${_analysis!.mentionVolumePercentVsLastWeek}%"
                                        : "—",
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Mention Volume vs last week",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(left: 10),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _analysis != null
                                        ? "${_analysis!.overallSentiment}"
                                        : "—",
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Overall Sentiment (1–100)",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SocialSentimentRow extends StatelessWidget {
  final String platform;
  final int sentiment;
  final int reliability;
  final VoidCallback? onTap;

  const SocialSentimentRow({
    super.key,
    required this.platform,
    required this.sentiment,
    required this.reliability,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool positive = sentiment >= 50;
    final Color barColor = positive ? Colors.green : Colors.red;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                platform,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "$sentiment%",
              style: TextStyle(
                color: barColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 70,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (sentiment.clamp(0, 100) / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}