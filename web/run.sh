#!/usr/bin/env bash
set -euo pipefail

# Resolve paths independently of the caller's working directory.
RECIPE_WEB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$RECIPE_WEB_DIR"
RECIPE_COMMAND="${1:-dev}"
case "$RECIPE_COMMAND" in
  dev|test|build|package|start) ;;
  help|--help|-h)
    printf 'Usage: bash web/run.sh [dev|test|build|package|start]\nDefault: dev. Requires Node.js 22+ and npm; package also requires tar.\n'
    exit 0 ;;
  *) printf 'Unknown command: %s\nUse --help for usage.\n' "$RECIPE_COMMAND" >&2; exit 2 ;;
esac
command -v node >/dev/null || { printf 'Install Node.js 22 or later.\n' >&2; exit 1; }
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22+ required"); process.exit(1); }'

# A deployment archive needs neither npm nor source dependencies.
if [[ "$RECIPE_COMMAND" == start && -f start.mjs ]]; then
  if [[ -f .env ]]; then exec node --env-file=.env start.mjs; fi
  exec node start.mjs
fi
command -v npm >/dev/null || { printf 'Install npm with Node.js.\n' >&2; exit 1; }
if [[ "$RECIPE_COMMAND" == package ]]; then
  command -v tar >/dev/null || { printf 'Install tar to package the website.\n' >&2; exit 1; }
fi
if [[ ! -d node_modules/next ]]; then npm ci --no-audit --no-fund; fi
if [[ ! -f .env.local && ! -f .env ]]; then
  cp .env.example .env.local
  printf 'Created .env.local; fill in your verified website settings when available.\n'
fi
if [[ "$RECIPE_COMMAND" == start && ! -f .next/BUILD_ID ]]; then npm run build; fi
exec npm run "$RECIPE_COMMAND"
