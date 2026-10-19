#!/bin/bash
# Remaining top-up runs after first attempt — brings batch_7 to exactly n=20.
# Delete after verifying results.

cd "$(dirname "$0")/.."

WORKSPACE="/media/neurolab/60a72ba2-3a9d-47d0-88e3-852b0f67f283"
RESULTS_BASE="${WORKSPACE}/sim_results"
ANALYZE_SCRIPT="${RESULTS_BASE}/analyze_results_v5.py"
GATE2_SCRIPT="${RESULTS_BASE}/analyze_gate2.py"
B7="${RESULTS_BASE}/phase1_eval/batch_7"

echo "=========================================================="
echo "  BATCH_7 TOP-UP ROUND 2 — remaining missing runs"
echo "  $(date)"
echo "=========================================================="

# imu_only-city_day-low: still at 17, needs 18,19,20
./scripts/run_topup.sh imu_only  city_day   low   18 20

# Everything else needs exactly run 20
./scripts/run_topup.sh unmasked  city_day   low   20 20
./scripts/run_topup.sh unmasked  city_day   high  20 20
./scripts/run_topup.sh yolo      city_day   low   20 20
./scripts/run_topup.sh yolo_imu  city_day   low   20 20
./scripts/run_topup.sh imu_only  city_night low   20 20
./scripts/run_topup.sh imu_only  city_night high  20 20
./scripts/run_topup.sh unmasked  city_night low   20 20
./scripts/run_topup.sh yolo      city_night mid   20 20
./scripts/run_topup.sh yolo      city_night high  20 20
./scripts/run_topup.sh yolo_imu  city_night high  20 20

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================================="
echo "  VERIFICATION"
echo "=========================================================="
ALL_OK=true
for d in "$B7"/*/; do
    count=$(ls "$d"vio_path_run_*.csv 2>/dev/null | wc -l)
    name=$(basename "$d")
    if [[ $count -ne 20 ]]; then
        echo "  ❌ $name: $count"
        ALL_OK=false
    else
        echo "  ✅ $name: 20"
    fi
done

if [[ "$ALL_OK" != "true" ]]; then
    echo ""
    echo "WARNING: still not all at 20. Check above and re-run run_topup.sh for specific scenarios."
    echo "  (VIO init failures are random — just re-run the failing ones)"
else
    echo ""
    echo "All at 20. Running analysis..."

    for d in "$B7"/*/; do
        name=$(basename "$d")
        ln -sfn "$d" "${RESULTS_BASE}/${name}"
    done

    {
        echo "========================================================================"
        echo "  BATCH 7 — 4cond_alpha1.5_sigma10.0_delay5.0  (all n=20, 2026-08-18)"
        echo "  Conditions: unmasked | imu_only | yolo | yolo_imu"
        echo "  imu_residual_alpha=1.5  sigma_px=10.0  init_delay=5.0"
        echo "  yolo_conf (parking_lot/city_night) = 0.25"
        echo "  yolo_conf (city_day)               = 0.45"
        echo "  estimator_config (city_day)        = estimator_config_city.yaml"
        echo "  runs_per_scenario = 20"
        echo "========================================================================"
        echo ""
    } > "$B7/analysis.log"

    for env in parking_lot city_day city_night; do
        echo "  -> Analyzing: ${env}"
        (cd "$RESULTS_BASE" && python3 "$ANALYZE_SCRIPT" --env "$env") \
            >> "$B7/analysis.log" 2>&1
    done

    [[ -f "$GATE2_SCRIPT" ]] && \
        python3 "$GATE2_SCRIPT" --batch "$RESULTS_BASE" >> "$B7/analysis.log" 2>&1

    for d in "$B7"/*/; do
        name=$(basename "$d")
        [[ -L "${RESULTS_BASE}/${name}" ]] && rm "${RESULTS_BASE}/${name}"
    done

    echo ""
    echo "  Analysis log: ${B7}/analysis.log"
    echo "  Delete this script: rm scripts/run_topup_all.sh scripts/run_topup.sh"
fi

echo "  $(date)"
echo "=========================================================="
