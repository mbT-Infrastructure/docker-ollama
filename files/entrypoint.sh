#!/usr/bin/env bash
set -e -o pipefail

prepare-ollama.sh &

exec "$@"
