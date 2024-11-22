#!/usr/bin/env bash
set -e -o pipefail

curl --fail --location http://localhost:11434 || exit 1
