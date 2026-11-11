#!/usr/bin/python3
"""Send only lifecycle metadata to running Limitwick instances."""
import glob
import json
import os
import pathlib
import re
import sys
import tempfile
import time

# The Sessions window shows an icon per kind of tool; the tool name itself, and any MCP server name, stays here.
# Names as Codex CLI 0.156 sends them to hooks: shell commands arrive as Bash, edits as apply_patch.
CATEGORIES = {'Bash': 'shell', 'apply_patch': 'edit', 'view_image': 'read', 'web_search': 'web',
              'spawn_agent': 'agent', 'update_plan': 'plan'}

def category(name):
    if not isinstance(name, str):
        return 'other'
    return 'mcp' if name.startswith('mcp__') else CATEGORIES.get(name, 'other')

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
    message = {'event': event, 'session': session, 'turn': turn, 'tool': tool, 'time': time.time(),
               'home': os.environ.get('CODEX_HOME', os.path.expanduser('~/.codex'))}
    if event == 'PreToolUse':
        message['category'] = category(data.get('tool_name'))
    # Folder name and launching app for the Sessions window; never a full path.
    cwd = data.get('cwd')
    if isinstance(cwd, str) and cwd.startswith('/'):
        name = os.path.basename(cwd.rstrip('/'))[:60]
        if name and name.isprintable():
            message['name'] = name
    app = os.environ.get('__CFBundleIdentifier', '')
    if re.fullmatch(r'[A-Za-z0-9.-]{1,100}', app):
        message['app'] = app
    payload = json.dumps(message)
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
