import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix='codexbar-hooks-test-'))
env = os.environ.copy()
env['CODEX_HOME'] = str(root / 'codex')
env['HOME'] = str(root / 'home')
config = Path(env['CODEX_HOME']) / 'hooks.json'
config.parent.mkdir()
original = {'description': 'kept', 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/usr/bin/true'}]}]}}
config.write_text(json.dumps(original))
setup = 'Resources/useAnimations/activity-setup.py'
for action in ('install', 'install', 'remove'):
    subprocess.run(['/usr/bin/python3', setup, action], env=env, check=True, stdout=subprocess.DEVNULL)
assert json.loads(config.read_text()) == original
config.write_text('{bad json')
result = subprocess.run(['/usr/bin/python3', setup, 'install'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
assert result.returncode != 0 and config.read_text() == '{bad json'

listener = Path(env['HOME']) / 'Library/Caches/CodexBar/Activity' / f'listener-{os.getpid()}'
listener.mkdir(parents=True)
input_data = {'hook_event_name': 'PreToolUse', 'session_id': 'session', 'turn_id': 'turn', 'tool_use_id': 'call', 'tool_input': {'command': 'PRIVATE'}}
p = subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/activity-hook.py'], env=env, input=json.dumps(input_data), text=True, capture_output=True, check=True)
assert json.loads(p.stdout) == {}
files = list(listener.glob('event-*'))
assert len(files) == 1
message = json.loads(files[0].read_text())
assert message['event'] == 'PreToolUse' and message['tool'] == 'call'
assert 'PRIVATE' not in files[0].read_text() and 'tool_input' not in message
print('Activity hook tests passed')
