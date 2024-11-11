# Customized Ollama container image

This image contains Ollama with the following properties:

-   ROCm support
-   GTT memory fix from this [PR](https://github.com/ollama/ollama/pull/6282)

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
