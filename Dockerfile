ARG ROCM_VERSION="6.2.4"
ARG AMDGPU_TARGETS="gfx900"
ARG OLLAMA_CUSTOM_CPU_DEFS="-DLLAMA_HIP_UMA=ON"
ARG UBUNTU_VERSION="24.04"

FROM rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-complete AS builder

COPY --from=madebytimo/base /usr/local/bin /usr/local/bin
WORKDIR /root/builder

ENV LIBRARY_PATH=/opt/amdgpu/lib64

RUN install-autonomous.sh install Go \
    && apt update -qq && apt install -y -qq git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch AMD_APU_GTT_memory --depth 1 --recurse-submodules \
    https://github.com/Maciej-Mogilany/ollama.git ollama-src

# ARG AMDGPU_TARGETS
# ARG OLLAMA_CUSTOM_CPU_DEFS

# Enable GTT for more apus
RUN sed --in-place 's/\(APUvalidForGTT = \[\]string{\)\(.*}\?\)/\1 "gfx900", "gfx902", "gfx903",\2/' \
    ollama-src/discover/amd_linux.go

RUN --mount=type=cache,target=/root/.ccache \
    make --directory ollama-src/llama --jobs "$(nproc)"

RUN --mount=type=cache,target=/root/.ccache \
    go build -C ollama-src -trimpath -o dist/linux-amd64/bin/ollama .

# RUN ls -l /root/builder/ollama-src/dist/linux-amd64-rocm/lib/ollama && exit 1
RUN rm /root/builder/ollama-src/dist/linux-amd64-rocm/lib/ollama/libelf.so.1 \
    /root/builder/ollama-src/dist/linux-amd64-rocm/lib/ollama/libhipblas.so

# FROM ubuntu:${UBUNTU_VERSION}
FROM rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}

RUN apt update -qq && apt install -y -qq ca-certificates libelf++0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --link /root/builder/ollama-src/dist/linux-*/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama-src/dist/linux-*/lib/ /usr/local/lib/
# COPY --from=builder --link /opt/rocm/lib /usr/local/lib/ollama
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV OLLAMA_HOST="http://0.0.0.0:11434"
ENV OLLAMA_KEEP_ALIVE="24h"
ENV OLLAMA_MAX_LOADED_MODELS="10"
ENV OLLAMA_NUM_PARALLEL="10"
ENV STARTUP_PRELOAD=""
ENV STARTUP_PULL=""

ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "ollama", "serve"]

HEALTHCHECK CMD [ "healthcheck.sh" ]
