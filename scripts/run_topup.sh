#!/bin/bash
# =============================================================================
# run_topup.sh — Top up a specific scenario to exactly n=20 runs
#
# Usage:
#   ./scripts/run_topup.sh <mask_mode> <dataset> <level> <start_run> <end_run>
#
# Examples:
#   ./scripts/run_topup.sh imu_only   city_day   low   18 20
#   ./scripts/run_topup.sh unmasked   city_day   low   19 20
#   ./scripts/run_topup.sh unmasked   city_day   high  20 20
#   ./scripts/run_topup.sh yolo       city_day   low   20 20
#   ./scripts/run_topup.sh yolo_imu   city_day   low   18 20
#   ./scripts/run_topup.sh imu_only   city_night low   20 20
#   ./scripts/run_topup.sh imu_only   city_night high  20 20
#   ./scripts/run_topup.sh unmasked   city_night low   20 20
#   ./scripts/run_topup.sh yolo       city_night mid   20 20
#   ./scripts/run_topup.sh yolo       city_night high  20 20
#   ./scripts/run_topup.sh yolo_imu   city_night high  20 20
#
# Files are written directly to batch_7/<mask_mode>-<dataset>-<level>/
# with correct run numbering so no manual renaming is needed.
# =============================================================================

MASK_MODE="$1"
DATASET="$2"
LEVEL="$3"
START_RUN="$4"
END_RUN="$5"

if [[ -z "$MASK_MODE" || -z "$DATASET" || -z "$LEVEL" || -z "$START_RUN" || -z "$END_RUN" ]]; then
    echo "Usage: $0 <mask_mode> <dataset> <level> <start_run> <end_run>"
    echo "  mask_mode: unmasked | imu_only | yolo | yolo_imu"
    exit 1
fi

WORKSPACE="/media/neurolab/60a72ba2-3a9d-47d0-88e3-852b0f67f283"
RESULTS_BASE="${WORKSPACE}/sim_results"
OPENVINS_WS="${WORKSPACE}/openvins_ws"
VIODE_DATASET="${WORKSPACE}/Downloads_Ext/VIODE_Dataset"
OTP_SCRIPT="${VIODE_DATASET}/odom_to_path.py"
CONFIG_BASE="${OPENVINS_WS}/install/ov_msckf/share/ov_msckf/config/viode_config"
CONFIG_PLAIN="${CONFIG_BASE}/estimator_config.yaml"
CONFIG_IMU="${CONFIG_BASE}/estimator_config_imu_residual.yaml"
CONFIG_CITY_PLAIN="${CONFIG_BASE}/estimator_config_city.yaml"
CONFIG_CITY_IMU="${CONFIG_BASE}/estimator_config_city_imu_residual.yaml"
MODEL_PATH="${OPENVINS_WS}/models/yolo26s-seg.pt"
VENV_PYTHON="${RESULTS_BASE}/env/bin/python3"

# Output goes directly to batch_7 scenario folder
DEST_FOLDER="${RESULTS_BASE}/phase1_eval/batch_7/${MASK_MODE}-${DATASET}-${LEVEL}"
BAG_PATH="${VIODE_DATASET}/${DATASET}_${LEVEL}"

# ── Parameters (same as batch_7 / batch_10) ──────────────────────────────────
DILATION_KERNEL=5
MAX_MASK_FRACTION=0.80
MIN_DISPARITY=1.2
MIN_FEATURES=8
ORB_NFEATURES=100
CONF_THRESHOLD=0.25
CONF_THRESHOLD_CITY=0.45
FLOW_DYNAMIC_THRESHOLD=2.0
FLOW_MIN_FEATURES=5
USE_FLOW_CLASSIFIER=true
YOLO_DEVICE="${YOLO_DEVICE:-cuda}"
IMU_RESIDUAL_ALPHA=1.5
IMU_RESIDUAL_SIGMA_PX=10.0
IMU_RESIDUAL_INIT_DELAY=5.0

# ── Config selection ─────────────────────────────────────────────────────────
if [[ "$DATASET" == city_* ]]; then
    if [[ "$MASK_MODE" == "yolo_imu" || "$MASK_MODE" == "imu_only" ]]; then
        CONFIG_PATH="$CONFIG_CITY_IMU"
    else
        CONFIG_PATH="$CONFIG_CITY_PLAIN"
    fi
else
    if [[ "$MASK_MODE" == "yolo_imu" || "$MASK_MODE" == "imu_only" ]]; then
        CONFIG_PATH="$CONFIG_IMU"
    else
        CONFIG_PATH="$CONFIG_PLAIN"
    fi
fi

CONF_THRESH="${CONF_THRESHOLD}"
[[ "$DATASET" == city_* ]] && CONF_THRESH="${CONF_THRESHOLD_CITY}"

# ── Kill list ────────────────────────────────────────────────────────────────
KILL_LIST=(
    "ov_msckf" "ov_softgate" "yolo_masker" "odom_to_path.py"
    "static_transform_publisher" "path_recorder" "hybrid_speed_estimator" "masker"
)

cleanup_nodes() {
    echo "  [CLEANUP] Stopping nodes..."
    timeout 5 ros2 topic pub --once /recorder/save std_msgs/msg/Bool "{data: true}" \
        > /dev/null 2>&1 || true
    sleep 2
    for t in "${KILL_LIST[@]}"; do pkill -f "$t" > /dev/null 2>&1 || true; done
    sleep 1
    for t in "${KILL_LIST[@]}"; do pkill -9 -f "$t" > /dev/null 2>&1 || true; done
    ros2 daemon stop  > /dev/null 2>&1 || true
    pkill -9 -f ros2  > /dev/null 2>&1 || true
    pkill -9 -f fastdds > /dev/null 2>&1 || true
    rm -rf ~/.ros/ros2daemon 2>/dev/null || true
    rm -rf /dev/shm/fastrtps_* /dev/shm/rtps_* 2>/dev/null || true
    sleep 2
    ros2 daemon start > /dev/null 2>&1 || true
    timeout 15 bash -c 'until ros2 node list > /dev/null 2>&1; do sleep 0.5; done' || true
    echo "  [CLEANUP] Done."
}

source "${OPENVINS_WS}/install/setup.bash"
trap cleanup_nodes INT TERM
mkdir -p "$DEST_FOLDER"

echo "=========================================================="
echo "  TOP-UP: ${MASK_MODE}-${DATASET}-${LEVEL}"
echo "  Runs : ${START_RUN} → ${END_RUN}"
echo "  Config: $(basename $CONFIG_PATH)"
echo "  YOLO conf: ${CONF_THRESH}"
echo "  Dest: ${DEST_FOLDER}"
echo "=========================================================="

if [[ ! -d "$BAG_PATH" ]]; then
    echo "ERROR: Bag not found: ${BAG_PATH}"
    exit 1
fi

for ((i=START_RUN; i<=END_RUN; i++)); do
    echo ""
    echo "  ── Run ${i} ──────────────────────────────────"

    for t in "${KILL_LIST[@]}"; do pkill -9 -f "$t" > /dev/null 2>&1 || true; done
    sleep 2

    # 1. OpenVINS
    ros2 launch ov_msckf subscribe.launch.py \
        config_path:="$CONFIG_PATH" use_sim_time:=true > /dev/null 2>&1 &
    timeout 15 bash -c \
        'until ros2 node list 2>/dev/null | grep -q "ov_msckf"; do sleep 0.3; done' || true
    sleep 2

    # 2. YOLO masker
    if [[ "$MASK_MODE" == "yolo" || "$MASK_MODE" == "yolo_imu" ]]; then
        ros2 run yolo_masker yolo_masker --ros-args \
            -p model_path:="${MODEL_PATH}" \
            -p device:="${YOLO_DEVICE}" \
            -p confidence_threshold:="${CONF_THRESH}" \
            -p dilation_kernel:="${DILATION_KERNEL}" \
            -p max_mask_fraction:="${MAX_MASK_FRACTION}" \
            -p use_flow_classifier:="${USE_FLOW_CLASSIFIER}" \
            -p flow_dynamic_threshold:="${FLOW_DYNAMIC_THRESHOLD}" \
            -p flow_min_features:="${FLOW_MIN_FEATURES}" \
            > /dev/null 2>&1 &
    else
        ros2 run yolo_masker yolo_masker --ros-args \
            -p model_path:="${MODEL_PATH}" \
            -p device:="${YOLO_DEVICE}" \
            -p force_empty:=true \
            > /dev/null 2>&1 &
    fi
    echo "    -> Waiting for masker..."
    timeout 60 bash -c \
        'until ros2 topic list 2>/dev/null | grep -q "/cam0/masked"; do sleep 0.5; done' \
        || echo "    [WARN] /cam0/masked not seen — continuing"
    sleep 5

    # 3. GT path converter
    python3 "$OTP_SCRIPT" \
        --ros-args -p target_frame:=gt_frame -p scale_factor:=1.0 > /dev/null 2>&1 &

    # 4. Static TF publishers
    ros2 run tf2_ros static_transform_publisher \
        --x 0 --y 0 --z 0 --yaw -1.57 --pitch 0 --roll 3.14159 \
        --frame-id global --child-frame-id gt_frame \
        --ros-args -p use_sim_time:=true > /dev/null 2>&1 &
    ros2 run tf2_ros static_transform_publisher \
        --x 0 --y 0 --z 0 --qx 0.5 --qy 0.5 --qz 0.5 --qw 0.5 \
        --frame-id imu --child-frame-id cam0 \
        --ros-args -p use_sim_time:=false > /dev/null 2>&1 &
    ros2 run tf2_ros static_transform_publisher \
        --x 0 --y 0.05 --z 0 --qx 0.5 --qy 0.5 --qz 0.5 --qw 0.5 \
        --frame-id imu --child-frame-id cam1 \
        --ros-args -p use_sim_time:=false > /dev/null 2>&1 &

    # 5. Recorders — write directly to DEST_FOLDER using run_id=i
    ros2 run ov_softgate path_recorder -- "$i" \
        --ros-args -p output_dir:="${DEST_FOLDER}" > /dev/null 2>&1 &
    ros2 run ov_softgate hybrid_speed_estimator "$i" \
        --ros-args \
        -p mask_source:=yolo \
        -p min_disparity:="${MIN_DISPARITY}" \
        -p min_features:="${MIN_FEATURES}" \
        -p orb_nfeatures:="${ORB_NFEATURES}" \
        -p calib_file:="${OPENVINS_WS}/src/open_vins/config/viode_config/kalibr_imucam_chain.yaml" \
        -p output_dir:="${DEST_FOLDER}" > /dev/null 2>&1 &
    sleep 1

    # 6. Play bag
    echo "    -> Playing bag..."
    ros2 bag play "$BAG_PATH" --clock --read-ahead-queue-size 10000
    echo "    -> Done."
    sleep 1
    cleanup_nodes
    sleep 1

    echo "    -> Files should be in: $(basename $DEST_FOLDER)/vio_path_run_${i}.csv"
    echo "    Run ${i} complete."
done

echo ""
echo "=========================================================="
echo "  Top-up complete. Verify run counts:"
ls "${DEST_FOLDER}"/vio_path_run_*.csv 2>/dev/null | wc -l
echo "  files in $(basename $DEST_FOLDER)/"
echo "=========================================================="
