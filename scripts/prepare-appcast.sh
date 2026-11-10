#!/bin/bash
# Run after publishing the GitHub release and its exact archive, before committing appcast.xml.
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
NAME="Limitwick-$VERSION-macOS-Apple-Silicon.zip"
[ "$(basename "$ARCHIVE")" = "$NAME" ] || { echo "Expected archive name: $NAME" >&2; exit 2; }
# Refuse a mislabeled archive before adding an update to the feed.
PLIST="$(mktemp -t limitwick-release-plist)"
NOTES="$(mktemp -t limitwick-release-notes)"
trap 'rm -f "$PLIST" "$NOTES"' EXIT
unzip -p "$ARCHIVE" Limitwick.app/Contents/Info.plist > "$PLIST"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST")"
    [ "$VALUE" = "$VERSION" ] || { echo "$KEY in archive is $VALUE, expected $VERSION" >&2; exit 1; }
done
# The release must hold this exact archive: same name, size and, when GitHub reports it, SHA-256.
LOCAL_SIZE="$(stat -f %z "$ARCHIVE")"
LOCAL_SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
ASSET="$(gh release view "v$VERSION" --repo frankydzoro/Limitwick --json assets --jq ".assets[] | select(.name == \"$NAME\") | \"\(.size) \(.digest // \"\")\"")"
[ -n "$ASSET" ] || { echo "Release v$VERSION has no asset $NAME; upload the archive first." >&2; exit 1; }
REMOTE_SIZE=""; REMOTE_SHA=""
read -r REMOTE_SIZE REMOTE_SHA <<< "$ASSET"
REMOTE_SHA="${REMOTE_SHA#sha256:}"
[ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] || { echo "Asset size on GitHub is $REMOTE_SIZE, local archive is $LOCAL_SIZE." >&2; exit 1; }
if [ -n "$REMOTE_SHA" ] && [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    echo "Asset SHA-256 on GitHub differs from the local archive." >&2
    exit 1
fi
# The public release is the source of truth for what users see before updating.
gh release view "v$VERSION" --repo frankydzoro/Limitwick --json body --jq .body | python3 scripts/release-changes.py > "$NOTES"
SIGNER="$PWD/build/sparkle-2.10.1/bin/sign_update"
[ -x "$SIGNER" ] || { echo "Run ./build.sh first to install Sparkle tools." >&2; exit 1; }
SIGNATURE="$("$SIGNER" --account limitwick-updates -p "$ARCHIVE")"
LENGTH="$(stat -f %z "$ARCHIVE")"
python3 - "$VERSION" "$NAME" "$SIGNATURE" "$LENGTH" "$NOTES" <<'PY'
import datetime, email.utils, os, sys, tempfile, xml.etree.ElementTree as ET
version, name, signature, length, notes_path = sys.argv[1:]
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
ET.SubElement(item, 'title').text = f'Limitwick {version}'
with open(notes_path, encoding='utf-8') as notes:
    ET.SubElement(item, 'description').text = notes.read().strip()
ET.SubElement(item, f'{{{ns}}}version').text = version
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = '13.0'
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, 'enclosure', {'url': f'https://github.com/frankydzoro/Limitwick/releases/download/v{version}/{name}', f'{{{ns}}}edSignature': signature, 'length': length, 'type': 'application/octet-stream'})
# 2.0 changed the bundle ID, so pre-2.0 apps only see a notice that links to the manual download.
if int(version.split('.')[0]) >= 2:
    ET.SubElement(item, 'link').text = f'https://github.com/frankydzoro/Limitwick/releases/tag/v{version}'
    ET.SubElement(ET.SubElement(item, f'{{{ns}}}informationalUpdate'), f'{{{ns}}}belowVersion').text = '2.0.0'
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
