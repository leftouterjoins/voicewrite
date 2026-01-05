#!/usr/bin/env python3
"""Update appcast.xml with a new release entry."""

import argparse
import os
from datetime import datetime, timezone

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--signature', required=True)
    parser.add_argument('--size', required=True)
    parser.add_argument('--app-name', default='VoiceWrite')
    args = parser.parse_args()

    pub_date = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')

    new_item = f'''
    <item>
      <title>Version {args.version}</title>
      <link>https://github.com/leftouterjoins/voicewrite/releases/tag/v{args.version}</link>
      <sparkle:version>{args.version}</sparkle:version>
      <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="https://github.com/leftouterjoins/voicewrite/releases/download/v{args.version}/{args.app_name}-{args.version}.zip"
        sparkle:edSignature="{args.signature}"
        length="{args.size}"
        type="application/octet-stream" />
    </item>'''

    with open('docs/appcast.xml', 'r') as f:
        content = f.read()

    content = content.replace('<language>en</language>', f'<language>en</language>{new_item}')

    with open('docs/appcast.xml', 'w') as f:
        f.write(content)

    print(f'Updated appcast.xml for version {args.version}')

if __name__ == '__main__':
    main()
