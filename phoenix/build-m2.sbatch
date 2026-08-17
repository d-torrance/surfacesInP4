#!/bin/bash
# Build Macaulay2 from source with spack on PACE Phoenix.
#
# One-time setup before submitting this job:
#   git clone -c feature.manyFiles=true --depth=1 https://github.com/spack/spack.git ~/spack
#   . ~/spack/share/spack/setup-env.sh
#   spack config add "config:install_tree:root:/storage/scratch1/2/dtorrance9/spack/opt"
#   spack compiler find && spack external find --all
#   spack spec -I macaulay2          # sanity check before spending an hour on it
#
# Submit with:  sbatch phoenix/build-m2.sbatch

#SBATCH --job-name=spack-m2
#SBATCH --account=gts-dtorrance9
#SBATCH --qos=inferno
#SBATCH --nodes=1 --ntasks-per-node=16
#SBATCH --mem=48G
#SBATCH --time=8:00:00
#SBATCH --output=%x-%j.out
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=dtorrance9@gatech.edu

set -euo pipefail

# Batch jobs start with a clean environment, so source spack explicitly rather
# than relying on anything loaded in an interactive session.
. ~/spack/share/spack/setup-env.sh

echo "host=$(hostname) start=$(date)"
spack --version
spack install -j16 --fail-fast macaulay2

# Snapshot the build as relocatable tarballs in home (persistent) so a scratch
# purge means a minutes-long restore rather than a hours-long recompile:
#   spack mirror add m2cache ~/m2-buildcache
#   spack install --use-buildcache only macaulay2
spack buildcache push --unsigned ~/m2-buildcache macaulay2

echo "end=$(date)"
