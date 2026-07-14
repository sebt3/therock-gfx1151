# syntax=docker/dockerfile:1
# therock-gfx1151 - TheRock ROCm SDK built from source for AMD Strix Halo
# (gfx1151 / RDNA 3.5). Vendors bitserv-ai/_gfx115x_'s build pipeline
# (build-vllm.sh / vllm-packages.yaml / patches), capped to total_steps: 4
# so only Phase A (TheRock clone/configure/build/validate) runs - none of
# AOCL/Python/PyTorch/Triton/vLLM/llama.cpp/lemonade.
#
# Two patches (0a/0b in vllm-packages.yaml) are ours, not upstream gfx115x:
# THEROCK_SUPER_PROJECT_FIND_LIBRARY_NAMES/FIND_PATHS force roctx64/
# roctracer/roctx.h to resolve from the super-project even though this
# build has THEROCK_ENABLE_PROFILER=OFF, turning every downstream optional
# ROCTX probe (rocBLAS, hipBLASLt, hipSPARSELt, MIOpen, rocSPARSE, RCCL)
# into a hard FATAL_ERROR instead of the graceful NOTFOUND those projects
# already handle. Fixed at the single source instead of patching each
# downstream CMakeLists.txt.
#
# Output: the staged TheRock install tree (${LOCAL_PREFIX} =
# /opt/src/vllm/local) as this image's root filesystem, for downstream
# images (stack-torch-gfx1151, vllm-gfx1151) to consume via
# `COPY --from=ghcr.io/sebt3/therock-gfx1151:<tag> / /opt/rocm`.

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git \
      clang lld cmake ninja-build gfortran patchelf automake libtool libtool-bin \
      bison flex xxd scons meson \
      libvulkan-dev mesa-vulkan-drivers python3-dev python3-pip python3-venv \
      build-essential lsb-release procps \
      libgl1-mesa-dev libglx-dev libopengl-dev \
    && rm -rf /var/lib/apt/lists/*

# TheRock requires Clang >= 21; Ubuntu 24.04 ships 18.
RUN curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
    && bash /tmp/llvm.sh 21 \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-21 210 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-21 210 \
    && update-alternatives --install /usr/bin/lld lld /usr/bin/lld-21 210 \
    && update-alternatives --set clang /usr/bin/clang-21 \
    && update-alternatives --set clang++ /usr/bin/clang++-21 \
    && update-alternatives --set lld /usr/bin/lld-21 \
    && rm /tmp/llvm.sh

# lit (LLVM Integrated Tester) - required by libhipcxx's test harness at
# TheRock configure time. Not packaged for Debian/Ubuntu.
RUN pip3 install --break-system-packages --no-cache-dir lit

WORKDIR /opt/build
COPY build-vllm.sh common.sh vllm-env.sh vllm-packages.yaml ./
COPY patches ./patches

# Cache mount on the build tree: GitHub-hosted runners cap jobs at 6h, and
# this build can run longer on a 4-core runner than TheRock's own "2-4h on
# 16 cores" estimate suggests. A cache mount survives across separate
# `docker build` invocations (including a failed/timed-out one), so ninja's
# .ninja_log lets a re-triggered run resume instead of restarting cold.
RUN --mount=type=cache,target=/opt/src/vllm,sharing=locked \
    ./build-vllm.sh && \
    mkdir -p /opt/therock-out && cp -a /opt/src/vllm/local/. /opt/therock-out/

FROM scratch AS therock
COPY --from=builder /opt/therock-out /
