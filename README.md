# therock-gfx1151

Custom-patched **math-libs stage** of TheRock's ROCm SDK for AMD Strix Halo
(gfx1151, RDNA 3.5), built against AMD's own official CI artifacts for
everything else, published as a `.tar.gz` GitHub Release asset for
downstream builds to consume.

## Why this exists

A full from-source TheRock build (compiler-runtime + all math/comm/storage
libs) needs ~100GB scratch and hours of compute — too much for a free CI
runner, and mostly wasted effort: our 3 local patches only fix TheRock's
own *build process*, not any library's actual behavior, so a vanilla
official build is functionally identical to ours for everything except the
one stage we actually have a reason to touch.

So this repo builds **only the math-libs stage** (rocBLAS, hipBLASLt,
rocSPARSE, hipSPARSE, rocSOLVER, hipSOLVER, hipBLAS, rocFFT, hipFFT,
rocPRIM, hipCUB, rocThrust, MIOpen...) from source, and gets everything
upstream of it (the compiler, HIP runtime, core libs) from AMD's own
official CI build of the exact `therock-7.14` tag commit
(`ROCm/TheRock` run `29052575219`, public S3 bucket
`therock-ci-artifacts`, anonymous access — verified directly, not assumed).

TheRock's own `buildctl.py bootstrap --stage math-libs` mechanism makes
this work: it drops `.prebuilt` marker files for every artifact math-libs
needs as an inbound dependency, which cmake respects *if bootstrapped
before the first configure* (order matters — doing it after does not
retroactively skip already-materialized build steps). Validated locally on
real hardware before wiring into CI: the whole math-libs stage built in
~25 real minutes with zero compiler-runtime rebuild.

Split across repos by what actually needs to move together:

- **`therock-gfx1151`** (this repo) — the custom-patched math-libs stage.
  Changes rarely — only when a patch actually changes library behavior
  (e.g. a future AITER-adjacent kernel fix), not for build-process fixes.
- **`stack-torch-gfx1151`** — PyTorch + Triton + vLLM + AITER, built
  against AMD's *vanilla* official ROCm 7.14 directly (not this repo —
  deliberately decoupled, since a vanilla build is ABI-identical to ours
  for anything that isn't a behavior-changing patch).
- **`vllm-gfx1151`** — final assembly: stack-torch's wheels + (when a real
  patch exists) this repo's custom math-libs, into the runtime image.

## Local patches

`patches/therock-*.patch` — retriaged this session against the official
`therock-7.14` tag (previously pinned to an arbitrary pre-release commit,
`a512f42`, from before the tag existed):

- `therock-dep-provider-no-registry` — `find_package()` rewrite was
  missing `NO_CMAKE_PACKAGE_REGISTRY`, letting a stale system CMake
  package registry entry override the super-project's own resolution.
- `therock-media-libs-before-profiler` — `add_subdirectory(media-libs)`
  ran after `profiler` in the wrong order. No-op for this repo's config
  (`THEROCK_ENABLE_MEDIA_LIBS=OFF`), kept applied for when a fuller build
  is needed.
- `therock-rocprim-benchmark-deps` — unconditional `find_package(amd_smi)`
  for rocPRIM's benchmarks broke configure even with benchmarks disabled.
  Renamed from `therock-primlibs-benchmark-deps` to match upstream's own
  file rename between `a512f42` and `therock-7.14`. No-op for this repo's
  config (`THEROCK_BUILD_TESTING=OFF`), kept applied for parity.

Dropped: a `roctx64`/`roctracer.h` super-project-resolution fix that lived
inline in the old `vllm-packages.yaml` (not upstream gfx115x — authored
locally for the old pipeline). Verified empirically not needed against
`therock-7.14`: this repo's actual CI build (`THEROCK_ENABLE_PROFILER=OFF`)
completed rocBLAS/hipBLASLt without hitting the `FATAL_ERROR` that fix was
for, so it's presumably been fixed upstream since `a512f42`.

## Consuming the release

```sh
curl -fsSL -o therock-mathlibs.tar.gz \
  https://github.com/sebt3/therock-gfx1151/releases/download/<tag>/therock-gfx1151-mathlibs-<tag>.tar.gz
mkdir -p /opt/rocm-mathlibs && tar xzf therock-mathlibs.tar.gz -C /opt/rocm-mathlibs
```

This is TheRock's `artifacts/` output (per-component `.tar.zst` archives,
`kpack`-split into generic/arch-specific pieces) — not a flat install
tree. Merge into a full ROCm SDK install with TheRock's own
`install_rocm_from_artifacts.py --input-dir`.

## License

`LICENSE` covers this repo's own files (MIT). TheRock and everything it
builds carry their own upstream licenses.
