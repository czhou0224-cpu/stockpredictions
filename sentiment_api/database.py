"""
SQLite storage for historical sentiment and price data.
Used to correlate past sentiment with past price movement for predictions.
"""
import sqlite3
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

DB_PATH = "sentiment_data.db"


def get_conn():
    return sqlite3.connect(DB_PATH)


def init_db():
    """Create tables for sentiment history and price history."""
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS sentiment_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            date TEXT NOT NULL,
            platform TEXT NOT NULL,
            sentiment_score REAL NOT NULL,
            mention_count INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(symbol, date, platform)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS price_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            date TEXT NOT NULL,
            open_price REAL,
            close_price REAL NOT NULL,
            high_price REAL,
            low_price REAL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(symbol, date)
        )
    """)
    conn.commit()
    conn.close()


def save_sentiment(symbol: str, date: str, platform: str, sentiment_score: float, mention_count: int = 0):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        INSERT OR REPLACE INTO sentiment_history (symbol, date, platform, sentiment_score, mention_count)
        VALUES (?, ?, ?, ?, ?)
    """, (symbol.upper(), date, platform, sentiment_score, mention_count))
    conn.commit()
    conn.close()


def save_price(symbol: str, date: str, close_price: float, open_price: Optional[float] = None,
               high_price: Optional[float] = None, low_price: Optional[float] = None):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        INSERT OR REPLACE INTO price_history (symbol, date, close_price, open_price, high_price, low_price)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (symbol.upper(), date, close_price, open_price or close_price, high_price or close_price, low_price or close_price))
    conn.commit()
    conn.close()


def get_sentiment_history(symbol: str, days: int = 90) -> List[Tuple[str, str, float, int]]:
    """Returns list of (date, platform, sentiment_score, mention_count)."""
    conn = get_conn()
    cur = conn.cursor()
    since = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
    cur.execute("""
        SELECT date, platform, sentiment_score, mention_count
        FROM sentiment_history
        WHERE symbol = ? AND date >= ?
        ORDER BY date
    """, (symbol.upper(), since))
    rows = cur.fetchall()
    conn.close()
    return rows


def get_price_dates_without_sentiment(
    symbol: str, lookback_days: int = 90, limit: int = 20
) -> List[str]:
    """
    Trading dates we have in price_history but no sentiment row yet (catch-up backfill).
    Oldest first so repeated requests gradually fill history toward today.
    """
    conn = get_conn()
    cur = conn.cursor()
    since = (datetime.utcnow() - timedelta(days=lookback_days)).strftime("%Y-%m-%d")
    cur.execute(
        """
        SELECT p.date FROM price_history p
        WHERE p.symbol = ? AND p.date >= ?
        AND NOT EXISTS (
            SELECT 1 FROM sentiment_history s
            WHERE s.symbol = p.symbol AND s.date = p.date
        )
        ORDER BY p.date ASC
        LIMIT ?
        """,
        (symbol.upper(), since, limit),
    )
    rows = [r[0] for r in cur.fetchall()]
    conn.close()
    return rows


def get_price_history(symbol: str, days: int = 90) -> List[Tuple[str, float]]:
    """Returns list of (date, close_price)."""
    conn = get_conn()
    cur = conn.cursor()
    since = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
    cur.execute("""
        SELECT date, close_price
        FROM price_history
        WHERE symbol = ? AND date >= ?
        ORDER BY date
    """, (symbol.upper(), since))
    rows = cur.fetchall()
    conn.close()
    return rows


def get_mention_count_this_week(symbol: str) -> int:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT COALESCE(SUM(mention_count), 0) FROM sentiment_history
        WHERE symbol = ? AND date >= date('now', '-7 days')
    """, (symbol.upper(),))
    row = cur.fetchone()
    conn.close()
    return row[0] if row else 0


def get_mention_count_last_week(symbol: str) -> int:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT COALESCE(SUM(mention_count), 0) FROM sentiment_history
        WHERE symbol = ? AND date >= date('now', '-14 days') AND date < date('now', '-7 days')
    """, (symbol.upper(),))
    row = cur.fetchone()
    conn.close()
    return row[0] if row else 0
