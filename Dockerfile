ARG AMDGPU_TARGETS="gfx900"
ARG OLLAMA_CUSTOM_CPU_DEFS="-DLLAMA_HIP_UMA=ON"
ARG ROCM_VERSION="6.2.4"
ARG UBUNTU_VERSION="24.04"
ARG CUDA_VERSION="12-6"
ARG CUDA_V12_ARCHITECTURES="60;61;62;70;72;75;80;86;87;89;90;90a"

FROM rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-complete AS builder

COPY --from=madebytimo/base /usr/local/bin /usr/local/bin
WORKDIR /root/builder

ARG CUDA_VERSION
ARG CUDA_V12_ARCHITECTURES
ARG UBUNTU_VERSION
ENV CUDA_REPO_PATH="ubuntu${UBUNTU_VERSION//./}/x86_64"
RUN install-autonomous.sh install Go \
&& curl --silent --location \
"https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub" \
| gpg --yes --dearmor --output /usr/share/keyrings/nvidia-cuda.gpg \
&& echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda.gpg]" \
"https://developer.download.nvidia.com/compute/cuda/repos/$CUDA_REPO_PATH /" \
> /etc/apt/sources.list.d/nvidia-cuda.list \
&& apt update -qq && apt install -y -qq "cuda-toolkit-$CUDA_VERSION" git \
&& rm -rf /var/lib/apt/lists/* \
/usr/share/keyrings/nvidia-cuda.gpg /etc/apt/sources.list.d/nvidia-cuda.list


RUN git clone --branch AMD_APU_GTT_memory --depth 1 --recurse-submodules \
    https://github.com/Maciej-Mogilany/ollama.git ollama-src

# Enable GTT for more apus
RUN sed --in-place 's/\(APUvalidForGTT = \[\]string{\)\(.*}\?\)/\1 "gfx900", "gfx902", "gfx903",\2/' \
    ollama-src/discover/amd_linux.go

ENV LIBRARY_PATH=/opt/amdgpu/lib64:/usr/local/cuda/lib64/stubs
ARG OLLAMA_CUSTOM_CPU_DEFS
RUN --mount=type=cache,target=/root/.ccache --mount=type=cache,target=ollama-src/llama/build \
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

ENV OLLAMA_FLASH_ATTENTION=1
ENV OLLAMA_HOST="http://0.0.0.0:11434"
ENV OLLAMA_KEEP_ALIVE="24h"
ENV OLLAMA_MAX_LOADED_MODELS="10"
ENV OLLAMA_NUM_PARALLEL="1"
ENV STARTUP_PRELOAD=""
ENV STARTUP_PULL=""

ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "ollama", "serve"]

HEALTHCHECK CMD [ "healthcheck.sh" ]
