#!/bin/bash
# Run after building the exact release archive and before committing appcast.xml.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 VERSION PATH_TO_RELEASE_ZIP" >&2
    exit 2
fi
VERSION="$1"
ARCHIVE="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a version like 1.5.0" >&2; exit 2; }
[ -f "$ARCHIVE" ] || { echo "Archive not found: $ARCHIVE" >&2; exit 2; }
NAME="CodexBar-$VERSION-macOS-Apple-Silicon.zip"
[ "$(basename "$ARCHIVE")" = "$NAME" ] || { echo "Expected archive name: $NAME" >&2; exit 2; }
# Refuse a mislabeled archive before adding an update to the feed.
PLIST="$(mktemp -t codexbar-release-plist)"
trap 'rm -f "$PLIST"' EXIT
unzip -p "$ARCHIVE" CodexBar.app/Contents/Info.plist > "$PLIST"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST")"
    [ "$VALUE" = "$VERSION" ] || { echo "$KEY in archive is $VALUE, expected $VERSION" >&2; exit 1; }
done
SIGNER="$PWD/build/sparkle-2.10.1/bin/sign_update"
[ -x "$SIGNER" ] || { echo "Run ./build.sh first to install Sparkle tools." >&2; exit 1; }
SIGNATURE="$("$SIGNER" --account codex-bar-updates -p "$ARCHIVE")"
LENGTH="$(stat -f %z "$ARCHIVE")"
python3 - "$VERSION" "$NAME" "$SIGNATURE" "$LENGTH" <<'PY'
import datetime, email.utils, os, sys, tempfile, xml.etree.ElementTree as ET
version, name, signature, length = sys.argv[1:]
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
path = 'appcast.xml'
tree = ET.parse(path)
channel = tree.getroot().find('channel')
if channel is None:
    raise SystemExit('Invalid appcast: channel missing')
if any(item.findtext(f'{{{ns}}}version') == version for item in channel.findall('item')):
    raise SystemExit('Version already exists in appcast')
item = ET.Element('item')
ET.SubElement(item, 'title').text = f'Codex Bar {version}'
ET.SubElement(item, f'{{{ns}}}version').text = version
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = '13.0'
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, 'enclosure', {'url': f'https://github.com/frankydzoro/codex-bar/releases/download/v{version}/{name}', f'{{{ns}}}edSignature': signature, 'length': length, 'type': 'application/octet-stream'})
channel.insert(0, item)
ET.indent(tree, space='  ')
fd, tmp = tempfile.mkstemp(prefix='.appcast-', dir='.')
try:
    with os.fdopen(fd, 'wb') as out:
        tree.write(out, encoding='utf-8', xml_declaration=True)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print(f'Added signed update {version} to {path}. Publish the exact signed archive before the feed.')
PY
