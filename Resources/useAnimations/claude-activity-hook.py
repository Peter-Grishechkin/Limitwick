#!/usr/bin/python3
"""Forward Claude Code lifecycle metadata without prompts or tool inputs."""
import glob
import json
import os
import sys
import tempfile
import time

try:
    data = json.load(sys.stdin)
    event = data.get('hook_event_name')
    session = data.get('session_id')
    if event == 'Notification' and data.get('notification_type') == 'idle_prompt':
        event = 'Idle'
    if event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'StopFailure', 'SessionEnd', 'Idle') and isinstance(session, str) and 0 < len(session) <= 100:
        tool = data.get('tool_use_id', '')
        if not isinstance(tool, str) or len(tool) > 200:
            tool = ''
        payload = json.dumps({'event': event, 'session': session, 'tool': tool, 'time': time.time()})
        base = os.path.expanduser('~/Library/Caches/CodexBar/ClaudeActivity')
        for directory in glob.glob(os.path.join(base, 'listener-*')):
            try:
                pid = int(os.path.basename(directory).split('-')[1]); os.kill(pid, 0)
                fd, name = tempfile.mkstemp(prefix='.event-', dir=directory)
                with os.fdopen(fd, 'w') as output:
                    output.write(payload)
                os.replace(name, name.replace('/.event-', '/event-'))
            except (OSError, ValueError, IndexError):
                continue
except (OSError, ValueError, TypeError):
    pass
