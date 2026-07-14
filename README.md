# therock-gfx1151

TheRock ROCm SDK built from source for AMD Strix Halo / Strix Point (gfx1150/gfx1151, RDNA 3.5), published as an OCI image for downstream builds to consume.

This repo vendors [bitserv-ai/_gfx115x_](https://github.com/bitserv-ai/_gfx115x_)'s build pipeline (`build-vllm.sh` / `vllm-packages.yaml` / `patches/`), capped to `total_steps: 4` so only Phase A (TheRock clone/configure/build/validate) runs — none of AOCL, Python, PyTorch, Triton, vLLM, llama.cpp, or Lemonade.

## Why this exists

Building the entire vLLM inference stack from source in one Dockerfile (TheRock + PyTorch + Triton + vLLM + aiter) needs ~100GB of scratch and multiple hours — too much for a single CI job. Splitting by what actually needs to move together:

- **`therock-gfx1151`** (this repo) — the ROCm SDK itself. Changes rarely.
- **`stack-torch-gfx1151`** — PyTorch + TorchVision + Triton + AOTriton, pinned against a given TheRock tag. These four are ABI-locked to each other.
- **`vllm-gfx1151`** — assembly: vLLM + flash-attention + aiter built against the above. This is the fast-iterating piece.

## Local patches

Two `sed` patches in `vllm-packages.yaml` (`0a`/`0b` on the `therock` package) are not upstream gfx115x — they fix a real bug in TheRock's own build: `THEROCK_SUPER_PROJECT_FIND_LIBRARY_NAMES`/`FIND_PATHS` force `roctx64`/`roctracer/roctx.h` to resolve from the super-project even though this build sets `THEROCK_ENABLE_PROFILER=OFF`, turning every downstream optional ROCTX probe (rocBLAS, hipBLASLt, hipSPARSELt, MIOpen, rocSPARSE, RCCL) into a hard `FATAL_ERROR` instead of the graceful `NOTFOUND` those projects already handle gracefully. Fixed once at the source instead of patching each downstream `CMakeLists.txt`.

## Consuming the image

```dockerfile
COPY --from=ghcr.io/sebt3/therock-gfx1151:latest / /opt/rocm
```

## License

`LICENSE` covers gfx115x's own files (MIT). TheRock and everything it builds carry their own upstream licenses.
