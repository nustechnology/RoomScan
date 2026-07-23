#!/bin/sh

set -eu

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit

echo "Git hooks installed. Commits will run .githooks/pre-commit."

