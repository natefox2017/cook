#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$REPO_ROOT/admin"

if [ ! -x node_modules/.bin/vite ]; then
  npm ci
fi

exec npm run dev -- --host 127.0.0.1
