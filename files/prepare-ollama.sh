#!/usr/bin/env bash
set -e -o pipefail

while ! healthcheck.sh &> /dev/null; do
    echo "Prepare: Waiting for Ollama to start..."
    sleep 5
done

if [[ -n "$STARTUP_PRELOAD" ]]; then
    for MODEL in $STARTUP_PRELOAD; do
        echo "Preloading model \"$MODEL\""
        ollama run "$MODEL" "" --keepalive -1h \
            || echo "Failed to preload model \"$MODEL\""
    done
fi

if [[ -n "$STARTUP_PULL" ]]; then
    for MODEL in $STARTUP_PULL; do
        echo "Pulling model \"$MODEL\""
        ollama pull "$MODEL" \
            || echo "Failed to pull model \"$MODEL\""
    done
fi
