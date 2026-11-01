#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/check-docs.py
python3 Scripts/check-brand-assets.py
python3 Scripts/check-gifski-notices.py
python3 -m unittest discover -s Scripts -p 'test_ci_scripts.py' -v
python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v
bash Scripts/format-check.sh
bash Scripts/lint.sh
