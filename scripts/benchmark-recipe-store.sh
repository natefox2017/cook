#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/.tmp/recipe-store-benchmark"
mkdir -p "$OUTPUT"

swiftc -O -parse-as-library \
  "$ROOT"/ios/RecipeCore/Sources/RecipeCore/*.swift \
  "$ROOT/scripts/benchmark-recipe-store.swift" \
  -o "$OUTPUT/benchmark-recipe-store"

"$OUTPUT/benchmark-recipe-store" "$OUTPUT/data"
