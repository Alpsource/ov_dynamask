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

> **Paper:** under review. Archival DOI: `XX.XXXX/XXXXXX` (to be filled on acceptance).
> **Data and code record:** DOI `XX.XXXX/XXXXXX`, released separately from this repository.

---

## What is in here

This repository is the ROS 2 workspace: the two nodes that produce and record
masks, the experiment runners, and the manifest that pulls the OpenVINS fork.
It is the software side only. The recorded runs, the analysis pipeline and the
reference outputs that regenerate every number, table and figure in the article
live in the separate archived data record named above.

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

## Masker configuration used for the recorded runs

```
conf 0.25   dilation 13 px   max mask fraction 0.80
CLAHE on, clip 2.0           flow test on, threshold 2.0 px
force_empty true
```

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
each arm. On a Jetson Orin NX, estimator updates took 46.1 to 61.4 ms on
average with a 95th percentile of 81.2 to 138.2 ms, while segmentation ran at a
fraction of the camera rate. Full conditions, statistics and the timing
configuration are in the article.

## Licence

The packages, scripts and tools in this repository are MIT licensed, see
`LICENSE`. They are ROS 2 Python nodes that exchange messages with the
estimator and do not link against it.

The OpenVINS fork pulled by `.repos` is a separate repository and remains under
the GNU GPL v3 of upstream OpenVINS (https://github.com/rpng/open_vins).

## Citing

If you use this software, please cite the article and the data record:

```bibtex
@article{demirel_dynamask,
  author  = {Demirel, Alp and Uyan{\i}k, {\.I}smail},
  title   = {Asynchronous Semantic Masking in Filter-Based Stereo-Inertial
             Odometry: A Repeated-Run Study of Accuracy, Divergence, and
             Embedded Timing},
  year    = {2026},
  note    = {Under review}
}
```

Please also cite OpenVINS, and the VIODE and KAIST Complex Urban datasets if
you reproduce the evaluations.
