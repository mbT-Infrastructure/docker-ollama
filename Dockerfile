FROM madebytimo/builder AS builder

WORKDIR /root/builder

WORKDIR /root/builder/ollama-src

# RUN git clone --branch AMD_APU_GTT_memory --depth 1 --recurse-submodules \
#     https://github.com/Maciej-Mogilany/ollama .

# Clone Maciej-Mogilany/AMD_APU_GTT_memory and merge ollama/main
RUN git config --global user.email "builder@container" \
    && git clone --branch AMD_APU_GTT_memory --recurse-submodules \
        https://github.com/Maciej-Mogilany/ollama . \
    && git remote add ollama https://github.com/ollama/ollama \
    && git fetch ollama main \
    && git merge --no-edit ollama/main


# Set default num_ctx
RUN sed --in-place 's/\(NumCtx: *\)[0-9]*\(,\).*/\18192\2/' \
    api/types.go

# Enable GTT for more apus
RUN sed --in-place \
    's/\(APUvalidForGTT = \[\]string{\)\(.*}\?\)/\1 "gfx900", "gfx902", "gfx903",\2/' \
    discover/amd_linux.go

ENV LIBRARY_PATH=/opt/amdgpu/lib64:/usr/local/cuda/lib64/stubs
ARG OLLAMA_CUSTOM_CPU_DEFS
RUN --mount=type=cache,target=/root/.cache \
    mkdir --parents ../ollama/bin \
    && go build -buildmode=pie -o ../ollama/bin -trimpath

WORKDIR /root/builder/ollama
COPY --from=ollama/ollama:rocm --link /usr/lib/ollama lib
COPY --from=ollama/ollama --link /usr/lib/ollama lib

FROM madebytimo/base

RUN apt update -qq && apt install -y -qq ca-certificates libelf++0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --link /root/builder/ollama/bin/ /usr/local/bin/
COPY --from=builder --link /root/builder/ollama/lib/ /usr/local/lib/
COPY --link files/entrypoint.sh files/healthcheck.sh files/prepare-ollama.sh /usr/local/bin/

ENV DELETE_MODELS=false
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
