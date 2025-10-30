FROM madebytimo/builder AS builder-src

WORKDIR /root/builder/ollama-src

ADD https://github.com/ollama/ollama.git .

RUN mkdir --parents /root/builder/ollama/{bin,lib}

ENV GIN_MODE=release


FROM builder-src AS builder-cuda
ARG TARGETPLATFORM

ENV TARGET_ARCHITECTURE="${TARGETPLATFORM#*/}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE/arm64/aarch64}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE_ALT/amd64/x86_64}"

RUN DISTRIBUTION="$(lsb_release --id --short)" \
    DISTRIBUTION_RELEASE="$(lsb_release --release --short)" \
    && NVIDIA_REPO="${DISTRIBUTION,,}${DISTRIBUTION_RELEASE}/${TARGET_ARCHITECTURE_ALT}" \
    && curl --silent --location \
    "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/3bf863cc.pub" \
    | gpg --yes --dearmor --output /usr/share/keyrings/nvidia-cuda.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda.gpg]" \
    "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/ /" \
    > /etc/apt/sources.list.d/nvidia-cuda.list \
    && apt update -qq && apt install -y -qq cuda-toolkit-13
ENV PATH=/usr/local/cuda/bin:$PATH

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 13' -DOLLAMA_RUNNER_DIR="cuda_v13" \
    && cmake --build --parallel "$(nproc)" --preset 'CUDA 13' \
    && cmake --install build --component CUDA --strip --parallel "$(nproc)" \
    && mv dist/lib/ollama ../ollama/lib


FROM builder-src AS builder-vulkan

RUN VULKAN_VERSION="1.4.328.1" \
    && mkdir /root/builder/vulkan \
    && download.sh --output - \
    "https://sdk.lunarg.com/sdk/download/${VULKAN_VERSION}/linux/vulkansdk-linux-x86_64-${VULKAN_VERSION}.tar.xz" \
    | tar --extract --strip-components 1 --xz --directory /root/builder/vulkan \
    && /root/builder/vulkan/vulkansdk --maxjobs shaderc vulkan-loader \
    && ls -la /root/builder/vulkan/ \
    && cp -r /root/builder/vulkan/x86_64/include/* /usr/local/include/ \
    && cp -r /root/builder/vulkan/x86_64/lib/* /usr/local/lib \
    && cp -r /root/builder/vulkan/x86_64/bin/* /usr/local/bin \
    && rm -rf /root/builder/vulkan

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'Vulkan' -DOLLAMA_RUNNER_DIR="vulkan" \
    && cmake --build --parallel "$(nproc)" --preset 'Vulkan' \
    && cmake --install build --component Vulkan --strip --parallel "$(nproc)" \
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


FROM madebytimo/scripts

RUN apt update -qq && apt install -y -qq mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --link /root/builder/ollama/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama/lib/ /usr/local/lib/
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV DELETE_MODELS=false
ENV LD_LIBRARY_PATH="/usr/local/lib"
ENV NICENESS_ADJUSTMENT=0
ENV OLLAMA_CONTEXT_LENGTH="16000"
ENV OLLAMA_FLASH_ATTENTION=1
ENV OLLAMA_HOST="http://0.0.0.0:11434"
ENV OLLAMA_KEEP_ALIVE="4h"
ENV OLLAMA_MAX_LOADED_MODELS="10"
ENV OLLAMA_NUM_PARALLEL="1"
ENV PRELOAD_MODELS=""
ENV PULL_MODELS=""
ENV SCHED_POLICY="other"

ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "ollama", "serve"]

HEALTHCHECK CMD [ "healthcheck.sh" ]
