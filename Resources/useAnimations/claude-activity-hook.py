#!/usr/bin/python3
"""Forward Claude Code lifecycle metadata without prompts or tool inputs."""
import glob
import json
import os
import re
import sys
import tempfile
import time

NOTIFICATIONS = {'idle_prompt': 'Idle', 'permission_prompt': 'Permission'}
# The Sessions window shows an icon per kind of tool; the tool name itself, and any MCP server name, stays here.
CATEGORIES = {'Edit': 'edit', 'MultiEdit': 'edit', 'Write': 'edit', 'NotebookEdit': 'edit',
              'Bash': 'shell', 'BashOutput': 'shell', 'KillShell': 'shell', 'Read': 'read',
              'Glob': 'search', 'Grep': 'search', 'WebFetch': 'web', 'WebSearch': 'web',
              'Task': 'agent', 'Agent': 'agent', 'TodoWrite': 'plan'}

def category(name):
    if not isinstance(name, str):
        return 'other'
    return 'mcp' if name.startswith('mcp__') else CATEGORIES.get(name, 'other')

def session_details(data):
    """Project folder name and launch details for the Sessions window; never a full path."""
    details = {}
    project = os.environ.get('CLAUDE_PROJECT_DIR') or data.get('cwd')
    if isinstance(project, str) and project.startswith('/'):
        name = os.path.basename(project.rstrip('/'))[:60]
        if name and name.isprintable():
            details['name'] = name
    for key, variable, pattern in (('app', '__CFBundleIdentifier', r'[A-Za-z0-9.-]{1,100}'),
                                   ('entry', 'CLAUDE_CODE_ENTRYPOINT', r'[a-z0-9-]{1,40}'),
                                   ('host', 'CLAUDE_CODE_HOST_SESSION_ID', r'[A-Za-z0-9_-]{1,80}')):
        value = os.environ.get(variable, '')
        if re.fullmatch(pattern, value):
            details[key] = value
    pid = os.environ.get('CLAUDE_PID', '')
    if re.fullmatch(r'[0-9]{1,10}', pid) and 0 < int(pid) < 2 ** 31:
        details['pid'] = int(pid)
    return details

try:
    data = json.load(sys.stdin)
    event = data.get('hook_event_name')
    session = data.get('session_id')
    if event == 'Notification':
        event = NOTIFICATIONS.get(data.get('notification_type'), event)
    if event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'StopFailure', 'SessionEnd', 'Idle', 'Permission') and isinstance(session, str) and 0 < len(session) <= 100:
        tool = data.get('tool_use_id', '')
        if not isinstance(tool, str) or len(tool) > 200:
            tool = ''
        message = {'event': event, 'session': session, 'tool': tool, 'time': time.time(), **session_details(data)}
        if event == 'PreToolUse':
            message['category'] = category(data.get('tool_name'))
        payload = json.dumps(message)
        base = os.path.expanduser('~/Library/Caches/Limitwick/ClaudeActivity')
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
