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

if [[ -n "$PRELOAD_MODELS" ]]; then
    for MODEL in $PRELOAD_MODELS; do
        if [[ "$STARTUP_PULL" == *"$MODEL"* ]]; then
            pullModel "$MODEL"
            STARTUP_PULL="${STARTUP_PULL/$MODEL/}"
        fi
        loadModel "$MODEL"
    done
fi

if [[ -n "$PULL_MODELS" ]]; then
    for MODEL in $PULL_MODELS; do
        echo "Pulling model \"$MODEL\"."
        curl --fail --silent --data \
            "{\"model\": \"$MODEL\" }" \
            http://localhost:11434/api/pull \
            || echo "Failed to pull model \"$MODEL\""
    done
fi

if [[ -n "$PRELOAD_MODELS" ]]; then
    while true; do
        sleep 600
        LOADED_MODELS="$(curl --fail --silent http://localhost:11434/api/ps \
            | sed 's/,/,\n/g' |sed --silent 's/^.*"name": *"\([^"]*\)".*$/\1/p')"
        if [[ -z "$LOADED_MODELS" ]]; then
            for MODEL in $PRELOAD_MODELS; do
                loadModel "$MODEL"
            done
        fi
    done
fi
