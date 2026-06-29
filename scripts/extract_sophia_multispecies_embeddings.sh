#!/usr/bin/env bash
#
# Reproducible record: DINOv2 embeddings for Sophia's multispecies LB sets
# (6-16 + 6-24), processed by biofilm-processing run_sophia_multispecies_062926.sh.
#
# DUAL MAGNIFICATION: imaged at BOTH 4x (_03) and 10x (_04). Embeddings of different
# objectives are different physical scales and must NOT share a cache, so each mag
# is extracted separately (--mag) into its own per-mag cache:
#   <root>/10X/embeddings/cls_cache.pt   (10x, _04)
#   <root>/4X/embeddings/cls_cache.pt    (4x,  _03)
#
# 24 FRAMES (this set's timecourse) — pinned with --n-frames 24. model/imageSize/grid
# default to dinov2-base / 518 / grid 3. NOTE this is a separate experiment from the
# V. cholerae sets (different organisms, 24 frames), so it is NOT directly comparable
# to the reimaging/cluster 31-frame embeddings.
#
# LABELS / EXCLUSIONS: well -> species + LB% + contamination `excluded` flag are in
# <root>/multispecies_layout.csv. Join on (plateID, wellId); drop excluded wells
# (all of which are media/control wells) downstream.
#
# Run AFTER run_sophia_multispecies_062926.sh finishes (all 6 plates mirrored).
#
# Usage:
#   conda activate <env>
#   bash scripts/extract_sophia_multispecies_embeddings.sh --well-batch 24 --dry-run
#   bash scripts/extract_sophia_multispecies_embeddings.sh --well-batch 24
# Extra flags pass through to both mag passes.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# --- multispecies output root: first existing+writable candidate (per-machine mount) ---
CANDIDATES=(
    "/mnt/bridgeslab/phenotyper/Sehna/multispecies-data-062926"
    "/mnt/phenotyper/Sehna/multispecies-data-062926"
)
ROOT=""
for c in "${CANDIDATES[@]}"; do
    [[ -d "$c" && -w "$c" ]] && { ROOT="$c"; break; }
done
if [[ -z "$ROOT" ]]; then
    echo "ERROR: no writable multispecies output root at known mounts:" >&2
    printf '  %s\n' "${CANDIDATES[@]}" >&2
    echo "Has run_sophia_multispecies_062926.sh finished and mirrored to the NAS?" >&2
    exit 2
fi
echo "Multispecies output root: $ROOT"

RUN_CMD="biofilm-embeddings-run"
command -v biofilm-embeddings-run >/dev/null 2>&1 || \
    RUN_CMD="env PYTHONPATH=src python -m biofilm_embeddings.embeddings.extract_run"

TS=$(date +%Y%m%d_%H%M%S)
LOG="$(pwd)/scripts/extract_sophia_multispecies_embeddings_${TS}.log"

# Two sequential per-mag passes inside one detached nohup. bash -c body takes
# ROOT, RUN, then user passthrough args as positionals (avoids quoting issues;
# $RUN is left unquoted so the module-form fallback word-splits correctly).
nohup bash -c '
    ROOT="$1"; shift
    RUN="$1";  shift
    for mag in _04 _03; do
        case "$mag" in _04) lbl=10X;; _03) lbl=4X;; esac
        echo "===== embedding mag $mag  ->  $ROOT/$lbl/embeddings/cls_cache.pt ====="
        $RUN "$ROOT" --mag "$mag" --n-frames 24 --cache-dir "$ROOT/$lbl" "$@" \
            || echo "  mag $mag FAILED (rc=$?) — continuing to next mag"
    done
' _ "$ROOT" "$RUN_CMD" "$@" < /dev/null > "$LOG" 2>&1 &
PID=$!
echo
echo "Multispecies embedding run launched detached (survives logout)."
echo "  Root:     $ROOT"
echo "  Mags:     _04 (10X) then _03 (4X) — separate caches"
echo "  PID:      $PID"
echo "  Log:      $LOG"
echo "  Monitor:  tail -f \"$LOG\""
echo "  Stop:     kill $PID"
echo "  Output:   $ROOT/10X/embeddings/cls_cache.pt  and  $ROOT/4X/embeddings/cls_cache.pt"
