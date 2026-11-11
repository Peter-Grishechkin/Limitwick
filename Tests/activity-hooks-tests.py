import json
import shlex
import shutil
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

# Hooks call a copy in Application Support, so they keep working after the app is deleted.
def codex_commands():
    return [h['command'] for groups in json.loads(config.read_text())['hooks'].values() for g in groups for h in g['hooks'] if 'activity-hook.py' in h['command']]
def run_setup(script, action, environment=env):
    return subprocess.run(['/usr/bin/python3', script, action], env=environment, check=True, capture_output=True, text=True).stdout.strip()
codex_stable = Path(env['HOME']) / 'Library/Application Support/Limitwick/useAnimations/activity-hook.py'
config.write_text(json.dumps(original))
codex_stable.unlink()
assert run_setup(setup, 'refresh') == '' and json.loads(config.read_text()) == original and not codex_stable.exists()
missing = dict(env, CODEX_HOME=str(root / 'no-codex'))
assert run_setup(setup, 'refresh', missing) == '' and not (root / 'no-codex').exists()
app = root / 'Deleted.app/Contents/Resources/useAnimations'
app.mkdir(parents=True)
for name in ('activity-setup.py', 'activity-hook.py'):
    (app / name).write_bytes(Path('Resources/useAnimations', name).read_bytes())
run_setup(str(app / 'activity-setup.py'), 'install')
shutil.rmtree(root / 'Deleted.app')
assert codex_stable.exists() and os.access(codex_stable, os.X_OK)
commands = codex_commands()
assert len(commands) == 5 and all(shlex.split(c)[1] == str(codex_stable) for c in commands)
hook = subprocess.run(shlex.split(commands[0]), env=env, input=json.dumps({'hook_event_name': 'Stop', 'session_id': 's', 'turn_id': 't'}), capture_output=True, text=True)
assert hook.returncode == 0 and json.loads(hook.stdout) == {}
before = config.read_bytes()
assert run_setup(setup, 'refresh') == '' and config.read_bytes() == before
old = '/usr/bin/python3 /Old/Limitwick.app/Contents/Resources/useAnimations/activity-hook.py'
config.write_text(json.dumps({'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/usr/bin/true'}, {'type': 'command', 'command': old}]}]}}))
assert run_setup(setup, 'refresh') == 'moved'
commands = codex_commands()
assert len(commands) == 5 and all(shlex.split(c)[1] == str(codex_stable) for c in commands)
assert '/usr/bin/true' in config.read_text()
run_setup(setup, 'remove')
assert json.loads(config.read_text()) == {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': '/usr/bin/true'}]}]}}
assert codex_stable.exists()

listener = Path(env['HOME']) / 'Library/Caches/Limitwick/Activity' / f'listener-{os.getpid()}'
listener.mkdir(parents=True)
input_data = {'hook_event_name': 'PreToolUse', 'session_id': 'session', 'turn_id': 'turn', 'tool_use_id': 'call', 'tool_input': {'command': 'PRIVATE'}}
p = subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/activity-hook.py'], env=env, input=json.dumps(input_data), text=True, capture_output=True, check=True)
assert json.loads(p.stdout) == {}
files = list(listener.glob('event-*'))
assert len(files) == 1
message = json.loads(files[0].read_text())
assert message['event'] == 'PreToolUse' and message['tool'] == 'call'
assert 'PRIVATE' not in files[0].read_text() and 'tool_input' not in message
assert 'name' not in message
files[0].unlink()
# The Sessions window gets the folder name and launching app, never the full path.
input_data = {'hook_event_name': 'UserPromptSubmit', 'session_id': 'session', 'turn_id': 'turn', 'cwd': '/Users/someone/Secret/Project', 'prompt': 'PRIVATE'}
subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/activity-hook.py'], env=dict(env, __CFBundleIdentifier='com.apple.Terminal'), input=json.dumps(input_data), text=True, capture_output=True, check=True)
files = list(listener.glob('event-*'))
text = files[0].read_text(); message = json.loads(text)
assert message['name'] == 'Project' and message['app'] == 'com.apple.Terminal'
assert 'Secret' not in text and 'someone' not in text and 'PRIVATE' not in text
files[0].unlink()
subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/activity-hook.py'], env=dict(env, __CFBundleIdentifier='bad id; rm'), input=json.dumps(dict(input_data, cwd='relative/x')), text=True, capture_output=True, check=True)
message = json.loads(list(listener.glob('event-*'))[0].read_text())
assert 'app' not in message and 'name' not in message
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
stable = Path(env['HOME']) / 'Library/Application Support/Limitwick/useAnimations/claude-activity-hook.py'
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
claude_listener = Path(env['HOME']) / 'Library/Caches/Limitwick/ClaudeActivity' / f'listener-{os.getpid()}'
claude_listener.mkdir(parents=True)
input_data = {'hook_event_name': 'PreToolUse', 'session_id': 'claude-session', 'tool_use_id': 'call', 'tool_input': {'command': 'PRIVATE'}}
p = subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/claude-activity-hook.py'], env=env, input=json.dumps(input_data), text=True, capture_output=True, check=True)
files = list(claude_listener.glob('event-*'))
assert len(files) == 1 and p.stdout == ''
message = json.loads(files[0].read_text())
assert message['event'] == 'PreToolUse' and message['session'] == 'claude-session' and message['tool'] == 'call'
assert 'PRIVATE' not in files[0].read_text() and 'tool_input' not in message
files[0].unlink()

def claude_event(data, **variables):
    """Runs the Claude hook with an extra environment and returns the forwarded message, or None."""
    clean = {k: v for k, v in env.items() if k not in ('CLAUDE_PROJECT_DIR', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_PID', 'CLAUDE_CODE_HOST_SESSION_ID', '__CFBundleIdentifier')}
    subprocess.run(['/usr/bin/python3', 'Resources/useAnimations/claude-activity-hook.py'], env=dict(clean, **variables), input=json.dumps(data), text=True, capture_output=True, check=True)
    found = list(claude_listener.glob('event-*'))
    if not found:
        return None
    text = found[0].read_text(); found[0].unlink()
    return text

# The project root wins over the current folder, which changes when Claude runs cd.
text = claude_event({'hook_event_name': 'UserPromptSubmit', 'session_id': 'claude-session', 'cwd': '/Users/someone/Work/Sub', 'prompt': 'PRIVATE'},
                    CLAUDE_PROJECT_DIR='/Users/someone/Work/Limitwick/', CLAUDE_CODE_ENTRYPOINT='claude-desktop', CLAUDE_PID='1456',
                    CLAUDE_CODE_HOST_SESSION_ID='local_70c6c65e-606c-4a2e-805b-0eebfe0ddc85', __CFBundleIdentifier='com.anthropic.claudefordesktop')
message = json.loads(text)
assert message['name'] == 'Limitwick' and message['entry'] == 'claude-desktop' and message['pid'] == 1456
assert message['host'] == 'local_70c6c65e-606c-4a2e-805b-0eebfe0ddc85' and message['app'] == 'com.anthropic.claudefordesktop'
assert 'someone' not in text and 'Work' not in text and 'PRIVATE' not in text
message = json.loads(claude_event({'hook_event_name': 'Stop', 'session_id': 'claude-session', 'cwd': '/tmp/Sub'}, CLAUDE_PID='x1', CLAUDE_CODE_ENTRYPOINT='Bad Entry'))
assert message['name'] == 'Sub' and 'pid' not in message and 'entry' not in message
assert json.loads(claude_event({'hook_event_name': 'Notification', 'notification_type': 'permission_prompt', 'session_id': 'claude-session', 'message': 'PRIVATE'}))['event'] == 'Permission'
assert json.loads(claude_event({'hook_event_name': 'Notification', 'notification_type': 'idle_prompt', 'session_id': 'claude-session'}))['event'] == 'Idle'
assert claude_event({'hook_event_name': 'Notification', 'notification_type': 'auth_success', 'session_id': 'claude-session'}) is None
claude_config.write_text(json.dumps(claude_original))
subprocess.run(['/usr/bin/python3', setup, 'install'], env=env, check=True, stdout=subprocess.DEVNULL)
assert [g.get('matcher') for g in json.loads(claude_config.read_text())['hooks']['Notification']] == [None]
print('Claude activity hook tests passed')
