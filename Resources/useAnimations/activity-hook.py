#!/usr/bin/python3
"""Send only lifecycle metadata to running Limitwick instances."""
import glob
import json
import os
import pathlib
import sys
import tempfile
import time

try:
    data = json.load(sys.stdin)
    event = data.get('hook_event_name')
    if event not in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'Interrupt'):
        sys.exit(0)
    session, turn = data.get('session_id'), data.get('turn_id')
    if not isinstance(session, str) or not isinstance(turn, str) or len(session) > 100 or len(turn) > 100:
        sys.exit(0)
    tool = data.get('tool_use_id')
    if not isinstance(tool, str) or len(tool) > 200:
        tool = ''
    payload = json.dumps({'event': event, 'session': session, 'turn': turn, 'tool': tool, 'time': time.time(),
                          'home': os.environ.get('CODEX_HOME', os.path.expanduser('~/.codex'))})
    base = os.path.expanduser('~/Library/Caches/Limitwick/Activity')
    for directory in glob.glob(os.path.join(base, 'listener-*')):
        try:
            pid = int(os.path.basename(directory).split('-')[1])
            os.kill(pid, 0)
            fd, name = tempfile.mkstemp(prefix='.event-', dir=directory)
            with os.fdopen(fd, 'w') as output:
                output.write(payload)
            os.replace(name, name.replace('/.event-', '/event-'))
        except (OSError, ValueError, IndexError):
            continue
except (OSError, ValueError, TypeError):
    pass
# Stop requires valid JSON; no output is allowed to affect the session.
print('{}')
