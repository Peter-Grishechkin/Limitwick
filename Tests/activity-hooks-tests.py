import json
import shlex
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix='limitwick-hooks-test-'))
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

claude_root = root / 'claude'
env['CLAUDE_CONFIG_DIR'] = str(claude_root)
claude_root.mkdir()
claude_config = claude_root / 'settings.json'
claude_original = {'permissions': {'allow': ['Read']}, 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/usr/bin/true'}]}]}}
claude_config.write_text(json.dumps(claude_original))
setup = 'Resources/useAnimations/claude-activity-setup.py'
for action in ('install', 'install', 'remove'):
    subprocess.run(['/usr/bin/python3', setup, action], env=env, check=True, stdout=subprocess.DEVNULL)
assert json.loads(claude_config.read_text()) == claude_original
stable = Path(env['HOME']) / 'Library/Application Support/CodexBar/useAnimations/claude-activity-hook.py'
assert stable.exists() and os.access(stable, os.X_OK)
subprocess.run(['/usr/bin/python3', setup, 'refresh'], env=env, check=True, stdout=subprocess.DEVNULL)
assert json.loads(claude_config.read_text()) == claude_original
old_bundle = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/usr/bin/python3 /Old/CodexBar.app/Contents/Resources/useAnimations/claude-activity-hook.py'}]}]}}
claude_config.write_text(json.dumps(old_bundle))
subprocess.run(['/usr/bin/python3', setup, 'refresh'], env=env, check=True, stdout=subprocess.DEVNULL)
commands = [h['command'] for groups in json.loads(claude_config.read_text())['hooks'].values() for g in groups for h in g['hooks']]
assert commands and all(str(stable) in shlex.split(c)[1] for c in commands)
subprocess.run(['/usr/bin/python3', setup, 'remove'], env=env, check=True, stdout=subprocess.DEVNULL)
assert 'hooks' not in json.loads(claude_config.read_text())
claude_config.write_text(json.dumps(claude_original))
claude_config.write_text('{bad json')
result = subprocess.run(['/usr/bin/python3', setup, 'install'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
assert result.returncode != 0 and claude_config.read_text() == '{bad json'
claude_listener = Path(env['HOME']) / 'Library/Caches/CodexBar/ClaudeActivity' / f'listener-{os.getpid()}'
claude_listener.mkdir(parents=True)
input_data = {'hook_event_name': 'PreToolUse', 'session_id': 'claude-session', 'tool_use_id': 'call', 'tool_input': {'command': 'PRIVATE'}}
p = subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/claude-activity-hook.py'], env=env, input=json.dumps(input_data), text=True, capture_output=True, check=True)
files = list(claude_listener.glob('event-*'))
assert len(files) == 1 and p.stdout == ''
message = json.loads(files[0].read_text())
assert message['event'] == 'PreToolUse' and message['session'] == 'claude-session' and message['tool'] == 'call'
assert 'PRIVATE' not in files[0].read_text() and 'tool_input' not in message
print('Claude activity hook tests passed')
