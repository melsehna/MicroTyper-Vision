#!/usr/bin/env bash
#
# Reproducible record: DINOv2 embeddings for the KLEB TN-library training set,
# processed by biofilm-processing run_kleb_062926.sh.
#
# EMBED-ONLY: runs on the already-processed output tree — skips image processing.
# Walks every <experiment>/<plate>/processedImages/index.csv, embeds each well's
# _processed.tif, writes <root>/embeddings/cls_cache.pt. Detached via nohup with a
# timestamped log. Run on a GPU machine.
#
# DATA: 6 plates (one K. pneumoniae mutant each: NV_058/059/064/065/066/070),
# 96 wells each (576 total), SINGLE magnification _02 = 4x (pxToUm 1.744), 25 frames
# (uniform). nFrames is inferred (25); 0 wells skipped. (The script is generic over
# the output root — no plate/well counts are hardcoded.)
# Single mag, so one cache at <root>/embeddings/ — no --mag / per-mag split needed.
# model/imageSize/grid default to dinov2-base / 518 / grid 3.
#
# NOTE: Klebsiella at 4x, 25 frames — its own training set, NOT directly comparable
# to the V. cholerae (10x, 31f) or Sophia (4x/10x, 24f) embedding sets.
#
# SOURCE TREE: the kleb output on the NAS. The share mounts at different paths per
# machine, so the root is auto-detected (writable one wins):
#   processing box : /mnt/phenotyper/Sehna/...
#   GPU box        : /mnt/bridgeslab/phenotyper/Sehna/...
#
# Run AFTER run_kleb_062926.sh finishes (all 6 plates mirrored).
#
# Usage:
#   conda activate <env>
#   bash scripts/extract_kleb_embeddings.sh --well-batch 24 --dry-run   # verify, no GPU
#   bash scripts/extract_kleb_embeddings.sh --well-batch 24             # full run
# For an arbitrary root, call the CLI directly: biofilm-embeddings-run /path/to/root
#
set -euo pipefail
cd "$(dirname "$0")/.."

# --- kleb output root: first existing+writable candidate (per-machine mount) ---
CANDIDATES=(
    "/mnt/bridgeslab/phenotyper/Sehna/kleb-data-062926/klebData"
    "/mnt/phenotyper/Sehna/kleb-data-062926/klebData"
)
ROOT=""
for c in "${CANDIDATES[@]}"; do
    [[ -d "$c" && -w "$c" ]] && { ROOT="$c"; break; }
done
if [[ -z "$ROOT" ]]; then
    echo "ERROR: no writable kleb output root at known mounts:" >&2
    printf '  %s\n' "${CANDIDATES[@]}" >&2
    echo "Has run_kleb_062926.sh finished and mirrored to the NAS?" >&2
    exit 2
fi
echo "Kleb output root: $ROOT"

if command -v biofilm-embeddings-run >/dev/null 2>&1; then
    RUNNER=(biofilm-embeddings-run)
else
    RUNNER=(env PYTHONPATH=src python -m biofilm_embeddings.embeddings.extract_run)
fi

TS=$(date +%Y%m%d_%H%M%S)
LOG="$(pwd)/scripts/extract_kleb_embeddings_${TS}.log"

nohup "${RUNNER[@]}" "$ROOT" "$@" < /dev/null > "$LOG" 2>&1 &
PID=$!
echo
echo "Kleb embedding run launched detached (survives logout)."
echo "  Root:     $ROOT"
echo "  PID:      $PID"
echo "  Log:      $LOG"
echo "  Monitor:  tail -f \"$LOG\""
echo "  Stop:     kill $PID"
echo "  Output:   $ROOT/embeddings/cls_cache.pt"
