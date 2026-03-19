# Sentiment-based stock prediction API

This Flask backend drives the **Analysis** page predictions in the Flutter app. All prediction values (price by interval, platform sentiment, mention volume, overall sentiment) come from here—**not** from hardcoded formulas in the app.

## How it works

1. **Social mentions**  
   Fetches comments/mentions about the symbol from supported platforms (e.g. Reddit, Twitter).  
   Current code uses placeholder data; replace `fetch_social_mentions()` in `sentiment_engine.py` with real APIs (PRAW, Tweepy, News API, etc.).

2. **NLP sentiment**  
   Runs **TextBlob** on each mention to get polarity. Scores are mapped to 0–100 (bad → good) per platform.

3. **Historical correlation**  
   Uses **SQLite** (`sentiment_data.db`) to store:
   - Past sentiment (by symbol, date, platform)
   - Past prices (from your own ingestion or Alpha Vantage)  
   Then computes how well past sentiment correlated with next-day price movement.

4. **Prediction**  
   Combines:
   - Current aggregate sentiment (from step 2)
   - Historical correlation (from step 3)
   - Current price (passed by the app from Alpha Vantage)  
   to produce a predicted price per interval (12h, 1d, 3d, 1w, 2w, 3w) and a confidence score.

## Setup

```bash
cd sentiment_api
python -m venv venv
venv\Scripts\activate   # Windows
pip install -r requirements.txt
```

## Run

```bash
python app.py
```

Server runs at `http://127.0.0.1:5000` (or set `PORT`).

## Flutter app

In the project `.env` add:

```
SENTIMENT_API_BASE_URL=http://10.0.2.2:5000
```

- **Android emulator**: use `10.0.2.2` for host machine’s `localhost`.
- **iOS simulator / real device**: use your machine’s LAN IP (e.g. `http://192.168.1.5:5000`).

The app sends `GET /analysis/TSLA?current_price=250.50` (current price from Alpha Vantage) and displays the returned predictions and sentiment.

## Endpoint

- **GET** `/analysis/<symbol>?current_price=<number>`  
  Returns JSON: `platform_sentiments`, `overall_sentiment`, `mention_volume_percent_vs_last_week`, `predictions` (per-interval price + confidence).  
  All values are derived from social sentiment analysis and correlation with past price movement.
