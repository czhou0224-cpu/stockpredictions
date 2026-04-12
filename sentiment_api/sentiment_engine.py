"""
News-based sentiment analysis and correlation-based price prediction.

Sources (scraped via public RSS — no Reddit API):
- CNBC headlines (Google News RSS: site:cnbc.com)
- Bloomberg headlines (Google News RSS: site:bloomberg.com)

No sample/fake article text — if feeds return nothing, platforms show neutral with 0 mentions.
"""
from __future__ import annotations

import logging
import math
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import os
from urllib.parse import quote

import feedparser
import numpy as np
import requests
from textblob import TextBlob

from database import (
    get_sentiment_history,
    get_price_history,
    get_price_dates_without_sentiment,
    save_sentiment,
    save_price,
    get_mention_count_this_week,
    get_mention_count_last_week,
    init_db,
)

log = logging.getLogger("sentiment_engine")

# Per /analysis request: how many past trading days to backfill (RSS calls = 2 * this).
BACKFILL_MAX_DATES_PER_REQUEST = 12

PLATFORM_RELIABILITY = {
    "bloomberg": 88,
    "cnbc": 82,
}


def analyze_sentiment_nlp(text: str) -> float:
    if not text or not str(text).strip():
        return 50.0
    blob = TextBlob(str(text))
    polarity = blob.sentiment.polarity
    return max(0, min(100, 50 + polarity * 50))


def _fetch_google_news_rss(symbol: str, site_domain: str, max_items: int = 30) -> List[Tuple[str, int]]:
    """
    Public Google News RSS for queries like: TSLA site:cnbc.com
    Returns list of (text, mention_count).
    """
    query = f"{symbol} site:{site_domain}"
    url = f"https://news.google.com/rss/search?q={quote(query)}&hl=en-US&gl=US&ceid=US:en"
    results: List[Tuple[str, int]] = []
    try:
        parsed = feedparser.parse(url)
        for entry in getattr(parsed, "entries", [])[:max_items]:
            title = getattr(entry, "title", "") or ""
            summary = getattr(entry, "summary", "") or ""
            text = f"{title}. {summary}".strip()
            if text:
                results.append((text, 1))
    except Exception as e:
        log.warning("Google News RSS failed symbol=%s site=%s: %s", symbol, site_domain, e)
    return results


def _fetch_google_news_rss_for_day(
    symbol: str, site_domain: str, day: datetime, max_items: int = 25
) -> List[Tuple[str, int]]:
    """Google News RSS for a single calendar day (after:/before:)."""
    d0 = day.strftime("%Y-%m-%d")
    d1 = (day + timedelta(days=1)).strftime("%Y-%m-%d")
    query = f"{symbol} site:{site_domain} after:{d0} before:{d1}"
    url = f"https://news.google.com/rss/search?q={quote(query)}&hl=en-US&gl=US&ceid=US:en"
    results: List[Tuple[str, int]] = []
    try:
        parsed = feedparser.parse(url)
        for entry in getattr(parsed, "entries", [])[:max_items]:
            title = getattr(entry, "title", "") or ""
            summary = getattr(entry, "summary", "") or ""
            text = f"{title}. {summary}".strip()
            if text:
                results.append((text, 1))
    except Exception as e:
        log.warning(
            "Google News RSS (dated) failed symbol=%s site=%s day=%s: %s",
            symbol,
            site_domain,
            d0,
            e,
        )
    return results


def _fetch_bloomberg_markets_rss_filtered(symbol: str, max_items: int = 40) -> List[Tuple[str, int]]:
    """Bloomberg public markets RSS; keep items that mention the ticker."""
    url = "https://feeds.bloomberg.com/markets/news.rss"
    sym = symbol.upper()
    results: List[Tuple[str, int]] = []
    try:
        parsed = feedparser.parse(url)
        for entry in getattr(parsed, "entries", [])[:max_items]:
            title = getattr(entry, "title", "") or ""
            summary = getattr(entry, "summary", "") or ""
            text = f"{title}. {summary}".strip()
            if text and sym in text.upper():
                results.append((text, 1))
    except Exception as e:
        log.warning("Bloomberg RSS parse failed: %s", e)
    return results


def fetch_news_mentions(symbol: str) -> Tuple[Dict[str, List[Tuple[str, int]]], bool, bool]:
    """
    Returns:
      (mentions_by_platform, using_sample_mentions always False, insufficient_news)

    No placeholder articles — only real headlines from scraping/RSS.
    """
    symbol = symbol.upper()

    cnbc = _fetch_google_news_rss(symbol, "cnbc.com")
    bloomberg_rss = _fetch_bloomberg_markets_rss_filtered(symbol)
    bloomberg_gn = _fetch_google_news_rss(symbol, "bloomberg.com")

    # Merge Bloomberg sources, de-dupe by text prefix
    seen = set()
    bloomberg: List[Tuple[str, int]] = []
    for pair in bloomberg_rss + bloomberg_gn:
        key = pair[0][:120]
        if key not in seen:
            seen.add(key)
            bloomberg.append(pair)

    mentions = {
        "cnbc": cnbc,
        "bloomberg": bloomberg,
    }

    total = sum(len(v) for v in mentions.values())
    insufficient = total == 0

    log.info(
        "news scrape %s: cnbc=%d bloomberg=%d insufficient=%s",
        symbol,
        len(cnbc),
        len(bloomberg),
        insufficient,
    )

    # Never use sample placeholder text
    return mentions, False, insufficient


def _persist_platform_sentiment(
    symbol: str, date_str: str, mentions: Dict[str, List[Tuple[str, int]]]
) -> List[Dict]:
    results = []
    for platform, texts_with_count in mentions.items():
        if not texts_with_count:
            score = 50.0
            mention_count = 0
        else:
            scores = [analyze_sentiment_nlp(t) for t, _ in texts_with_count]
            score = float(np.mean(scores))
            mention_count = sum(c for _, c in texts_with_count)

        save_sentiment(symbol, date_str, platform, score, mention_count)

        results.append({
            "platform": platform.replace("_", " ").title(),
            "sentiment": int(round(score)),
            "reliability": PLATFORM_RELIABILITY.get(platform.lower().replace(" ", "_"), 50),
        })

    return results


def aggregate_platform_sentiment(symbol: str, mentions: Dict[str, List[Tuple[str, int]]]) -> List[Dict]:
    today = datetime.utcnow().strftime("%Y-%m-%d")
    return _persist_platform_sentiment(symbol, today, mentions)


def backfill_sentiment_catchup(symbol: str) -> int:
    """
    For trading days we have prices for but no sentiment yet, scrape dated news and persist.
    Capped per request so one /analysis call stays responsive; repeated app use fills history.
    """
    symbol = symbol.upper()
    today = datetime.utcnow().strftime("%Y-%m-%d")
    missing = get_price_dates_without_sentiment(
        symbol, lookback_days=90, limit=BACKFILL_MAX_DATES_PER_REQUEST
    )
    missing = [d for d in missing if d < today]
    filled = 0
    for d_str in missing:
        try:
            day = datetime.strptime(d_str, "%Y-%m-%d")
        except ValueError:
            continue
        cnbc = _fetch_google_news_rss_for_day(symbol, "cnbc.com", day)
        time.sleep(0.2)
        bloomberg = _fetch_google_news_rss_for_day(symbol, "bloomberg.com", day)
        time.sleep(0.2)
        mentions = {"cnbc": cnbc, "bloomberg": bloomberg}
        _persist_platform_sentiment(symbol, d_str, mentions)
        filled += 1
        log.info("sentiment backfill %s %s cnbc=%d bloomberg=%d", symbol, d_str, len(cnbc), len(bloomberg))
    return filled


def sync_price_history_from_finnhub(symbol: str, max_days: int = 100) -> bool:
    token = os.environ.get("FINNHUB_API_KEY", "").strip()
    if not token:
        try:
            from dotenv import load_dotenv

            load_dotenv(Path(__file__).resolve().parent.parent / ".env")
            token = os.environ.get("FINNHUB_API_KEY", "").strip()
        except Exception:
            pass
    if not token:
        log.warning("FINNHUB_API_KEY not set in environment; historical price sync skipped")
        return False

    now = int(datetime.utcnow().timestamp())
    from_ts = now - (max_days + 35) * 86400
    url = (
        "https://finnhub.io/api/v1/stock/candle"
        f"?symbol={quote(symbol)}&resolution=D&from={from_ts}&to={now}&token={token}"
    )

    try:
        response = requests.get(url, timeout=15)
        if response.status_code == 403:
            log.info(
                "Finnhub stock/candle returned 403 for %s (many free keys only include /quote); "
                "historical sync will use yfinance fallback if installed",
                symbol,
            )
            return False
        if response.status_code != 200:
            log.warning("Finnhub HTTP %s for %s", response.status_code, symbol)
            return False

        data = response.json()
        if data.get("s") != "ok":
            log.warning("Finnhub candle status=%s for %s", data.get("s"), symbol)
            return False

        t_list = data.get("t") or []
        c_list = data.get("c") or []
        if not t_list or len(t_list) != len(c_list):
            log.warning("Finnhub: empty or mismatched candle arrays for %s", symbol)
            return False

        pairs: List[Tuple[int, float]] = []
        for ts, close in zip(t_list, c_list):
            try:
                cval = float(close)
                if cval > 0:
                    pairs.append((int(ts), cval))
            except (TypeError, ValueError):
                continue

        if not pairs:
            return False

        pairs.sort(key=lambda x: x[0])
        tail = pairs[-max_days:]
        saved_any = False
        for ts, close_val in tail:
            d = datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")
            save_price(symbol, d, close_val)
            saved_any = True

        if saved_any:
            log.info("Finnhub: synced %d price rows for %s", len(tail), symbol)
        return saved_any
    except Exception as e:
        log.warning("Finnhub sync failed for %s: %s", symbol, e)
        return False


def sync_price_history_from_yfinance(symbol: str, max_days: int = 100) -> bool:
    """
    Fallback daily OHLC when Finnhub stock/candle is not on the API plan (403).
    Uses Yahoo via yfinance (not an official API; fine for dev / research).
    """
    try:
        import yfinance as yf
    except ImportError:
        log.warning("yfinance not installed; pip install yfinance for historical fallback")
        return False

    symbol = symbol.upper()
    try:
        t = yf.Ticker(symbol)
        df = t.history(period="2y", interval="1d", auto_adjust=True)
        if df is None or df.empty:
            log.warning("yfinance: no rows for %s", symbol)
            return False

        df = df.sort_index().tail(max_days)
        saved_any = False
        for idx, row in df.iterrows():
            close_val = float(row.get("Close", 0) or 0)
            if close_val <= 0:
                continue
            d = idx.strftime("%Y-%m-%d") if hasattr(idx, "strftime") else str(idx)[:10]
            save_price(symbol, d, close_val)
            saved_any = True

        if saved_any:
            log.info("yfinance: synced %d price rows for %s (Finnhub candle unavailable)", len(df), symbol)
        return saved_any
    except Exception as e:
        log.warning("yfinance sync failed for %s: %s", symbol, e)
        return False


def sync_price_history(symbol: str, max_days: int = 100) -> bool:
    """Finnhub daily candles when plan allows; else Yahoo/yfinance fallback."""
    if sync_price_history_from_finnhub(symbol, max_days=max_days):
        return True
    log.info("Finnhub candles skipped/unavailable for %s; trying yfinance fallback", symbol)
    return sync_price_history_from_yfinance(symbol, max_days=max_days)


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


def _realized_daily_volatility(symbol: str, lookback_days: int = 90) -> float:
    """
    Std dev of simple daily returns from stored closes (recent realized vol).
    Used only to scale heuristic forecasts toward plausible magnitudes — not a guarantee.
    """
    rows = get_price_history(symbol, days=lookback_days)
    if len(rows) < 6:
        return 0.02

    prices = [p for _, p in sorted(rows, key=lambda r: r[0])]
    rets: List[float] = []
    for i in range(len(prices) - 1):
        a, b = prices[i], prices[i + 1]
        if a > 0 and b > 0:
            rets.append((b - a) / a)

    if len(rets) < 5:
        return 0.02

    sigma = float(np.std(np.array(rets, dtype=float)))
    # Typical US large-cap ~1–3% daily; TSLA often higher; clamp so UI stays bounded
    return float(max(0.006, min(sigma, 0.08)))


def predict_price_movement(
    symbol: str,
    current_aggregate_sentiment: float,
    current_price: float,
    correlation: Optional[float],
    horizon_days: float,
) -> Tuple[float, int]:
    daily_vol = _realized_daily_volatility(symbol)
    h = max(0.25, min(float(horizon_days), 21.0))
    vol_over_h = daily_vol * math.sqrt(h)

    if correlation is None:
        tilt = (current_aggregate_sentiment - 50.0) / 50.0
        tilt = float(max(-1.0, min(1.0, tilt)))
        total_return = tilt * vol_over_h * 0.55
        total_return = float(max(-0.28, min(0.28, total_return)))
        predicted = current_price * (1.0 + total_return)
        return predicted, 25

    sentiment_rows = get_sentiment_history(symbol, days=90)
    if not sentiment_rows:
        return current_price, 25

    hist_sentiments = [r[2] for r in sentiment_rows]
    avg_sentiment = float(np.mean(hist_sentiments))

    sentiment_diff = (current_aggregate_sentiment - avg_sentiment) / 100.0
    # Map weak numeric signal to [-1, 1]; correlation + sentiment set direction / strength
    raw_tilt = correlation * sentiment_diff * 12.0
    tilt = float(max(-1.0, min(1.0, raw_tilt)))

    # Magnitude scales with sqrt(horizon) × realized daily vol (rough random-walk scaling)
    total_return = tilt * vol_over_h * 0.95
    max_move = min(0.42, 4.5 * daily_vol * math.sqrt(h))
    total_return = float(max(-max_move, min(max_move, total_return)))

    predicted = current_price * (1.0 + total_return)
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

    historical_prices_synced = sync_price_history(symbol)

    sentiment_backfill_days = backfill_sentiment_catchup(symbol)

    mentions, using_sample_mentions, insufficient_news = fetch_news_mentions(symbol)
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
        "insufficient_news": insufficient_news,
        "historical_prices_synced": historical_prices_synced,
        "sentiment_backfill_days": sentiment_backfill_days,
    }
