import os
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

from sentiment_engine import run_analysis

load_dotenv()

app = Flask(__name__)
CORS(app)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/analysis/<symbol>", methods=["GET"])
def analysis(symbol: str):
    try:
        current_price = request.args.get("current_price", type=float)
        if current_price is None or current_price <= 0:
            return jsonify({"error": "current_price query param required and must be > 0"}), 400
    except (TypeError, ValueError):
        return jsonify({"error": "current_price must be a number"}), 400

    try:
        result = run_analysis(symbol.strip().upper(), current_price)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)