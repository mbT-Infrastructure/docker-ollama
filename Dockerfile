FROM madebytimo/builder AS builder-src

WORKDIR /root/builder/ollama-src

ADD --keep-git-dir https://github.com/ollama/ollama.git .

# Merge Maciej-Mogilany/AMD_APU_GTT_memory
RUN  git fetch --unshallow \
    && git remote add pr https://github.com/Maciej-Mogilany/ollama \
    && git fetch pr AMD_APU_GTT_memory \
    && git merge --no-edit pr/AMD_APU_GTT_memory

# Enable GTT for more apus
RUN sed --in-place \
    's/\(APUvalidForGTT = \[\]string{\)\(.*}\?\)/\1 "gfx900", "gfx902", "gfx903",\2/' \
    discover/amd_linux.go

RUN mkdir --parents /root/builder/ollama/{bin,lib}

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
    && apt update -qq && apt install -y -qq cuda-toolkit
ENV PATH=/usr/local/cuda/bin:$PATH

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 12' \
    && cmake --build --parallel "$(nproc)" --preset 'CUDA 12' \
    && cmake --install build --component CUDA --strip \
    && mv dist/lib/ollama ../ollama/lib


FROM builder-src AS builder-rocm

RUN curl --silent --location "https://repo.radeon.com/rocm/rocm.gpg.key" \
        | gpg --yes --dearmor --output /usr/share/keyrings/amd-rocm.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/amd-rocm.gpg]" \
        "https://repo.radeon.com/rocm/apt/6.3.3 jammy main" \
        > /etc/apt/sources.list.d/amd-rocm.list \
    && echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
        > /etc/apt/preferences.d/rocm-pin-600 \
    && apt update -qq && apt install -y -qq rocm
ENV PATH=/opt/rocm/hcc/bin:/opt/rocm/hip/bin:/opt/rocm/bin:$PATH

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'ROCm 6' \
    && cmake --build --parallel "$(nproc)" --preset 'ROCm 6' \
    && cmake --install build --component HIP --strip \
    && mv dist/lib/ollama ../ollama/lib


FROM builder-src AS builder

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CPU' \
    && cmake --build --parallel "$(nproc)" --preset 'CPU' \
    && cmake --install build --component CPU --strip \
    && mv dist/lib/ollama ../ollama/lib

ENV GOFLAGS="'-ldflags=-w -s'"
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache \
    go build -buildmode=pie -o ../ollama/bin -trimpath

COPY --from=builder-cuda /root/builder/ollama/lib /root/builder/ollama/lib
COPY --from=builder-rocm /root/builder/ollama/lib /root/builder/ollama/lib


FROM madebytimo/scripts

COPY --from=builder --link /root/builder/ollama/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama/lib/ /usr/local/lib/
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV DELETE_MODELS=false
ENV GIN_MODE=release
ENV LD_LIBRARY_PATH="/usr/local/lib"
ENV NICENESS_ADJUSTMENT=0
ENV OLLAMA_CONTEXT_LENGTH="8096"
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
