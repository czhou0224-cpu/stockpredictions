"""
Sentiment analysis and correlation-based price prediction.

1. Pull comments/mentions from social platforms (Reddit, etc.)
2. Run NLP sentiment (TextBlob)
3. Correlate past sentiment with past price movement (stored in SQLite)
4. Use current sentiment + learned correlation to predict price movement

Notes:
- Historical price data is synced from Alpha Vantage so correlation can work.
- Social mentions are still sample placeholders unless real APIs are added.
"""
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import os

from textblob import TextBlob
import numpy as np
import requests

from database import (
    get_sentiment_history,
    get_price_history,
    save_sentiment,
    save_price,
    get_mention_count_this_week,
    get_mention_count_last_week,
    init_db,
)

PLATFORM_RELIABILITY = {
    "reddit": 52,
    "twitter": 58,
    "news": 85,
    "stocktwits": 52,
    "yahoo_finance": 48,
    "bloomberg": 88,
    "cnbc": 82,
    "financial_times": 84,
}


def analyze_sentiment_nlp(text: str) -> float:
    if not text or not str(text).strip():
        return 50.0
    blob = TextBlob(str(text))
    polarity = blob.sentiment.polarity
    return max(0, min(100, 50 + polarity * 50))


def fetch_social_mentions(symbol: str) -> Tuple[Dict[str, List[Tuple[str, int]]], bool]:
    """
    Returns:
      ({ platform: [ (text, mention_count) ] }, using_sample_data)

    This still uses placeholder/sample text until real APIs are added.
    """
    sample_reddit = [
        (f"{symbol} looking strong today, earnings beat", 1),
        (f"Bought more {symbol} on the dip", 1),
        (f"Worried about {symbol} margins", 1),
    ]
    sample_twitter = [
        (f"${symbol} to the moon", 1),
        (f"{symbol} stock analysis", 1),
    ]

    mentions = {
        "reddit": sample_reddit,
        "twitter": sample_twitter,
        "news": [(f"{symbol} stock update", 1)],
        "stocktwits": [(f"${symbol} bull", 1)],
    }

    return mentions, True


def aggregate_platform_sentiment(symbol: str, mentions: Dict[str, List[Tuple[str, int]]]) -> List[Dict]:
    today = datetime.utcnow().strftime("%Y-%m-%d")
    results = []

    for platform, texts_with_count in mentions.items():
        if not texts_with_count:
            score = 50
            mention_count = 0
        else:
            scores = [analyze_sentiment_nlp(t) for t, _ in texts_with_count]
            score = float(np.mean(scores))
            mention_count = sum(c for _, c in texts_with_count)

        save_sentiment(symbol, today, platform, score, mention_count)

        results.append({
            "platform": platform.replace("_", " ").title(),
            "sentiment": int(round(score)),
            "reliability": PLATFORM_RELIABILITY.get(platform.lower().replace(" ", "_"), 50),
        })

    return results


def sync_price_history_from_alpha_vantage(symbol: str, max_days: int = 100) -> bool:
    api_key = os.environ.get("ALPHAVANTAGE_API_KEY", "").strip()
    if not api_key:
        return False

    url = (
        "https://www.alphavantage.co/query"
        f"?function=TIME_SERIES_DAILY_ADJUSTED&symbol={symbol}&outputsize=compact&apikey={api_key}"
    )

    try:
        response = requests.get(url, timeout=12)
        if response.status_code != 200:
            return False

        data = response.json()
        if "Error Message" in data or "Note" in data:
            return False

        ts = data.get("Time Series (Daily)")
        if not isinstance(ts, dict) or not ts:
            return False

        dates = sorted(ts.keys(), reverse=True)[:max_days]
        saved_any = False

        for d in dates:
            row = ts.get(d, {})
            close_str = str(row.get("5. adjusted close") or row.get("4. close") or "").strip()
            close_val = float(close_str)
            if close_val > 0:
                save_price(symbol, d, close_val)
                saved_any = True

        return saved_any
    except Exception:
        return False


def compute_correlation(symbol: str, lookback_days: int = 60) -> Optional[float]:
    sentiment_rows = get_sentiment_history(symbol, days=lookback_days)
    price_rows = get_price_history(symbol, days=lookback_days + 1)

    if len(price_rows) < 2 or not sentiment_rows:
        return None

    by_date: Dict[str, List[float]] = {}
    for date, platform, score, _ in sentiment_rows:
        by_date.setdefault(date, []).append(score)
    daily_sentiment = {d: float(np.mean(s)) for d, s in by_date.items()}

    price_by_date = {d: p for d, p in price_rows}
    dates_sorted = sorted(price_by_date.keys())

    returns = []
    sentiments = []

    for i in range(len(dates_sorted) - 1):
        d = dates_sorted[i]
        d_next = dates_sorted[i + 1]

        if d not in daily_sentiment:
            continue

        p = price_by_date[d]
        p_next = price_by_date[d_next]
        if p <= 0:
            continue

        ret = (p_next - p) / p
        returns.append(ret)
        sentiments.append(daily_sentiment[d])

    if len(returns) < 5:
        return None

    corr = float(np.corrcoef(sentiments, returns)[0, 1])
    if np.isnan(corr):
        return None
    return corr


def predict_price_movement(
    symbol: str,
    current_aggregate_sentiment: float,
    current_price: float,
    correlation: Optional[float],
    horizon_days: float,
) -> Tuple[float, int]:
    if correlation is None:
        drift = (current_aggregate_sentiment - 50) / 50 * 0.01 * min(horizon_days, 7)
        return current_price * (1 + drift), 25

    sentiment_rows = get_sentiment_history(symbol, days=90)
    if not sentiment_rows:
        return current_price, 25

    hist_sentiments = [r[2] for r in sentiment_rows]
    avg_sentiment = float(np.mean(hist_sentiments))

    sentiment_diff = (current_aggregate_sentiment - avg_sentiment) / 100
    expected_return_per_day = correlation * sentiment_diff * 0.02
    total_return = expected_return_per_day * min(horizon_days, 21)

    predicted = current_price * (1 + total_return)
    confidence = int(min(90, 40 + abs(correlation) * 40 + min(30, len(sentiment_rows) // 3)))
    return predicted, max(25, confidence)


def get_horizon_days(interval_key: str) -> float:
    m = {
        "twelveHours": 0.5,
        "oneDay": 1,
        "threeDays": 3,
        "oneWeek": 7,
        "twoWeeks": 14,
        "threeWeeks": 21,
    }
    return m.get(interval_key, 1)


def run_analysis(symbol: str, current_price: float) -> Dict:
    init_db()
    symbol = symbol.upper()
    today = datetime.utcnow().strftime("%Y-%m-%d")

    save_price(symbol, today, current_price)

    historical_prices_synced = sync_price_history_from_alpha_vantage(symbol)

    mentions, using_sample_mentions = fetch_social_mentions(symbol)
    platform_sentiments = aggregate_platform_sentiment(symbol, mentions)

    if platform_sentiments:
        overall = int(round(np.mean([p["sentiment"] for p in platform_sentiments])))
    else:
        overall = 50

    this_week = get_mention_count_this_week(symbol)
    last_week = get_mention_count_last_week(symbol)
    if last_week > 0:
        mention_pct = int(round((this_week - last_week) / last_week * 100))
    else:
        mention_pct = 100 if this_week > 0 else 0

    correlation = compute_correlation(symbol)
    is_fallback_prediction = correlation is None

    intervals = [
        ("twelveHours", "12 hours"),
        ("oneDay", "One day"),
        ("threeDays", "Three days"),
        ("oneWeek", "One week"),
        ("twoWeeks", "Two weeks"),
        ("threeWeeks", "Three weeks"),
    ]

    predictions = {}
    for key, label in intervals:
        horizon = get_horizon_days(key)
        pred_price, confidence = predict_price_movement(
            symbol,
            float(overall),
            current_price,
            correlation,
            horizon,
        )
        predictions[key] = {
            "interval_label": label,
            "predicted_price": round(pred_price, 2),
            "confidence": confidence,
        }

    return {
        "symbol": symbol,
        "current_price": current_price,
        "platform_sentiments": platform_sentiments,
        "overall_sentiment": overall,
        "mention_volume_percent_vs_last_week": mention_pct,
        "predictions": predictions,
        "correlation_used": correlation if correlation is not None else None,
        "is_fallback_prediction": is_fallback_prediction,
        "using_sample_mentions": using_sample_mentions,
        "historical_prices_synced": historical_prices_synced,
    }