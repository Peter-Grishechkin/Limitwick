#!/usr/bin/python3
"""Install/remove Limitwick lifecycle hooks while preserving other hooks."""
import json
import os
import pathlib
import shlex
import shutil
import sys
import tempfile

EVENTS = ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'Interrupt')
MARKER = '/useAnimations/activity-hook.py'

# A copy outside the app bundle keeps hooks working when the app is moved or deleted.
# The copy stays after removal: open sessions keep calling it, and a missing script exits with 2.
STABLE = pathlib.Path.home() / 'Library/Application Support/Limitwick/useAnimations/activity-hook.py'

def stable_helper():
    target = STABLE
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.activity-hook-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as f, open(pathlib.Path(__file__).resolve().with_name('activity-hook.py'), 'rb') as source:
            shutil.copyfileobj(source, f)
        os.chmod(temp, 0o755)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return str(target)

def ours(handler):
    return isinstance(handler, dict) and MARKER in str(handler.get('command', ''))

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('install', 'remove', 'refresh'):
        raise SystemExit('Usage: activity-setup.py install|remove|refresh')
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
    action = sys.argv[1]
    command = '/usr/bin/python3 ' + shlex.quote(str(STABLE))
    if action == 'refresh':
        # Only updates an existing installation. Codex asks to trust hooks again when a command
        # changes, so hooks.json is rewritten only for older paths, and the caller is told so.
        handlers = [h for groups in hooks.values() if isinstance(groups, list) for g in groups
                    if isinstance(g, dict) and isinstance(g.get('hooks'), list) for h in g['hooks'] if ours(h)]
        if not handlers:
            return
        stable_helper()
        if all(h.get('command') == command for h in handlers):
            return
        action = 'install'
    elif action == 'install':
        stable_helper()
    for event in EVENTS:
        groups = hooks.get(event, [])
        if not isinstance(groups, list):
            raise SystemExit('Existing hook group has an unexpected format; nothing changed.')
        kept = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get('hooks', []), list):
                raise SystemExit('Existing hook group has an unexpected format; nothing changed.')
            handlers = [h for h in group.get('hooks', []) if not ours(h)]
            if handlers:
                kept.append({**group, 'hooks': handlers})
        if action == 'install':
            kept.append({'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]})
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.limitwick-hooks-', dir=root)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write('\n')
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    if sys.argv[1] == 'refresh':
        print('moved')
    else:
        print('Limitwick hooks ' + ('installed; review and trust them in Codex.' if action == 'install' else 'removed.'))

if __name__ == '__main__':
    main()
