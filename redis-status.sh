#!/bin/bash
# Shows what's currently cached in Redis and event counts per sport.
echo "=== Redis SportsCal Status ==="
echo ""

echo "Keys:"
redis-cli keys "debug-*" | sort
echo ""

echo "=== Schedule ==="
redis-cli get "debug-Latest Schedule" 2>/dev/null | python3 -c "
import sys, json
raw = sys.stdin.read()
if raw.strip():
    d = json.loads(raw)
    for sport in ['nba','nhl','mlb','nfl','soccer','golf','tennis','racing']:
        events = d.get(sport, {}).get('events', []) if d.get(sport) else []
        print(f'  {sport}: {len(events)} events')
else:
    print('  (empty)')
" 2>&1

echo ""
echo "=== Live Info ==="
redis-cli get "debug-Latest Full Live Info" 2>/dev/null | python3 -c "
import sys, json
raw = sys.stdin.read()
if raw.strip():
    d = json.loads(raw)
    for sport in ['nba','nhl','mlb','nfl','soccer','golf','tennis','racing']:
        events = d.get(sport, {}).get('events', []) if d.get(sport) else []
        if events:
            live = [g for g in events if g.get('strStatus') == 'in']
            print(f'  {sport}: {len(events)} events ({len(live)} live)')
else:
    print('  (empty)')
" 2>&1

echo ""
echo "=== Soccer Scoreboards ==="
redis-cli get "debug-Latest Soccer Scoreboards" 2>/dev/null | python3 -c "
import sys, json
raw = sys.stdin.read()
if raw.strip():
    d = json.loads(raw)
    i = 0
    while i < len(d) - 1:
        league_id = d[i]
        scoreboard = d[i+1]
        events = scoreboard.get('events', []) if isinstance(scoreboard, dict) else []
        if events:
            live = [e for e in events if e.get('status',{}).get('type',{}).get('state') == 'in']
            label = f' ({len(live)} live)' if live else ''
            print(f'  League {league_id}: {len(events)} events{label}')
        i += 2
else:
    print('  (empty)')
" 2>&1
