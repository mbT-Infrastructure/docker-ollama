#!/usr/bin/env bash
set -e -o pipefail

function deleteModel(){
    local MODEL="$1"
    echo "Deleting model \"$MODEL\"."
    curl --fail --silent -X DELETE --data "{\"model\": \"$MODEL\" }" --output /dev/null \
        http://localhost:11434/api/delete \
        || echo "Failed to delete model \"$MODEL\""
}

function loadModel() {
    local MODEL="$1"
    local OPTIONS=""
    if [[ "$MODEL" == *"["*"]" ]]; then
        OPTIONS="${MODEL#*"["}"
        OPTIONS="${OPTIONS%"]"*}"
        MODEL="${MODEL%"["*"]"}"
    fi
    echo "Loading model \"$MODEL\"${OPTIONS:+ with options \"${OPTIONS}\"}."
    local REQUEST_BODY="{\"model\": \"$MODEL\", \"keep_alive\": -1, \"options\": { ${OPTIONS} }}"
    curl --fail --silent --data "$REQUEST_BODY" --output /dev/null \
        http://localhost:11434/api/generate \
        || curl --fail --silent --data "$REQUEST_BODY" --output /dev/null \
        http://localhost:11434/api/embed \
        || echo "Failed to preload model \"$MODEL\""
}

function pullModel() {
    local MODEL="$1"
    echo "Pulling model \"$MODEL\""
    curl --fail --silent --data "{\"model\": \"$MODEL\" }" --output /dev/null \
        http://localhost:11434/api/pull \
        || echo "Failed to pull model \"$MODEL\""
}


while ! healthcheck.sh &> /dev/null; do
    echo "Prepare: Waiting for Ollama to start..."
    sleep 5
done

if [[ "${DELETE_MODELS:-}" == "true" ]]; then
    mapfile -t INSTALLED_MODELS < <(curl --fail --silent http://localhost:11434/api/tags \
        | sed 's/,/,\n/g' | sed --silent 's/^.*"name": *"\([^"]*\)".*$/\1/p')
    for MODEL in "${INSTALLED_MODELS[@]}"; do
        if [[ "$PULL_MODELS $LOADED_MODELS" != *"$MODEL"* ]]; then
            deleteModel "$MODEL"
        fi
    done
fi

if [[ -n "$PRELOAD_MODELS" ]]; then
    for MODEL in $PRELOAD_MODELS; do
        if [[ "$PULL_MODELS" == *"$MODEL"* ]]; then
            pullModel "$MODEL"
            PULL_MODELS="${PULL_MODELS/$MODEL/}"
        fi
        loadModel "$MODEL"
    done
fi

if [[ -n "$PULL_MODELS" ]]; then
    for MODEL in $PULL_MODELS; do
        pullModel "$MODEL"
    done
fi

if [[ -n "$PRELOAD_MODELS" ]]; then
    while true; do
        sleep 600
        LOADED_MODELS="$(curl --fail --silent http://localhost:11434/api/ps \
            | sed 's/,/,\n/g' \
            | sed --silent 's/^.*"name": *"\([^"]*\)".*$/\1/p')"
        if [[ -z "$LOADED_MODELS" ]]; then
            for MODEL in $PRELOAD_MODELS; do
                loadModel "$MODEL"
            done
        fi
    done
fi
