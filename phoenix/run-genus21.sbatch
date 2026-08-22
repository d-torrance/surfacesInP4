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
# Stage 3 -- nonminimal resolution only, skipping the minimalization that
# exhausted 180GB at LengthLimit=>6.  Extracts Frank's Koszul matrix M when the
# length limit reaches 10:
#     sbatch --export=ALL,STAGE=nonmin,LENGTH_LIMIT=6  phoenix/run-genus21.sbatch
#     sbatch --export=ALL,STAGE=nonmin,LENGTH_LIMIT=10 --mem=740G -c 24 -t 3-00:00:00 -p cpu-large phoenix/run-genus21.sbatch
#
# Run the ladder in order and read MaxRSS off each rung (seff <jobid>) before
# committing to the next -- the growth from 6 to 8 says whether 10 needs 500 GB
# or 3 TB. Command-line flags override the #SBATCH defaults below.
#
# Submit from the repository root. Requires Macaulay2 -- see phoenix/README.md.

#SBATCH --job-name=genus21
#SBATCH --account=gts-dtorrance9
#SBATCH --qos=inferno
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8
# M2 parallelizes minimalBetti via TBB by default. cpus-per-task (not
# ntasks) is the right knob for one process with many threads. On the
# big-memory rungs raise this: you are already billed for the node's
# memory share, so unused cores are wasted money.
#SBATCH --mem=180G
#SBATCH --time=1-00:00:00
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
PARALLELIZE_BY_DEGREE="${PARALLELIZE_BY_DEGREE:-false}"
DEGREE_LIMIT="${DEGREE_LIMIT:-3}"
# Tell TBB how many cores it actually has. Left to itself it queries the
# machine and sees all 128, while the cgroup grants only what we asked
# for -- oversubscription, not speedup.
M2_THREADS="${SLURM_CPUS_PER_TASK:-1}"

# Boehm GC tuning. Every run has been pinned near 100% CPU with heavy system
# time and ~1e9 minor page faults regardless of cores, which points at
# allocation and collection rather than compute. A large initial heap and a
# smaller free-space divisor both trade memory for fewer collections.
# GC_INITIAL_HEAP_SIZE is in bytes; keep it well under --mem.
if [ -n "${GC_INITIAL_HEAP_GB:-}" ]; then
    export GC_INITIAL_HEAP_SIZE=$(( GC_INITIAL_HEAP_GB * 1024 * 1024 * 1024 ))
    echo "GC_INITIAL_HEAP_SIZE=$GC_INITIAL_HEAP_SIZE (${GC_INITIAL_HEAP_GB}G)"
fi
if [ -n "${GC_FREE_SPACE_DIVISOR:-}" ]; then
    export GC_FREE_SPACE_DIVISOR
    echo "GC_FREE_SPACE_DIVISOR=$GC_FREE_SPACE_DIVISOR (default 3; lower collects less often)"
fi
export LENGTH_LIMIT PARALLELIZE_BY_DEGREE M2_THREADS DEGREE_LIMIT

# Work in a per-job directory on scratch, but keep the Y0 checkpoint somewhere
# stable so stage 2 can find it across jobs.
WORKDIR="$HOME/scratch/genus21"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

PKG_DIR="$SLURM_SUBMIT_DIR/surface in M2"

case "$STAGE" in
    Y0)    SCRIPT="$SLURM_SUBMIT_DIR/phoenix/make-Y0.m2" ;;
    betti|nonmin)
           if [ "$STAGE" = betti ]; then
               SCRIPT="$SLURM_SUBMIT_DIR/phoenix/betti-ladder.m2"
           else
               SCRIPT="$SLURM_SUBMIT_DIR/phoenix/nonminimal-ladder.m2"
           fi
           # Both load Y0.m2 from the working directory. Seed it from the
           # committed copy if stage 1 has not been run here.
           if [ ! -f "$WORKDIR/Y0.m2" ]; then
               cp "$SLURM_SUBMIT_DIR/phoenix/Y0.m2" "$WORKDIR/Y0.m2"
               echo "seeded Y0.m2 from the committed copy"
           fi ;;
    *)     echo "unknown STAGE=$STAGE (expected Y0, betti, or nonmin)"; exit 2 ;;
esac

echo "host=$(hostname) stage=$STAGE length_limit=$LENGTH_LIMIT start=$(date)"
echo "threads=$M2_THREADS degree_limit=$DEGREE_LIMIT parallelize_by_degree=$PARALLELIZE_BY_DEGREE"
echo "partition=${SLURM_JOB_PARTITION:-?} mem=${SLURM_MEM_PER_NODE:-?}M workdir=$WORKDIR"
M2 --version

# Fed on stdin rather than via --script so the transcript reads like an
# interactive session: input echoed, i1/o1 prompts, errors reported inline
# rather than aborting. stdbuf keeps the log flowing for `tail -f`.
# --no-debug matters here: without it an error drops M2 into the debugger,
# which then reads the REST OF THE SCRIPT as debugger commands. Every
# subsequent line runs in a context where nothing is defined, burying the
# real failure under a cascade of "no method found ... (of class Symbol)".
/usr/bin/time -v stdbuf -oL M2 -q --no-debug -e "path = prepend(\"$PKG_DIR/\", path)" < "$SCRIPT"
m2_status=$?

echo "end=$(date) m2_exit=$m2_status"

if [ "$m2_status" -eq 137 ]; then
    echo "OOM-KILLED (signal 9): raise --mem and resubmit."
    echo "Peak RSS is in the 'Maximum resident set size' line above."
    exit 137
fi

# M2 reading from stdin reports errors and continues, so it exits 0 even when
# things went wrong. Scan the transcript so Slurm's job state means something.
LOG="$SLURM_SUBMIT_DIR/$SLURM_JOB_NAME-$SLURM_JOB_ID.out"
if [ -f "$LOG" ] && grep -qE ':[0-9]+:[0-9]+:\(.*\): error' "$LOG"; then
    echo "TRANSCRIPT CONTAINS ERRORS -- see above"
    exit 1
fi

exit $m2_status
