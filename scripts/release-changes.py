#!/usr/bin/env python3
"""Extract a GitHub release's Changes section as safe HTML for Sparkle."""
import html
import re
import sys


def changes_html(body):
    lines = body.splitlines()
    heading = re.compile(r'^\s{0,3}(#{1,6})\s+Changes\s*#*\s*$', re.IGNORECASE)
    for index, line in enumerate(lines):
        match = heading.match(line)
        if match:
            level = len(match.group(1))
            break
    else:
        raise ValueError('Release notes must contain a Markdown heading named Changes')
    end = re.compile(r'^\s{0,3}(#{1,%d})\s+\S' % level)
    section = []
    for line in lines[index + 1:]:
        if end.match(line):
            break
        section.append(line)
    content = '\n'.join(section).strip()
    if not content:
        raise ValueError('The Changes section is empty')
    return '<h2>Changes</h2><div style="white-space: pre-wrap">' + html.escape(content) + '</div>'


if __name__ == '__main__':
    try:
        print(changes_html(sys.stdin.read()))
    except ValueError as error:
        sys.exit(str(error))
