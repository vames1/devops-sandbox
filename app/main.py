import os
import time
from flask import Flask, jsonify

app = Flask(__name__)
START_TIME = time.time()
ENV_ID = os.environ.get('ENV_ID', 'unknown')
ENV_NAME = os.environ.get('ENV_NAME', 'unknown')

@app.route('/')
def index():
    return jsonify({
        'message': f'Hello from environment {ENV_NAME}!',
        'env_id': ENV_ID,
        'env_name': ENV_NAME,
        'uptime': int(time.time() - START_TIME)
    })

@app.route('/health')
def health():
    return jsonify({
        'status': 'ok',
        'env_id': ENV_ID,
        'uptime': int(time.time() - START_TIME)
    })

if __name__ == '__main__':
    port = int(os.environ.get('APP_PORT', 5000))
    app.run(host='0.0.0.0', port=port)
