#!/usr/bin/env python3
"""OpenRouter usage tracker — standalone macOS menu bar companion.

Calls OpenRouter's public API for total credits/usage, and reads Hermes'
session DB (OpenRouter rows only) for the per-model breakdown. No Sumopod,
no local estimates, no Hermes internal metrics.

Published as ``openrouter-usage`` — a clean, shareable macOS menu bar app.
"""
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def _load_key():
    env = Path.home() / '.hermes' / '.env'
    if not env.exists():
        return None
    for line in env.read_text().splitlines():
        if line.startswith('OPENROUTER_API_KEY='):
            return line.split('=', 1)[1].strip().strip('"')
    return None


def fetch_credits():
    """Call OpenRouter credits API for the overall account balance."""
    key = _load_key()
    if not key:
        return {'ok': False, 'error': 'No OPENROUTER_API_KEY found'}
    try:
        req = urllib.request.Request(
            'https://openrouter.ai/api/v1/credits',
            headers={'Authorization': f'Bearer {key}', 'Accept': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read().decode())
            d = data.get('data', {})
            total = float(d.get('total_credits', 0))
            used = float(d.get('total_usage', 0))
            return {
                'ok': True,
                'total_credits': total,
                'total_usage': used,
                'remaining': max(0, total - used),
                'remaining_pct': max(0, (total - used) / total * 100) if total > 0 else 0,
            }
    except Exception as exc:
        return {'ok': False, 'error': str(exc)}


def fetch_model_usage(days=7):
    """Read OpenRouter per-model usage from Hermes' session DB.

    This is OpenRouter's own billing data (stored from OpenRouter's models API
    responses), just cached locally by Hermes. No Hermes-internal metrics.
    """
    db = str(Path.home() / '.hermes' / 'state.db')
    cutoff = time.time() - days * 86400
    try:
        conn = sqlite3.connect(db, timeout=5)
        conn.row_factory = sqlite3.Row
        rows = conn.execute('''
            SELECT u.model,
                   SUM(COALESCE(u.input_tokens, 0)) input_tokens,
                   SUM(COALESCE(u.output_tokens, 0)) output_tokens,
                   SUM(COALESCE(u.cache_read_tokens, 0)) cache_read_tokens,
                   SUM(COALESCE(u.reasoning_tokens, 0)) reasoning_tokens,
                   SUM(COALESCE(u.estimated_cost_usd, 0)) cost,
                   SUM(COALESCE(u.api_call_count, 0)) api_calls,
                   COUNT(DISTINCT u.session_id) sessions
            FROM session_model_usage u
            JOIN sessions s ON s.id = u.session_id
            WHERE s.started_at >= ?
              AND (u.billing_provider = 'openrouter'
                   OR u.billing_base_url LIKE '%openrouter%')
            GROUP BY u.model
            ORDER BY cost DESC
        ''', (cutoff,)).fetchall()
        models = []
        total_cost = 0.0
        total_calls = 0
        total_tokens = 0
        for r in rows:
            d = dict(r)
            tok = d['input_tokens'] + d['output_tokens'] + d['cache_read_tokens'] + d['reasoning_tokens']
            models.append({
                'model': d['model'],
                'cost': float(d['cost']),
                'tokens': tok,
                'api_calls': d['api_calls'],
                'sessions': d['sessions'],
            })
            total_cost += float(d['cost'])
            total_calls += d['api_calls']
            total_tokens += tok
        conn.close()
        return {
            'ok': True,
            'days': days,
            'models': models,
            'total_cost': total_cost,
            'total_calls': total_calls,
            'total_tokens': total_tokens,
        }
    except Exception as exc:
        return {'ok': False, 'error': str(exc)}


def main():
    days = 7
    if len(sys.argv) > 1:
        try:
            days = max(1, min(int(sys.argv[1]), 365))
        except ValueError:
            pass

    credits = fetch_credits()
    usage = fetch_model_usage(days)

    if not credits.get('ok'):
        result = {'ok': False, 'error': credits.get('error', 'credits API failed')}
    else:
        result = {
            'ok': True,
            'days': days,
            'total_credits': credits['total_credits'],
            'total_usage': credits['total_usage'],
            'remaining': credits['remaining'],
            'remaining_pct': credits['remaining_pct'],
            'total_cost': usage.get('total_cost', 0),
            'total_calls': usage.get('total_calls', 0),
            'total_tokens': usage.get('total_tokens', 0),
            'models': usage.get('models', []),
        }
    print(json.dumps(result, separators=(',', ':')))


if __name__ == '__main__':
    main()