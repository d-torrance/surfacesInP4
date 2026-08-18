#!/bin/bash
# Genus-21 K3 minimal Betti numbers, in two stages.
#
# Stage 1 -- build the artinian reduction Y0 and checkpoint it (~1 hour):
#     sbatch --export=ALL,STAGE=Y0 phoenix/run-genus21.sbatch
#
# Stage 2 -- minimalBetti at a given length limit, reusing that checkpoint:
#     sbatch --export=ALL,STAGE=betti,LENGTH_LIMIT=6  --mem=180G  -t 12:00:00 phoenix/run-genus21.sbatch
#     sbatch --export=ALL,STAGE=betti,LENGTH_LIMIT=8  --mem=740G  -t 2-00:00:00 -p cpu-large phoenix/run-genus21.sbatch
#     sbatch --export=ALL,STAGE=betti,LENGTH_LIMIT=10 --mem=1500G -t 7-00:00:00 -p cpu-gnr   phoenix/run-genus21.sbatch
#
# Run the ladder in order and read MaxRSS off each rung (seff <jobid>) before
# committing to the next -- the growth from 6 to 8 says whether 10 needs 500 GB
# or 3 TB. Command-line flags override the #SBATCH defaults below.
#
# Submit from the repository root. Requires Macaulay2 -- see phoenix/README.md.

#SBATCH --job-name=genus21
#SBATCH --account=gts-dtorrance9
#SBATCH --qos=inferno
#SBATCH --nodes=1 --ntasks-per-node=1      # single-threaded: fflas-ffpack needs threads=none
#SBATCH --mem=180G
#SBATCH --time=12:00:00
#SBATCH --output=%x-%j.out
# No --error: with only --output set, Slurm merges stderr into it, so M2's
# elapsedTime output (which goes to stderr) appears next to the computation
# it timed rather than in a separate file.
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=dtorrance9@gatech.edu

set -uo pipefail

. ~/spack/share/spack/setup-env.sh
spack load macaulay2

STAGE="${STAGE:-Y0}"
LENGTH_LIMIT="${LENGTH_LIMIT:-6}"
export LENGTH_LIMIT

# Work in a per-job directory on scratch, but keep the Y0 checkpoint somewhere
# stable so stage 2 can find it across jobs.
WORKDIR="$HOME/scratch/genus21"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

PKG_DIR="$SLURM_SUBMIT_DIR/surface in M2"

case "$STAGE" in
    Y0)    SCRIPT="$SLURM_SUBMIT_DIR/phoenix/make-Y0.m2" ;;
    betti) SCRIPT="$SLURM_SUBMIT_DIR/phoenix/betti-ladder.m2" ;;
    *)     echo "unknown STAGE=$STAGE (expected Y0 or betti)"; exit 2 ;;
esac

echo "host=$(hostname) stage=$STAGE length_limit=$LENGTH_LIMIT start=$(date)"
echo "partition=${SLURM_JOB_PARTITION:-?} mem=${SLURM_MEM_PER_NODE:-?}M workdir=$WORKDIR"
M2 --version

# Fed on stdin rather than via --script so the transcript reads like an
# interactive session: input echoed, i1/o1 prompts, errors reported inline
# rather than aborting. stdbuf keeps the log flowing for `tail -f`.
stdbuf -oL M2 -q -e "path = prepend(\"$PKG_DIR/\", path)" < "$SCRIPT"
m2_status=${PIPESTATUS[0]}

echo "end=$(date) m2_exit=$m2_status"

# M2 reading from stdin reports errors and continues, so it exits 0 even when
# things went wrong. Scan the transcript so Slurm's job state means something.
LOG="$SLURM_SUBMIT_DIR/$SLURM_JOB_NAME-$SLURM_JOB_ID.out"
if [ -f "$LOG" ] && grep -qE ':[0-9]+:[0-9]+:\(.*\): error' "$LOG"; then
    echo "TRANSCRIPT CONTAINS ERRORS -- see above"
    exit 1
fi

exit $m2_status
