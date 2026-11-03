#!/usr/bin/python3
"""Install or remove only Codex Bar's Claude Code hooks."""
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile

EVENTS = ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'StopFailure', 'SessionEnd', 'Notification')
MARKER = '/useAnimations/claude-activity-hook.py'

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('install', 'remove'):
        raise SystemExit('Usage: claude-activity-setup.py install|remove')
    root = Path(os.environ.get('CLAUDE_CONFIG_DIR', Path.home() / '.claude'))
    path = root / 'settings.json'
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get('hooks', {}), dict):
        raise SystemExit('Unexpected settings format; nothing changed.')
    hooks = data.setdefault('hooks', {})
    helper = str(Path(__file__).resolve().with_name('claude-activity-hook.py'))
    for event in EVENTS:
        groups = hooks.get(event, [])
        if not isinstance(groups, list):
            raise SystemExit('Unexpected hook group; nothing changed.')
        kept = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get('hooks', []), list):
                raise SystemExit('Unexpected hook group; nothing changed.')
            handlers = [h for h in group.get('hooks', []) if not (isinstance(h, dict) and MARKER in str(h.get('command', '')))]
            if handlers:
                kept.append({**group, 'hooks': handlers})
        if sys.argv[1] == 'install':
            group = {'hooks': [{'type': 'command', 'command': '/usr/bin/python3 ' + shlex.quote(helper), 'timeout': 3}]}
            if event == 'Notification': group['matcher'] = 'idle_prompt'
            kept.append(group)
        if kept: hooks[event] = kept
        else: hooks.pop(event, None)
    if not hooks: data.pop('hooks', None)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.codexbar-hooks-', dir=root)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2); f.write('\n')
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)
    print('Claude Code activity hooks ' + ('installed.' if sys.argv[1] == 'install' else 'removed.'))

if __name__ == '__main__': main()
