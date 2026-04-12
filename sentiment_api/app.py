import logging
import os
import sys
from datetime import datetime, timezone

from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

# Load project root .env (parent of sentiment_api/) so FINNHUB_API_KEY works when running from sentiment_api/
_root = Path(__file__).resolve().parent.parent
load_dotenv(_root / ".env")
load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,
    force=True,
)
logging.getLogger("werkzeug").setLevel(logging.INFO)
log = logging.getLogger("sentiment_api")

from sentiment_engine import run_analysis

app = Flask(__name__)
CORS(app)


@app.before_request
def log_incoming_request():
    """Log every request so you can see if the Flutter app reaches the backend."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    remote = request.remote_addr or "?"
    log.info(
        ">>> REQUEST %s %s from %s | User-Agent: %s",
        request.method,
        request.path,
        remote,
        request.headers.get("User-Agent", "")[:80],
    )


@app.after_request
def log_response(response):
    log.info("<<< RESPONSE %s %s -> %s", request.method, request.path, response.status_code)
    return response


@app.route("/health")
def health():
    log.info("health check OK")
    return jsonify({"status": "ok"})


@app.route("/analysis/<symbol>", methods=["GET"])
def analysis(symbol: str):
    sym = symbol.strip().upper()
    try:
        current_price = request.args.get("current_price", type=float)
        if current_price is None or current_price <= 0:
            log.warning(
                "analysis %s rejected: bad current_price=%r args=%s",
                sym,
                current_price,
                dict(request.args),
            )
            return jsonify({"error": "current_price query param required and must be > 0"}), 400
    except (TypeError, ValueError) as e:
        log.warning("analysis %s rejected: %s", sym, e)
        return jsonify({"error": "current_price must be a number"}), 400

    log.info(
        "analysis START symbol=%s current_price=%s (Flutter/backend communication OK if you see this line)",
        sym,
        current_price,
    )

    try:
        result = run_analysis(sym, current_price)
        sample = result.get("using_sample_mentions")
        hist = result.get("historical_prices_synced")
        fallback = result.get("is_fallback_prediction")
        log.info(
            "analysis DONE symbol=%s sample_mentions=%s historical_prices_synced=%s fallback_prediction=%s",
            sym,
            sample,
            hist,
            fallback,
        )
        return jsonify(result)
    except Exception as e:
        log.exception("analysis FAILED symbol=%s: %s", sym, e)
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)