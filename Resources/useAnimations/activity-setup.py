#!/usr/bin/python3
"""Install/remove Codex Bar lifecycle hooks while preserving other hooks."""
import json
import os
import pathlib
import shlex
import sys
import tempfile

EVENTS = ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'Interrupt')
MARKER = '/useAnimations/activity-hook.py'

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('install', 'remove'):
        raise SystemExit('Usage: activity-setup.py install|remove')
    root = pathlib.Path(os.environ.get('CODEX_HOME', pathlib.Path.home() / '.codex'))
    path = root / 'hooks.json'
    if path.exists():
        with path.open() as f:
            data = json.load(f)
    else:
        data = {}
    if not isinstance(data, dict) or not isinstance(data.get('hooks', {}), dict):
        raise SystemExit('Existing hooks.json has an unexpected format; nothing changed.')
    hooks = data.setdefault('hooks', {})
    helper = str(pathlib.Path(__file__).resolve().with_name('activity-hook.py'))
    for event in EVENTS:
        groups = hooks.get(event, [])
        if not isinstance(groups, list):
            raise SystemExit('Existing hook group has an unexpected format; nothing changed.')
        kept = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get('hooks', []), list):
                raise SystemExit('Existing hook group has an unexpected format; nothing changed.')
            handlers = [h for h in group.get('hooks', []) if not (isinstance(h, dict) and MARKER in str(h.get('command', '')))]
            if handlers:
                kept.append({**group, 'hooks': handlers})
        if sys.argv[1] == 'install':
            kept.append({'hooks': [{'type': 'command', 'command': '/usr/bin/python3 ' + shlex.quote(helper), 'timeout': 3}]})
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.codexbar-hooks-', dir=root)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write('\n')
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print('Codex Bar hooks ' + ('installed; review and trust them in Codex.' if sys.argv[1] == 'install' else 'removed.'))

if __name__ == '__main__':
    main()
