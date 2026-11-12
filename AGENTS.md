# AGENTS.md

## Scope
- MoonBit port of Java/ImageJ segmentation algorithms from `D:/src/java/algo/Segmentation` (see `README.md`, `QA_REPORT.md`).
- Byte-for-byte fidelity to the Java reference harness in `ref/harness/` is the main contract (36 files + 75 scalars per image in full runs). Read `ref/harness/README.md` before changing algorithms, I/O, or verification.
- `ref/java/` (original Java sources) and `.mooncakes/` (dependencies) are read-only/reference; do not modify them. Generated artifacts include `pkg.generated.mbti`, `cmd/*/pkg.generated.mbti`, `_build/`, `verify/out/`, `verify/images/`, `verify/edge_images/`, `ref/harness/out/`.

## Project layout
- Root package (`moon.pkg`): library algorithms (`*_*.mbt` / `*.mbt`), Java-compat helpers, image types, PNG/raw I/O. Public API surface is reflected in `pkg.generated.mbti`.
- `cmd/seg/`: CLI executable (`moon.pkg` kind executable). `seg run` emits the full reference output set; per-algorithm subcommands (`otsu`, `multiotsu`, `autothreshold`, `mixture`, `blob`, `watershed`, `densitometry`, `retfm`, `rats`, `siox`, `multithresholder`) emit only that algorithm鈥檚 files + `scalars.txt`.
- `ref/harness/`: minimal ImageJ stubs + `Harness.java` running original/unmodified Java sources; committed goldens in `ref/harness/golden/`.
- `verify/`: test image generators, comparison, target/edge/png/bench scripts, wasm policy, `verify_all.ps1`.

## Build / check / test
- Warnings are a gate: `moon check --deny-warn`
- Unit tests (all backends): `moon test --target all`
- Build CLI (native): `moon build --target native` 鈫?`_build/native/debug/build/cmd/seg/seg.exe` (other targets: `--target js|wasm|wasm-gc`)
- Full verification suite: `powershell -ExecutionPolicy Bypass -File .\verify\verify_all.ps1` (runs 14 gates in order; stops on first failure). Optional PNG/bench gates may be skipped if Python+Pillow/JDK missing unless required.
- Key focused gates: `verify\run_verify.ps1` (happy-path byte-exact + golden freshness), `verify\run_edge_verify.py --backend all --per-algorithm`, `verify\run_targets.ps1` (backend脳algorithm matrix), `verify\refresh_golden.ps1` (intentional golden regeneration only).

## Verification invariants (do not break casually)
- Outputs compared byte-for-byte (`verify/compare.py`); some scalars are raw IEEE-754 bit patterns compared exactly (e.g. `mixture.bits.*`, `multithresholder.txt`). Failure flags (`*.failed`, `siox.success`) are part of contract.
- Reference is the harness in `ref/harness/` (with stub-specific behavior), not stock ImageJ鈥攕ee `ref/harness/README.md` for deviations (e.g. RATS mask dimension swap/transpose behavior, `Multi_Thresholder` 16-bit range/sentinel semantics, non-neutral RGB rendering for channel-mix detection).
- `verify/run_verify.ps1` clears output dirs and checks committed goldens against a fresh Java harness run before comparing MoonBit output; stale/hand-edited goldens must not pass.
- wasm/wasm-gc CLI runs under `moonrun` need sandbox policy (`verify/wasm_policy.json`) for filesystem writes.

## Behavioral quirks to preserve
- Reproduce original plugin behavior even when surprising (documented in README/harness): RATS transpose/quadtree layout and failures, SIOX failure modes/partial confidence matrix semantics, `Multi_Thresholder` `NO_THRESHOLD = -808080.0` (shipped-class behavior), `Blob_Labeler` allocation/edge/OOB read behavior, Java `Math.round`/int cast/wrapping semantics (`java_compat.mbt`).
- CLI input: raw 8-bit grayscale `width*height` bytes or PNG (dimensions from PNG). Paths normalized to forward slashes for cross-backend consistency.

## Config / deps
- Module: `riantr/moonbit_ImageSegmentation` (`moon.mod`), no external MoonBit deps (internal `internal/zlib` and `cmd/seg/fs` provide zlib/fs functionality); preferred target `js` but correctness required on native/js/wasm/wasm-gc.
- Repo-local Kilo config dirs observed: none; no CI workflows in repo.

