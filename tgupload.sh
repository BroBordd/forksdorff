#!/bin/bash
# Upload the built kernel zip to Telegram.
# Usage: ./tgupload.sh <chat_id> <bot_token> [file]
# Without [file], sends the newest kernel_build/*_a14.zip (made by build.sh).
set -e
cd "$(dirname "$(readlink -f "$0")")"

CHAT_ID="$1"
BOT_TOKEN="$2"
FILE="$3"

if [ -z "$CHAT_ID" ] || [ -z "$BOT_TOKEN" ]; then
    echo "Usage: $0 <chat_id> <bot_token> [file]" >&2
    exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }

if [ -z "$FILE" ]; then
    FILE=$(ls -t kernel_build/*_a14.zip 2>/dev/null | head -n1)
fi
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "No kernel zip found. Run ./build.sh first, or pass the file as 3rd arg." >&2
    exit 1
fi

SIZE=$(stat -c %s "$FILE")
MB=$(awk -v s="$SIZE" 'BEGIN{printf "%.1f", s/1048576}')
# Bot API upload limit is 50 MB
if [ "$SIZE" -gt 52428800 ]; then
    echo "$FILE is ${MB} MB; Telegram bots can only upload up to 50 MB." >&2
    exit 1
fi

SHA=$(sha256sum "$FILE" | cut -d' ' -f1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
CAPTION="$(basename "$FILE")
Commit: $COMMIT
Size: ${MB} MB
Date: $(date -u '+%Y-%m-%d %H:%M UTC')
SHA256: $SHA"

echo "[+] Uploading $FILE (${MB} MB) to chat $CHAT_ID ..."

# URL goes through -K - so the bot token never appears in the process list
RESP=$(curl -sS -K - \
    -F "chat_id=$CHAT_ID" \
    -F "document=@$FILE" \
    -F "caption=$CAPTION" <<EOF
url = "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument"
EOF
)

if echo "$RESP" | grep -q '"ok":true'; then
    echo "[+] Sent."
else
    echo "[-] Telegram error: $RESP" >&2
    exit 1
fi
