#!/bin/bash
# Show the full Gate 2 results table for batch_7 (checkmarks/crosses + ATE summary).
# No data is modified — the gate2 script reads batch_7 directly.

B7="/media/neurolab/60a72ba2-3a9d-47d0-88e3-852b0f67f283/sim_results/phase1_eval/batch_7"
RESULTS_BASE="/media/neurolab/60a72ba2-3a9d-47d0-88e3-852b0f67f283/sim_results"
GATE2_SCRIPT="${RESULTS_BASE}/analyze_gate2.py"

python3 "$GATE2_SCRIPT" --batch "$B7"
