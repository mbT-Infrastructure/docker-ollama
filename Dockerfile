FROM madebytimo/builder AS builder
ARG TARGETPLATFORM

ENV TARGET_ARCHITECTURE="${TARGETPLATFORM#*/}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE/arm64/aarch64}"
ENV TARGET_ARCHITECTURE_ALT="${TARGET_ARCHITECTURE_ALT/amd64/x86_64}"

SHELL ["/usr/bin/env", "bash", "-c"]
RUN DISTRIBUTION="$(lsb_release --id --short)" \
    DISTRIBUTION_RELEASE="$(lsb_release --release --short)" \
    && NVIDIA_REPO="${DISTRIBUTION,,}${DISTRIBUTION_RELEASE}/${TARGET_ARCHITECTURE_ALT}" \
    && curl --silent --location \
        "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/3bf863cc.pub" \
        | gpg --yes --dearmor --output /usr/share/keyrings/nvidia-cuda.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda.gpg]" \
        "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO}/ /" \
        > /etc/apt/sources.list.d/nvidia-cuda.list \
    && curl --silent --location "https://repo.radeon.com/rocm/rocm.gpg.key" \
        | gpg --yes --dearmor --output /usr/share/keyrings/amd-rocm.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/amd-rocm.gpg]" \
        "https://repo.radeon.com/rocm/apt/6.3.3 jammy main" \
        > /etc/apt/sources.list.d/amd-rocm.list \
    && echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
        > /etc/apt/preferences.d/rocm-pin-600 \
    && apt update -qq && apt install -y -qq cuda-toolkit rocm
ENV PATH=/opt/rocm/hcc/bin:/opt/rocm/hip/bin:/opt/rocm/bin:/opt/rocm/hcc/bin:$PATH

WORKDIR /root/builder/ollama-src

# Clone Maciej-Mogilany/AMD_APU_GTT_memory and merge ollama/main
RUN git clone --branch AMD_APU_GTT_memory --recurse-submodules \
        https://github.com/Maciej-Mogilany/ollama . \
    && git remote add ollama https://github.com/ollama/ollama \
    && git fetch ollama main \
    && git merge --no-edit ollama/main \
    && git submodule update --recursive


# Set default num_ctx
RUN sed --in-place 's/\(NumCtx: *\)[0-9]*\(,\).*/\18192\2/' \
    api/types.go

# Enable GTT for more apus
RUN sed --in-place \
    's/\(APUvalidForGTT = \[\]string{\)\(.*}\?\)/\1 "gfx900", "gfx902", "gfx903",\2/' \
    discover/amd_linux.go

RUN cmake --preset 'ROCm 6' \
    && cmake --build --parallel --preset 'ROCm 6' \
    && cmake --install build --component HIP --strip \
    && mv dist/lib/ollama/rocm ../ollama/lib

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 12' \
    && cmake --build --parallel --preset 'CUDA 12' \
    && cmake --install build --component CUDA --strip \
&& mv dist/lib/ollama/cuda_v12 ../ollama/lib

ENV GOFLAGS="'-ldflags=-w -s'"
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache \
    mkdir --parents ../ollama/bin ../ollama/lib \
    && go build -buildmode=pie -o ../ollama/bin -trimpath \
    && mv dist/lib/ollama/rocm ../ollama/lib

FROM madebytimo/base

RUN apt update -qq && apt install -y -qq ca-certificates libelf++0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --link /root/builder/ollama/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama/lib/ /usr/local/lib/
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV DELETE_MODELS=false
ENV LD_LIBRARY_PATH="/usr/local/lib"
ENV OLLAMA_FLASH_ATTENTION=1
ENV OLLAMA_HOST="http://0.0.0.0:11434"
ENV OLLAMA_KEEP_ALIVE="4h"
ENV OLLAMA_MAX_LOADED_MODELS="10"
ENV OLLAMA_NUM_PARALLEL="1"
ENV PRELOAD_MODELS=""
ENV PULL_MODELS=""

ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "ollama", "serve"]

HEALTHCHECK CMD [ "healthcheck.sh" ]
