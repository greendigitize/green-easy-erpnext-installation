#!/usr/bin/env bash
set -euo pipefail

# Green Digitize ERPNext Easy Installation
# This launcher retrieves a pinned revision of the upstream installer so the
# Green Digitize repository can provide a simple, downloadable entry point.

UPSTREAM_URL="https://raw.githubusercontent.com/flexcomng/erpnext_quick_install/c77c1caf6fc7ded885ebbd63222785f0f6365971/erpnext_install.sh"
TMP_FILE="${TMPDIR:-/tmp}/green-digitize-erpnext-install.sh"

printf '\n\033[1;32mGreen Digitize — ERPNext Easy Installation\033[0m\n'
printf '\033[1;34mPreparing the ERPNext installer...\033[0m\n\n'

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$UPSTREAM_URL" -o "$TMP_FILE"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_FILE" "$UPSTREAM_URL"
else
    echo "Error: curl or wget is required to download the installer."
    echo "Install one of them, then run this script again."
    exit 1
fi

chmod +x "$TMP_FILE"

# Execute the downloaded installer in the current terminal.
exec bash "$TMP_FILE"
