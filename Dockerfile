FROM docker.io/madebytimo/builder AS builder-src

WORKDIR /root/builder/ollama-src

ADD https://github.com/ollama/ollama.git .

RUN mkdir --parents /root/builder/ollama/{bin,lib}

ENV GIN_MODE=release


FROM docker.io/madebytimo/builder AS builder-cuda
ARG TARGETPLATFORM

ENV TARGET_ARCHITECTURE="${TARGETPLATFORM#*/}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE/arm64/aarch64}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE_ALT/amd64/x86_64}"

RUN DISTRIBUTION="$(lsb_release --id --short)" \
    DISTRIBUTION_RELEASE="$(lsb_release --release --short)" \
    && NVIDIA_REPO="${DISTRIBUTION,,}${DISTRIBUTION_RELEASE}/${TARGET_ARCHITECTURE_ALT}" \
    && curl --silent --location \
    "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/8793F200.pub" \
    | gpg --yes --dearmor --output /usr/share/keyrings/nvidia-cuda.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda.gpg]" \
    "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/ /" \
    > /etc/apt/sources.list.d/nvidia-cuda.list \
    && apt update -qq && apt install -y -qq cuda-toolkit-13 liblapacke-dev libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*
RUN download.sh --output cudnn-###CTR###.deb \
    "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/libcudnn9-cuda-13_9.20.0.48-1_amd64.deb" \
    "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/libcudnn9-static-cuda-13_9.20.0.48-1_amd64.deb" \
    "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/libcudnn9-dev-cuda-13_9.20.0.48-1_amd64.deb" \
    "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/libcudnn9-headers-cuda-13_9.20.0.48-1_amd64.deb" \
    && apt install -y -qq liblapacke-dev libopenblas-dev ./cudnn-*.deb
ENV PATH=/usr/local/cuda/bin:$PATH

WORKDIR /root/builder/ollama-src
COPY --from=builder-src /root/builder/ollama-src/ ./

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 13' \
    && cmake --build --parallel "$(nproc)" --preset 'CUDA 13' \
    && cmake --install build --component CUDA --strip --parallel "$(nproc)"

RUN sed --in-place 's/\("CMAKE_CUDA_FLAGS": "-t\) 4\("\)/\1 1 \2/' CMakePresets.json
RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'MLX CUDA 13' \
    -DBLAS_INCLUDE_DIRS=/usr/include/openblas -DLAPACK_INCLUDE_DIRS=/usr/include/openblas \
    && cmake --build --parallel "$(nproc)" --preset 'MLX CUDA 13' -- \
    && cmake --install build --component MLX --strip --parallel "$(nproc)" \
    && mkdir --parents ../ollama/lib \
    && mv dist/lib/ollama ../ollama/lib


FROM docker.io/madebytimo/builder AS builder-vulkan

RUN mkdir /root/builder/vulkan \
    && download.sh --output - \
    "https://sdk.lunarg.com/sdk/download/latest/linux/vulkan_sdk.tar.xz" \
    | tar --extract --strip-components 1 --xz --directory /root/builder/vulkan \
    && /root/builder/vulkan/vulkansdk --maxjobs shaderc vulkan-loader \
    && cp -r /root/builder/vulkan/x86_64/include/* /usr/local/include/ \
    && cp -r /root/builder/vulkan/x86_64/lib/* /usr/local/lib \
    && cp -r /root/builder/vulkan/x86_64/bin/* /usr/local/bin \
    && rm -rf /root/builder/vulkan

WORKDIR /root/builder/ollama-src
COPY --from=builder-src /root/builder/ollama-src/ ./

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'Vulkan' -DOLLAMA_RUNNER_DIR="vulkan" \
    && cmake --build --parallel "$(nproc)" --preset 'Vulkan' \
    && cmake --install build --component Vulkan --strip --parallel "$(nproc)" \
    && mkdir --parents ../ollama/lib \
    && mv dist/lib/ollama ../ollama/lib


FROM builder-src AS builder

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CPU' \
    && cmake --build --parallel "$(nproc)" --preset 'CPU' \
    && cmake --install build --component CPU --strip --parallel "$(nproc)" \
    && mv dist/lib/ollama ../ollama/lib

ENV GOFLAGS="'-ldflags=-w -s'"
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache \
    go build -buildmode=pie -o ../ollama/bin -trimpath

COPY --from=builder-cuda /root/builder/ollama/lib /root/builder/ollama/lib
COPY --from=builder-vulkan /root/builder/ollama/lib /root/builder/ollama/lib


FROM docker.io/madebytimo/scripts

RUN apt update -qq && apt install -y -qq mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --link /root/builder/ollama/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama/lib/ /usr/local/lib/
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV DELETE_MODELS="false"
ENV LD_LIBRARY_PATH="/usr/local/lib"
ENV NICENESS_ADJUSTMENT="0"
ENV OLLAMA_CONTEXT_LENGTH="32000"
ENV OLLAMA_EDITOR="nano"
ENV OLLAMA_FLASH_ATTENTION="1"
ENV OLLAMA_HOST="http://0.0.0.0:11434"
ENV OLLAMA_KEEP_ALIVE="4h"
ENV OLLAMA_KV_CACHE_TYPE="q8_0"
ENV OLLAMA_MAX_LOADED_MODELS="10"
ENV OLLAMA_NUM_PARALLEL="1"
ENV OLLAMA_ORIGINS="*"
ENV OLLAMA_VULKAN="1"
ENV PRELOAD_MODELS=""
ENV PULL_MODELS=""
ENV SCHED_POLICY="other"

ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "ollama", "serve"]

HEALTHCHECK CMD [ "healthcheck.sh" ]
