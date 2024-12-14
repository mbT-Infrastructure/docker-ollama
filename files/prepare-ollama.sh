#!/usr/bin/env bash
set -e -o pipefail

function pullModel() {
    MODEL=$1
    echo "Pulling model \"$MODEL\""
    curl --fail --silent --data \
        "{\"model\": \"$MODEL\" }" \
        http://localhost:11434/api/pull \
        || echo "Failed to pull model \"$MODEL\""
}

function loadModel() {
    MODEL=$1
    OPTIONS=""
    if [[ "$MODEL" == *"["*"]" ]]; then
        OPTIONS="${MODEL#*"["}"
        OPTIONS="${OPTIONS%"]"*}"
        MODEL="${MODEL%"["*"]"}"
    fi
    echo "Loading model \"$MODEL\"${OPTIONS:+ with options \"${OPTIONS}\"}."
    curl --fail --silent --data \
        "{\"model\": \"$MODEL\", \"keep_alive\": -1, \"options\": { ${OPTIONS} }}" \
        http://localhost:11434/api/generate \
        || echo "Failed to preload model \"$MODEL\""
}

while ! healthcheck.sh &> /dev/null; do
    echo "Prepare: Waiting for Ollama to start..."
    sleep 5
done

if [[ -n "$STARTUP_PRELOAD" ]]; then
    for MODEL in $STARTUP_PRELOAD; do
        if [[ "$STARTUP_PULL" == *"$MODEL"* ]]; then
            pullModel "$MODEL"
            STARTUP_PULL="${STARTUP_PULL/$MODEL/}"
        fi
        loadModel "$MODEL"
    done
fi

if [[ -n "$STARTUP_PULL" ]]; then
    for MODEL in $STARTUP_PULL; do
        echo "Pulling model \"$MODEL\"."
        curl --fail --silent --data \
            "{\"model\": \"$MODEL\" }" \
            http://localhost:11434/api/pull \
            || echo "Failed to pull model \"$MODEL\""
    done
fi
