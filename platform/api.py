#!/usr/bin/env python3
"""
DevOps Sandbox Platform - Control API
6 endpoints wrapping the platform scripts
"""

import os
import json
import subprocess
import glob
from datetime import datetime, timezone
from flask import Flask, jsonify, request

app = Flask(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORM_DIR = os.path.join(BASE_DIR, 'platform')
ENVS_DIR = os.path.join(BASE_DIR, 'envs')
LOGS_DIR = os.path.join(BASE_DIR, 'logs')

# ── Helpers ───────────────────────────────────────────────────────────────────

def load_env(env_id):
    """Load environment state file"""
    state_file = os.path.join(ENVS_DIR, f'{env_id}.json')
    if not os.path.exists(state_file):
        return None
    with open(state_file) as f:
        return json.load(f)

def list_envs():
    """List all active environments"""
    envs = []
    for state_file in glob.glob(os.path.join(ENVS_DIR, '*.json')):
        try:
            with open(state_file) as f:
                env = json.load(f)
            # Calculate TTL remaining
            expires_at = datetime.fromisoformat(
                env['expires_at'].replace('Z', '+00:00')
            )
            now = datetime.now(timezone.utc)
            ttl_remaining = max(0, int((expires_at - now).total_seconds()))
            env['ttl_remaining'] = ttl_remaining
            envs.append(env)
        except Exception as e:
            continue
    return envs

def run_script(script, args=[]):
    """Run a platform script and return output"""
    cmd = ['bash', os.path.join(PLATFORM_DIR, script)] + args
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=BASE_DIR
    )
    return result.stdout, result.stderr, result.returncode

# ── Routes ────────────────────────────────────────────────────────────────────

@app.route('/health')
def platform_health():
    """Platform health check"""
    return jsonify({
        'status': 'ok',
        'service': 'devops-sandbox-api',
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    })

@app.route('/envs', methods=['POST'])
def create_env():
    """Create a new sandbox environment"""
    data = request.get_json() or {}
    name = data.get('name', 'myapp')
    ttl = str(data.get('ttl', 1800))

    stdout, stderr, code = run_script('create_env.sh', [name, ttl])

    if code != 0:
        return jsonify({
            'error': 'Failed to create environment',
            'details': stderr
        }), 500

    # Find the newly created env
    envs = sorted(list_envs(), key=lambda x: x['created_at'], reverse=True)
    new_env = next((e for e in envs if e['name'] == name), None)

    return jsonify({
        'message': f'Environment {name} created successfully',
        'env': new_env,
        'output': stdout
    }), 201

@app.route('/envs', methods=['GET'])
def get_envs():
    """List all active environments with TTL remaining"""
    envs = list_envs()
    return jsonify({
        'count': len(envs),
        'environments': envs
    })

@app.route('/envs/<env_id>', methods=['DELETE'])
def destroy_env(env_id):
    """Destroy a specific environment"""
    env = load_env(env_id)
    if not env:
        return jsonify({'error': f'Environment {env_id} not found'}), 404

    stdout, stderr, code = run_script('destroy_env.sh', [env_id])

    if code != 0:
        return jsonify({
            'error': 'Failed to destroy environment',
            'details': stderr
        }), 500

    return jsonify({
        'message': f'Environment {env_id} destroyed successfully',
        'output': stdout
    })

@app.route('/envs/<env_id>/logs', methods=['GET'])
def get_logs(env_id):
    """Get last 100 lines of app.log for an environment"""
    log_file = os.path.join(LOGS_DIR, env_id, 'app.log')

    # Also check archived logs
    archived_log = os.path.join(LOGS_DIR, 'archived', env_id, 'app.log')

    if os.path.exists(log_file):
        path = log_file
    elif os.path.exists(archived_log):
        path = archived_log
    else:
        return jsonify({'error': f'No logs found for {env_id}'}), 404

    with open(path) as f:
        lines = f.readlines()

    last_100 = lines[-100:] if len(lines) > 100 else lines
    return jsonify({
        'env_id': env_id,
        'lines': len(last_100),
        'logs': ''.join(last_100)
    })

@app.route('/envs/<env_id>/health', methods=['GET'])
def get_health(env_id):
    """Get last 10 health check results for an environment"""
    health_file = os.path.join(LOGS_DIR, env_id, 'health.log')
    archived = os.path.join(LOGS_DIR, 'archived', env_id, 'health.log')

    if os.path.exists(health_file):
        path = health_file
    elif os.path.exists(archived):
        path = archived
    else:
        return jsonify({
            'env_id': env_id,
            'results': [],
            'message': 'No health data yet'
        })

    with open(path) as f:
        lines = f.readlines()

    last_10 = lines[-10:] if len(lines) > 10 else lines
    results = []
    for line in last_10:
        parts = line.strip().split(' | ')
        if len(parts) >= 3:
            results.append({
                'timestamp': parts[0],
                'status': parts[1],
                'latency': parts[2]
            })

    env = load_env(env_id)
    return jsonify({
        'env_id': env_id,
        'status': env['status'] if env else 'unknown',
        'results': results
    })

@app.route('/envs/<env_id>/outage', methods=['POST'])
def trigger_outage(env_id):
    """Trigger an outage simulation"""
    data = request.get_json() or {}
    mode = data.get('mode', 'crash')

    valid_modes = ['crash', 'pause', 'network', 'recover']
    if mode not in valid_modes:
        return jsonify({
            'error': f'Invalid mode: {mode}',
            'valid_modes': valid_modes
        }), 400

    env = load_env(env_id)
    if not env:
        return jsonify({'error': f'Environment {env_id} not found'}), 404

    stdout, stderr, code = run_script(
        'simulate_outage.sh',
        ['--env', env_id, '--mode', mode]
    )

    if code != 0:
        return jsonify({
            'error': 'Failed to simulate outage',
            'details': stderr
        }), 500

    return jsonify({
        'message': f'Outage simulation ({mode}) triggered on {env_id}',
        'output': stdout
    })

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    port = int(os.environ.get('API_PORT', 5001))
    print(f'🚀 DevOps Sandbox API starting on port {port}')
    app.run(host='0.0.0.0', port=port, debug=False)
