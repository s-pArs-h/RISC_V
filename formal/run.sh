#!/usr/bin/env bash
# Run riscv-formal on one of the cores in this repo.
#   formal/run.sh single [make targets]     single-cycle core (riscv_core)
# Work happens in build/formal/ so the riscv-formal submodule stays clean.
# Results: build/formal/cores/rv32i_<core>/checks/*/status
set -euo pipefail
which=${1:-single}; shift || true
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
rf=$here/riscv-formal
[ -f "$rf/checks/genchecks.py" ] || git -C "$root" submodule update --init formal/riscv-formal

work=$root/build/formal
mkdir -p "$work/cores"
ln -sfn "$rf/checks" "$work/checks"
ln -sfn "$rf/insns"  "$work/insns"

core=rv32i_$which
dir=$work/cores/$core
rm -rf "$dir"
mkdir -p "$dir"
cp "$here/checks_$which.cfg" "$dir/checks.cfg"
cp "$here/wrapper.sv" "$root"/rtl/*.sv "$root"/rtl/*.svh "$dir/"

cd "$dir"
python3 ../../checks/genchecks.py
make -C checks -j"$(nproc)" "$@"

total=$(ls checks/*/status | wc -l)
passed=$(grep -l PASS checks/*/status | wc -l)
echo "riscv-formal ($core): $passed/$total checks passed"
grep -L PASS checks/*/status | sed 's|/status||;s|^checks/|  FAILED: |' || true
[ "$passed" -eq "$total" ]
