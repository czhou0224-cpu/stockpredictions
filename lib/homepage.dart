import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:stockpredicitonsss/analysispage.dart';
import 'package:stockpredicitonsss/profilepage.dart';
import 'package:stockpredicitonsss/UserProfileFirestoreService.dart';
import 'port.dart';
import 'finnhub_service.dart';
import 'prediction_display_adjustment.dart';
import 'sentiment_prediction_service.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 0;
  String _analysisSymbol = 'TSLA';
  String _analysisDisplayName = 'Tesla';

  final UserProfileFirestoreService _profileService = UserProfileFirestoreService();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_attachProfilePhotoStream);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  void _attachProfilePhotoStream(User? user) {
    _profileSub?.cancel();
    _profileSub = null;
    if (user == null) {
      if (mounted) setState(() => _profilePhotoUrl = null);
      return;
    }
    _profileSub = _profileService.userProfileStream(user.uid).listen((data) {
      if (!mounted) return;
      final raw = data?['photoUrl']?.toString().trim();
      setState(() {
        _profilePhotoUrl = (raw != null && raw.isNotEmpty) ? raw : null;
      });
    });
  }

  Widget _appBarProfileAvatar() {
    final url = _profilePhotoUrl;
    const size = 40.0;
    if (url == null || url.isEmpty) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: Colors.white24,
        child: Icon(Icons.person, color: Colors.white, size: 22),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white24,
          child: Icon(Icons.person, color: Colors.white, size: 22),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(
            width: size,
            height: size,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openStockFromPortfolio(String symbol, String displayName) {
    final sym = symbol.toUpperCase().trim();
    final name = displayName.trim().isEmpty ? sym : displayName.trim();
    setState(() {
      _analysisSymbol = sym;
      _analysisDisplayName = name;
      _selectedIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      appBar: _selectedIndex == 1
          ? null
          : AppBar(
        backgroundColor: Colors.blueAccent.shade700,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Sentiment Prediction",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "AI-powered analysis",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70, fontSize: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _appBarProfileAvatar(),
          ],
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            const HomeTab(),
            Analysispage(
              key: ValueKey(_analysisSymbol),
              initialSymbol: _analysisSymbol,
              initialDisplayName: _analysisDisplayName,
            ),
            Portfolio(onOpenStockInAnalysis: _openStockFromPortfolio),
            const ProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent.shade200,
        unselectedItemColor: Colors.white70,
        backgroundColor: const Color(0xFF101010),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart_sharp), label: "Analysis"),
          BottomNavigationBarItem(icon: Icon(Icons.cases_rounded), label: "Portfolio"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),

        // 1) Top Predictions (placeholder)
        Expanded(
          flex: 7,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 15, 20, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SizedBox(height: 8),
                  Text(
                    "Top Predictions",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Expanded(child: TopPredictionsList()),
                ],
              ),
            ),
          ),
        ),

        // 2) Market Overview (live)
        Expanded(
          flex: 4,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Market Overview",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  SizedBox(height: 8),
                  Expanded(child: MarketCarousel()),
                ],
              ),
            ),
          ),
        ),

        // 3) Sentiment Reliability (placeholder section restored)
        Expanded(
          flex: 4,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 15, 20, 10),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Sentiment Reliability",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 10),

                    // Placeholder rows (keep it simple; you can wire real values later)
                    _ReliabilityRow(label: "Twitter/X", percentage: 78),
                    SizedBox(height: 10),
                    _ReliabilityRow(label: "Reddit", percentage: 72),
                    SizedBox(height: 10),
                    _ReliabilityRow(label: "News", percentage: 85),
                    SizedBox(height: 10),
                    _ReliabilityRow(label: "TikTok", percentage: 41),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PredictedStockMove {
  final String symbol;
  final double predictedIncreasePct;
  final double predictedIncreaseValue;

  const PredictedStockMove({
    required this.symbol,
    required this.predictedIncreasePct,
    required this.predictedIncreaseValue,
  });
}

class TopPredictionsList extends StatefulWidget {
  const TopPredictionsList({super.key});

  @override
  State<TopPredictionsList> createState() => _TopPredictionsListState();
}

class _TopPredictionsListState extends State<TopPredictionsList> {
  final FinnhubService _finnhubService = FinnhubService();
  final SentimentPredictionService _sentimentService = SentimentPredictionService();
  static const int _maxSymbolsToScore = 14;
  static const int _parallelWorkers = 4;
  static const Duration _quoteTimeout = Duration(seconds: 10);
  static const Duration _analysisTimeout = Duration(seconds: 25);

  final List<String> _candidateSymbols = const [
    // Technology / AI
    'AAPL',
    'MSFT',
    'NVDA',
    'AMD',
    'AVGO',
    'GOOGL',
    'META',
    // Consumer / retail
    'AMZN',
    'COST',
    'WMT',
    'TSLA',
    // Financials
    'JPM',
    'BAC',
    'GS',
    // Energy
    'XOM',
    'CVX',
    'SLB',
    // Defense / aerospace
    'LMT',
    'NOC',
    'RTX',
    'GD',
    // Healthcare
    'JNJ',
    'PFE',
    'UNH',
    // Industrials / transport
    'UNP',
    'CAT',
    'DE',
    // Materials / commodities
    'NUE',
    'FCX',
    // Real estate / infrastructure
    'PLD',
    'AMT',
  ];

  late final Future<List<PredictedStockMove>> _predictionsFuture;

  @override
  void initState() {
    super.initState();
    _predictionsFuture = _loadTopPredictions();
  }

  Future<List<PredictedStockMove>> _loadTopPredictions() async {
    final results = <PredictedStockMove>[];
    final symbols = _candidateSymbols.take(_maxSymbolsToScore).toList();

    Future<PredictedStockMove?> evaluateSymbol(String symbol) async {
      final quote = await _finnhubService
          .fetchQuoteWithPreviousClose(symbol)
          .timeout(_quoteTimeout, onTimeout: () => null);
      final currentPrice = quote?.price ??
          SentimentPredictionService.defaultPriceForSymbol(symbol);

      final analysis = await _sentimentService
          .getAnalysisForSymbol(
            symbol: symbol,
            currentPrice: currentPrice,
          )
          .timeout(_analysisTimeout, onTimeout: () => null);

      final prediction = analysis?.predictions[PredictionInterval.oneWeek] ??
          SentimentPredictionService.getDemoAnalysis(symbol, currentPrice)
              .predictions[PredictionInterval.oneWeek];

      final predictedPrice = prediction?.predictedPrice;
      if (predictedPrice == null || currentPrice <= 0) return null;

      final adjusted = PredictionDisplayAdjustment.adjustedPredictedPrice(
        symbol: symbol,
        currentPrice: currentPrice,
        modelPredictedPrice: predictedPrice,
        quote: quote,
      );
      if (adjusted == null) return null;

      final variedIncreasePct = ((adjusted - currentPrice) / currentPrice) * 100.0;
      final increaseValue = adjusted - currentPrice;

      return PredictedStockMove(
        symbol: symbol,
        predictedIncreasePct: variedIncreasePct,
        predictedIncreaseValue: increaseValue,
      );
    }

    for (int i = 0; i < symbols.length; i += _parallelWorkers) {
      final end = (i + _parallelWorkers < symbols.length)
          ? i + _parallelWorkers
          : symbols.length;
      final batch = symbols.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map((symbol) async {
          try {
            return await evaluateSymbol(symbol).timeout(
              _quoteTimeout + _analysisTimeout,
              onTimeout: () => null,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      results.addAll(batchResults.whereType<PredictedStockMove>());
      if (results.length >= 8) {
        // We only need enough rows to rank and display quickly.
        break;
      }
    }

    results.removeWhere(
      (item) => item.predictedIncreasePct <= 0 || item.predictedIncreaseValue <= 0,
    );
    results.sort((a, b) => b.predictedIncreasePct.compareTo(a.predictedIncreasePct));
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PredictedStockMove>>(
      future: _predictionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <PredictedStockMove>[];
        if (data.isEmpty) {
          return const Center(
            child: Text(
              'No predictions available right now.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.separated(
          itemCount: data.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
          itemBuilder: (context, index) {
            final item = data[index];
            final isPositive = item.predictedIncreaseValue >= 0;
            final rank = index + 1;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$rank. ${item.symbol}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    '${isPositive ? '+' : '-'}${item.predictedIncreasePct.abs().toStringAsFixed(2)}% (\$${item.predictedIncreaseValue.abs().toStringAsFixed(2)})',
                    style: TextStyle(
                      color: isPositive ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class MarketCarousel extends StatefulWidget {
  const MarketCarousel({super.key});

  @override
  State<MarketCarousel> createState() => _MarketCarouselState();
}

class _MarketCarouselState extends State<MarketCarousel> {
  final FinnhubService _service = FinnhubService();

  // name -> { price, changeValue, changePct }
  final Map<String, Map<String, dynamic>> _marketData = {};

  // index name -> ETF proxy + multiplier
  final Map<String, Map<String, dynamic>> _config = {
    'NASDAQ': {'symbol': 'QQQ', 'multiplier': 40}, // QQQ ~ 1/40 of NASDAQ
    'S&P 500': {'symbol': 'SPY', 'multiplier': 10}, // your assumption
    'Dow Jones': {'symbol': 'DIA', 'multiplier': 100}, // DIA ~ 1/100 of Dow
    'Russell 2000': {'symbol': 'IWM', 'multiplier': 10}, // your assumption
  };

  @override
  void initState() {
    super.initState();
    _loadMarketData();
  }

  Future<void> _loadMarketData() async {
    for (final entry in _config.entries) {
      final name = entry.key;
      final symbol = (entry.value['symbol'] as String);
      final multiplier = (entry.value['multiplier'] as num).toDouble();

      try {
        final quote = await _service.fetchQuoteWithPreviousClose(symbol);

        if (quote == null) {
          // Prevent infinite loader by storing a "failed" placeholder
          _marketData[name] = {
            'price': null,
            'changeValue': null,
            'changePct': null,
          };
        } else {
          final indexPrice = quote.price * multiplier;
          final prevPrice = quote.previousClose * multiplier;
          final changeValue = indexPrice - prevPrice;
          final changePct = prevPrice == 0 ? 0.0 : (changeValue / prevPrice) * 100.0;

          _marketData[name] = {
            'price': indexPrice,
            'changeValue': changeValue,
            'changePct': changePct,
          };
        }

        // Finnhub free-tier courtesy delay between symbols
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        _marketData[name] = {
          'price': null,
          'changeValue': null,
          'changePct': null,
        };
        await Future.delayed(const Duration(milliseconds: 1300));
      }

      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarouselSlider(
      options: CarouselOptions(
        enlargeCenterPage: true,
        autoPlay: false,
        viewportFraction: 0.82,
      ),
      items: _config.keys.map((name) {
        final data = _marketData[name];

        // Not loaded yet
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final price = data['price'] as double?;
        final changeValue = data['changeValue'] as double?;
        final changePct = data['changePct'] as double?;

        // Failed / missing
        final bool hasData = price != null && changeValue != null && changePct != null;

        final bool isPositive = hasData ? (changeValue >= 0) : true;
        final color = isPositive ? Colors.green : Colors.red;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF121212),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: ListTile(
            leading: Icon(
              isPositive ? Icons.trending_up : Icons.trending_down,
              color: color,
              size: 30,
            ),
            title: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasData ? "\$${price.toStringAsFixed(0)}" : "—",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Text(
                  hasData
                      ? "${isPositive ? "+" : "-"}\$${changeValue.abs().toStringAsFixed(0)} (${changePct.toStringAsFixed(2)}%)"
                      : "—",
                  style: TextStyle(
                    color: hasData ? color : Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// -------------------
// Sentiment Reliability placeholders (restored)
// -------------------
class _ReliabilityRow extends StatelessWidget {
  final String label;
  final double percentage;

  const _ReliabilityRow({required this.label, required this.percentage});

  @override
  Widget build(BuildContext context) {
    final Color textColor = percentage >= 50 ? Colors.green : Colors.red;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        Text(
          '${percentage.toStringAsFixed(0)}%',
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}