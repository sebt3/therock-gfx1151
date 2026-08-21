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

So this repo builds **math-libs proper** (rocBLAS, hipBLASLt, rocSPARSE,
hipSPARSE, rocSOLVER, hipSOLVER, hipBLAS, rocFFT, hipFFT, rocPRIM, hipCUB,
rocThrust) from source, and gets everything upstream of it (the compiler,
HIP runtime, core libs) from AMD's own official CI build of the exact
`therock-7.14` tag commit (`ROCm/TheRock` run `29052575219`, public S3
bucket `therock-ci-artifacts`, anonymous access — verified directly, not
assumed).

**MIOpen excluded** (`THEROCK_ENABLE_MIOPEN=OFF`): TheRock's own
`BUILD_TOPOLOGY.toml` bundles it into the same "math-libs" *stage* as
rocBLAS et al, but its kernel compilation is by far the slowest thing
TheRock builds from source and blew through a 90-minute CI budget on its
own. vLLM's actual need is GEMM (rocBLAS/hipBLASLt), not MIOpen's
conv-focused kernels, so this isn't a real loss for this repo's purpose.

TheRock's own `buildctl.py bootstrap --stage math-libs` mechanism makes
this work: it drops `.prebuilt` marker files for every artifact math-libs
needs as an inbound dependency, which cmake respects *if bootstrapped
before the first configure* (order matters — doing it after does not
retroactively skip already-materialized build steps). Validated locally on
real hardware before wiring into CI: rocBLAS+dist (representative of the
non-MIOpen portion) built in ~25 real minutes with zero compiler-runtime
rebuild.

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
- `therock-sysdeps-drop-versionscript` — the meson-based sysdeps that
  inject a `-Wl,--version-script=...` via the `LDFLAGS` env var
  (libpciaccess, libdrm) hit `ld: duplicate version tag` in CI on a genuine
  from-scratch build. Root cause: meson 1.12.0's own compiler sanity check
  (run once per `setup`, including on `--reconfigure`) applies the flag to
  its generated sanity-check command line *twice* — visible directly in the
  log (`-Wl,--version-script=... -Wl,--version-script=...`). Two mechanism
  changes were tried and both reproduced the identical failure, ruling them
  out as the cause: wiping meson's state dirs (theory: TheRock's double
  cmake-reconfigure per job was accumulating the flag across two separate
  `meson setup` invocations) and passing the flag via meson's
  `-Dc_link_args=` built-in option instead of `LDFLAGS` (theory: the
  duplication was env-var-specific). Neither changed anything, confirming
  the duplication happens inside meson's own sanity-check construction
  regardless of how the flag reaches it. Actual fix: drop the
  `--version-script` application entirely for these two libraries (rpath
  stays, via `-Dc_link_args=`, since `ld` tolerates repeated `-rpath`
  entries — only `--version-script` has the uniqueness requirement that
  makes the duplication fatal). This loses the symbol-versioning that
  protects against a clash if a distro-installed libpciaccess/libdrm is
  *also* loaded into the same process as this bundled copy — not this
  repo's deployment target (a narrow, internally-consumed math-libs
  artifact), so accepting the loss is a reasonable trade for an actually
  buildable stage. amd-mesa has the same LDFLAGS-based pattern but is
  unreachable here (`THEROCK_ENABLE_MEDIA_LIBS=OFF`); util-linux uses a
  different mechanism (patches `.sym` files directly rather than an env
  var) and isn't affected.

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
