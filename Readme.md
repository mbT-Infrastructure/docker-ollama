# Customized Ollama container image

This image contains Ollama with the following properties and enhancements:

-   Flash attention enabled by default.
-   Default context length of `16000`.
-   Preloading of models via environment variable `PRELOAD_MODELS`
-   Pulling of models at startup via environment variable `PULL_MODELS`
-   Option to delete models not specified for preloading or pulling by setting environment variable
    `DELETE_MODELS=true`
-   Option to change the process priority using environment variables `SCHED_POLICY` and
    `NICENESS_ADJUSTMENT`
-   Cuda support
-   Vulkan support

Usage is the same as in the [official Ollama Docker image].

## Installation

1. Pull from [Docker Hub], download the package from [Releases] or build using `builder/build.sh`

## Development

To run for development execute:

```bash
docker compose --file docker-compose-dev.yaml up --build
```

[official Ollama Docker image]: https://hub.docker.com/r/ollama/ollama
[Docker Hub]: https://hub.docker.com/r/madebytimo/ollama
[Releases]: https://github.com/madebytimo/docker-ollama/releases
