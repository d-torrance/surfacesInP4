# Installing Macaulay2 on GT PACE Phoenix

Notes on building Macaulay2 with spack on Georgia Tech's Phoenix cluster,
written while doing it for the first time in August 2026.

The Slurm and spack sections are general. The gotchas below are specific to
Macaulay2's dependency tree meeting Phoenix's system libraries — texinfo
tripping over an incomplete system perl, fflas-ffpack over a threading-variant
mismatch in the system OpenBLAS, M2 itself over missing Python headers — though
the underlying lesson about spack externals generalizes.

Substitute your own GT username, charge account, and paths throughout.
`phoenix/build-m2.sbatch` in this repo has `--account` and `--mail-user` set to
the author's; edit those before submitting.

## Account and paths

```bash
ssh <gtusername>@login-phoenix.pace.gatech.edu      # GT VPN required, even on campus
pace-quota                                          # charge account + storage usage
```

`pace-quota` is where you find your charge account name — it looks like
`gts-<PI-username>` — and your storage allocations. Expect roughly:

| Storage | Size | Persistence | Good for |
|---|---|---|---|
| Home (`~`) | ~20 GB | permanent | spack clone and install tree, `~/.spack` config |
| Scratch (`~/scratch`) | 15 TB | **60-day purge** | build stages, job working dirs, large intermediates |
| Project (`/storage/coda1/p-<code>/0`) | 1 TB for a PI | permanent | data you care about |

`pace-quota` reports individual and research-group quotas in **separate
sections** — project storage is under the group one, so it's easy to miss and
conclude you don't have any.

`~/scratch` is a symlink; `cd ~/scratch && pwd -P` gives the physical path,
which is what spack config files want.

PIs get a free-tier charge account that refills monthly (~$68, worth ~10,000
CPU-hours on a 192 GB node — about $0.007/CPU-hour). You are billed on
**requested** resources, not used, so don't pad requests.

## Slurm, minimally

In short: **`salloc`** is "give me a shell on a compute node," **`sbatch`** is
"run this script on a compute node."

Both go through the queue — `salloc` isn't instant, it just blocks your
terminal while it waits, which usually takes seconds. The real difference is
ownership. An `salloc` allocation belongs to your terminal, so it dies with a
closed laptop, a dropped VPN, or a broken ssh connection. An `sbatch` job
belongs to Slurm, which runs it whether or not you're connected and mails you
when it finishes.

So: `salloc` when you don't yet know what commands you want to type (debugging,
poking at a failed build); `sbatch` when you do.

They are alternatives, not a sequence. **Do not `salloc` before `sbatch`** —
that reserves a node you then sit idle on while the batch job runs somewhere
else, billing you for both. Submit from the login node; never compute on it.

```bash
sbatch phoenix/build-m2.sbatch          # from the login node, always

salloc -A gts-<PI> -q inferno -N1 --ntasks-per-node=8 --mem=32G -t 1:00:00

squeue -u $USER                         # PD = pending, R = running
scancel <jobid>
sacct -u $USER --starttime today --format=JobID,JobName%20,State,Elapsed,NodeList%30,ExitCode -X
seff <jobid>                            # after completion: actual vs requested
```

`sacct` truncates columns with a `+`; widen them with a `%N` suffix as above.
`-X` hides the `.batch`/`.extern` step rows.

Job script flags: `-A`/`--account` (required), `--qos=inferno` (standard;
`embers` is free but preemptible, so unsuitable for long uncheckpointed runs),
`--nodes`, `--time` as a hard kill. Unused walltime isn't billed, but large
requests hurt queue priority.

Run interactive sessions inside `tmux` on the login node so a dropped
connection doesn't take the allocation with it.

### Watching a running build

```bash
tail -f spack-m2-<jobid>.out                        # spack's package-by-package progress
sstat -j <jobid>.batch --format=JobID,MaxRSS,AveCPU # live resource use (note the .batch)
tail -f ~/scratch/spack-stage/spack-stage-*/spack-build-out.txt   # raw configure/make output
```

Output to a file is block-buffered, so the log arrives in bursts. A quiet
stretch usually means a long package (boost, normaliz, openblas), not a hang —
`AveCPU` climbing confirms it's alive. You can also `ssh` to a node where you
have a running job and watch `top`.

**Set the build stage somewhere persistent before you need it.** Spack defaults
it to node-local `/tmp/$USER`, which is wiped when the job ends, taking a failed
build's log with it. Scratch is the right home for it — transient files, and it
stays out of the home quota:

```bash
spack config add "config:build_stage:[$(cd ~/scratch && pwd -P)/spack-stage]"
```

## Why a personal spack clone

PACE provides a `spack` module, but it's unusable here:

- version `0.24.0.dev0`, which predates the spack v1.0 package-repo split, so
  it has no `macaulay2` recipe at all
- `spack config get upstreams` returns `{}` — no shared prebuilt package tree,
  so there is nothing to inherit by chaining to it

So: clone `develop` yourself. Nothing is lost by ignoring PACE's instance.

## Setup

```bash
git clone -c feature.manyFiles=true --depth=1 https://github.com/spack/spack.git ~/spack
. ~/spack/share/spack/setup-env.sh          # 1.3.0.dev0 at time of writing
spack compiler find
spack external find --all
spack spec -I macaulay2 | grep '\[e\]'      # audit these before building
spack spec -I macaulay2                     # dry run, builds nothing
```

`spack external find --all` is worth running — it found ~35 usable system
packages here, against 3 that were broken. But audit the result before you
submit; see "don't trust the system externals" below for which kinds to
distrust.

`feature.manyFiles=true` is a git performance setting for repos with many small
files — it matters on a network filesystem.

The install tree defaults to `~/spack/opt/spack`, and home is the right place
for it: permanent, and not subject to the scratch purge. The finished Macaulay2
tree measured **8.2 GB** against a ~20 GB home quota — comfortable, but not so
comfortable that you can ignore it if you're building several things. Build
*stages* are the bulky transient part; send those to scratch (see above).

If you do run out, redirect and resume (spack keeps what it already installed):

```bash
spack config add "config:install_tree:root:$(cd ~/scratch && pwd -P)/spack/opt"
```

Reading the output: in `spack spec -I` and `spack find`, `[+]` means already
installed, `[e]` external (provided by the system), and `-` will be built from
source. Live `spack install` output uses a different convention — `[ ] pkg
... build` is a phase in progress, and `[+] pkg (33s)` means that package *just
finished*, with its elapsed time.

PACE's site config has an empty `compilers` scope, with compilers listed as
externals in `packages.yaml` instead (the spack v1.0 compilers-as-packages
change). Their gcc carries `languages:='c,c++,fortran'`, so Macaulay2's Fortran
build dependency is satisfied without compiling a toolchain.

Expect ~40 packages built from source. Then:

```bash
sbatch phoenix/build-m2.sbatch
```

and when it finishes:

```bash
. ~/spack/share/spack/setup-env.sh
spack load macaulay2
M2 --version
```

Use `spack config edit packages` to edit externals; set `SPACK_EDITOR` (e.g.
`export SPACK_EDITOR="emacs -nw"`) to control which editor it opens.

## Gotcha: heterogeneous nodes

Phoenix has at least two CPU generations — `cascadelake` (older) and
`sapphirerapids`. Spack optimizes each package for whichever chip it happens to
build on, so consecutive jobs landing on different node types produce a mixed
install tree.

That matters because instruction sets are forward-compatible but not backward:
a `cascadelake` build runs fine on a Sapphire Rapids node, but a
`sapphirerapids` build dies with `Illegal instruction` (SIGILL) on a Cascade
Lake one — with nothing in the error pointing at the cause.

Pin to the older target so the result runs anywhere and jobs stay eligible for
the widest node pool (no `--constraint` needed, so shorter queue waits):

```bash
spack config add "packages:all:target:[cascadelake]"
spack find --long | grep -oE 'arch=\S+' | sort | uniq -c    # verify uniformity
```

Check the floor first with `sinfo -o "%20N %40f" | sort -u -k2` — if there are
older nodes than cascadelake in the pool, use a generic baseline like
`x86_64_v3` instead.

## Gotcha: don't trust the system externals

This was the main source of trouble — three separate build cycles lost to it,
one failure at a time.

**The mechanism.** Linux distros split packages in two: a runtime piece
(`python3`, `openblas`, `perl`) and a development piece (`python3-devel`,
`openblas-devel`, `perl-core`) carrying headers, `.so` symlinks, static libs,
`.pc` files, and the full standard library. HPC compute node images install the
runtime half and omit the devel half — smaller images, faster provisioning,
less to patch.

Spack's external detection looks for the *runtime* artifact: an executable on
`PATH`, a versioned `.so`. That's exactly the half that is present. It then
records `prefix: /usr` and asserts to the concretizer that a complete,
spack-equivalent installation lives there, headers included. Nothing verifies
that claim, so the failure surfaces much later, inside an unrelated package.

| External | Detected | Actually missing | Died in |
|---|---|---|---|
| perl | `/usr/bin/perl` | `Unicode::Normalize`, `Test::More` (in `perl-core`) | texinfo configure |
| openblas | `libopenblaso.so.0` | serial `libopenblas.so` | fflas-ffpack configure |
| python | `/usr/bin/python3` | `Python.h` (in `python3-devel`) | macaulay2 build |

**This does not mean skipping `spack external find --all`.** It found roughly
35 usable packages here against 3 broken ones, and forgoing it means compiling
all 35. Run it — then audit, because the three failures were predictable from
what each external is *for*:

- **Externals you only execute are safe.** Build tools invoked as programs —
  `git`, `gmake`, `cmake`, `autoconf`, `pkg-config`, `bison` — need nothing but
  the binary, which is the half that's installed.
- **Externals you compile or link against are suspect.** Libraries, interpreters
  whose standard library gets loaded, anything providing headers. These need the
  `-devel` half, which is the half that's missing.

Every failure above is in the second category, and every external that worked
is in the first.

Audit before submitting rather than discovering these one job at a time:

```bash
spack spec -I macaulay2 | grep '\[e\]'
```

For each one you compile against, check that the development half exists —
`ls /usr/include/<thing>.h`, `ls /usr/lib64/lib<thing>.so` (the unversioned
symlink, not just `.so.N`), or `rpm -q <pkg>-devel`. For an interpreter, check
that the modules a dependent will want actually import.

The individual cases follow.

**perl.** The build died in texinfo's configure:

```
configure: error: perl >= 5.8.1 with Encode, Data::Dumper and Unicode::Normalize
required by Texinfo
```

(Texinfo is in the tree because M2 calls `install-info` during installation.)
Phoenix has perl 5.32.1, but it's a RHEL-style split install missing several
core modules — `Unicode::Normalize` and `Test::More` were both absent.
Detection found the interpreter and stopped there, so the failure surfaced much
later, inside an unrelated package.

`cpanm --local-lib=~/perl5 Unicode::Normalize` patches the immediate hole, but
requires exporting `PERL5LIB` in every job script and leaves the external perl
silently dependent on a home directory nothing in spack knows about. With two
modules already missing, more were likely.

**openblas.** Detected with `prefix: /usr`, but `/usr/lib` contains only
`libopenblaso.so.0`. RHEL and Debian ship three threading flavors —
`libopenblas.so.0` (serial), `libopenblas`**`o`**`.so.0` (OpenMP), and
`libopenblas`**`p`**`.so.0` (pthreads) — and only the OpenMP one was installed.
So `-lopenblas` named a library that does not exist, and fflas-ffpack's
configure died on it.

Worse, the flavor present is threaded, which is exactly what fflas-ffpack's
`depends_on("openblas threads=none")` exists to exclude. An external declares
its variants by fiat, so that constraint was silently unenforced — threaded
BLAS under fflas-ffpack is a real hazard for exact linear algebra.

**python.** Detected from `/usr/bin/python3`, but `Python.h` lives in
`python3-devel`, which isn't installed. Macaulay2's own build failed on it —
the last package in the tree, after everything else had succeeded.

**Fix in every case:** delete the externals block and let spack build it.

```bash
spack config edit packages     # remove perl, openblas, python, any lapack externals
spack spec -I macaulay2 | grep -iE "perl|blas|lapack|python"   # expect '-', not '[e]'
```

Removing an external changes hashes, so dependents get rebuilt — expect
`spack spec -I macaulay2 | grep -c '^ *-'` to jump. That's correct.

Check `lapack` separately; it's a distinct virtual and RHEL splits it the same
way. General rule: when a build fails on a dependency, first check whether that
dependency is `[e]`.

## Gotcha: transient fetch failures

One build died fetching a patch from GitHub during a GitHub outage. Nothing to
fix — just resubmit. Spack installs are resumable, so each attempt starts closer
to the finish.

## Resilience

A failed build keeps everything already installed, so resubmitting picks up
where it stopped.

`build-m2.sbatch` ends with a buildcache push, which snapshots the build as
relocatable tarballs. Restoring is minutes rather than hours, and it's also how
to migrate an install tree between filesystems without recompiling (a plain
`mv` does **not** work — spack bakes absolute paths into RPATHs and wrapper
scripts):

```bash
spack buildcache push --unsigned ~/m2-buildcache macaulay2
spack config add "config:install_tree:root:<new location>"
spack mirror add m2cache ~/m2-buildcache
spack install --use-buildcache only macaulay2
```

The buildcache is a second compressed copy in the same quota — about 1.5 GB
next to the 8.2 GB install tree, so ~9.7 GB of a ~20 GB home in total. That
fits, but if you're tighter on space, point the mirror at project storage
instead.

Relocating to a *longer* path can occasionally trip on RPATH headroom. If you
know in advance you'll move the tree, build with padding:

```bash
spack config add "config:install_tree:padded_length:128"
```

## Status of this effort

**Macaulay2 builds and runs on Phoenix** as of 2026-08-17.

- [x] Personal spack clone, install tree in home (8.2 GB), build stage in scratch
- [x] Target pinned to `cascadelake`
- [x] perl, openblas, and python externals removed
- [x] Build succeeds — four failed attempts along the way: perl/texinfo, a
      GitHub fetch flake, openblas/fflas-ffpack, python/macaulay2
- [x] `spack load macaulay2 && M2 --version` verified

Load it in a job script with:

```bash
. ~/spack/share/spack/setup-env.sh
spack load macaulay2
```
