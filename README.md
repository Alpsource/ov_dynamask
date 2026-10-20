# ov_dynamask

**Asynchronous semantic masking for filter-based stereo-inertial odometry.**

ROS 2 workspace for the masking front end evaluated in *Asynchronous Semantic
Masking in Filter-Based Stereo-Inertial Odometry: A Repeated-Run Study of
Accuracy, Divergence, and Embedded Timing*. Instance segmentation and an
image-motion test run in a separate process from the estimator; completed masks
are cached and republished with later frames, so no admitted stereo pair ever
waits for fresh inference. The estimator is OpenVINS, unmodified in its update
path except for the mask input and the residual-weighting stage used in the
ablation.

---

## What is in here

This repository is the ROS 2 workspace: the two nodes that produce and record
masks, the experiment runners, and the manifest that pulls the OpenVINS fork.
It is the software side only. The recorded runs, the analysis pipeline and the
reference outputs are deposited separately as `ov_dynamask_data_and_code`.
That record recomputes the article's reported scalars, tables and figures from the
recorded runs and checks them against stored reference outputs; its own README
sets out where the recomputation and the published tables differ, including the
table cells carried through from the article and the comparison values read from
the cited literature. It does not regenerate the historical executions or the
raw timing traces.

```
ov_dynamask/
  .repos                     vcs manifest -> Alpsource/open_vins (branch feature/dynamic-masking-viode)
  src/ov_softgate/           ground-truth semantic masker, stereo object tracker, path recorder
  src/yolo_masker/           instance-segmentation masker with ego-motion flow test
  scripts/                   VIODE, KAIST, sweep, timing and live-deployment runners
  tools/                     dataset conversion, offline mask comparison
  analysis/                  batch analysis used during development
  build_jetson.sh            Jetson build
  launch_sensor_system.sh    live sensor bringup (ZED X + Xsens)
  cyclonedds.xml fastdds.xml DDS profiles used on the Jetson
```

The ROS package is named `ov_softgate` because that is the name under which
every recorded run in the data record was produced. The name refers to the
residual-weighting stage, which the article reports as showing no consistent
detectable benefit; it is kept here so the published logs and the published
code agree.

## Nodes

| Node | Package | Role |
|---|---|---|
| `yolo_masker` | `yolo_masker` | instance segmentation plus ego-motion-compensated flow test; publishes per-camera dynamic-object masks |
| `masker` | `ov_softgate` | masks from VIODE annotation colours, used for the annotation-derived batch |
| `hybrid_speed_estimator` | `ov_softgate` | stereo object tracker |
| `path_recorder` | `ov_softgate` | trajectory CSV export for estimate and ground truth |

## Build

Tested on ROS 2 Humble, on an x86-64 workstation and on a Jetson Orin NX
(JetPack OpenCV 4.8).

```bash
mkdir -p ~/ov_dynamask_ws && cd ~/ov_dynamask_ws
git clone https://github.com/Alpsource/ov_dynamask.git .
vcs import src < .repos
source /opt/ros/humble/setup.bash
pip install ultralytics
colcon build --symlink-install
```

On the Jetson use `./build_jetson.sh`, which builds against the JetPack OpenCV
rather than a self-built one.

Segmentation weights are not redistributed. The recorded runs used Ultralytics
`yolo26s-seg`, as a PyTorch checkpoint on the workstation and a TensorRT engine
on the Jetson. Place your own weights in `models/`; the launch file takes the
`.engine` file when present and falls back to the `.pt`.

## Masker parameters

These are the launch-file defaults, not the settings of any particular reported
experiment:

```
confidence_threshold 0.25   dilation_kernel 13   max_mask_fraction 0.80
use_flow_classifier true    force_empty false
```

`force_empty true` makes the node publish empty masks; that is how the unmasked
control arm is run, not a masking setting.

The reported experiments do not share one configuration. Confidence threshold,
dilation kernel, maximum mask fraction, flow threshold and the estimator
configuration each differ between the VIODE and KAIST arms, and within VIODE the
dense-city recordings use their own values. The authoritative record of what
each batch ran is the `params.txt` beside that batch in the data record; the
runner scripts in `scripts/` set the same values at launch time.

## Running

```bash
ros2 launch yolo_masker yolo_masker.launch.py      # masking front end
ros2 launch ov_softgate viode_gt.launch.py         # annotation-derived masks (VIODE)
scripts/run_experiments.sh                         # VIODE repeated-run protocol
scripts/run_kaist_evaluation.sh                    # KAIST Complex Urban replays
scripts/run_nm_sweep.sh                            # residual-weighting parameter sweep
scripts/run_timing_all.sh                          # per-stage latency sweep
scripts/run_zedx_live.sh                           # live ZED X deployment
```

Datasets are not redistributed. VIODE is at https://github.com/kminoda/VIODE
and the KAIST Complex Urban Dataset is published by its authors.

## Results, in one paragraph

Across 12 VIODE recordings with 20 executions per arm, three dense-city
comparisons favour masking after Holm correction, with conditional median
absolute trajectory error changes of -59.5, -36.3 and -26.2 percent. One is
robust to every tested sample restriction, two are sample-sensitive, and no
parking-lot comparison reaches significance. Divergent runs total 10 of 240 in
each arm. On a Jetson Orin NX, under a timing configuration separate from the
accuracy runs, estimator updates took 46.1 to 61.4 ms on average with a 95th
percentile of 81.2 to 138.2 ms, while segmentation ran at a fraction of the
camera rate. Full conditions, statistics and the timing configuration are in
the article.

## Licence

The packages, scripts and tools in this repository are MIT licensed, see
`LICENSE`. They are ROS 2 Python nodes that exchange messages with the
estimator and do not link against it.

The OpenVINS fork pulled by `.repos` is a separate repository and remains under
the GNU GPL v3 of upstream OpenVINS (https://github.com/rpng/open_vins).
