-- Stage 2: minimal Betti numbers of the artinian reduction.
--
-- Reads Y0.m2 (written by make-Y0.m2). Controlled by environment variables:
--   LENGTH_LIMIT           homological degree to stop at (6, 8, 10)
--   M2_THREADS             cores available; must match --cpus-per-task
--   PARALLELIZE_BY_DEGREE  "true" enables the memory-hungry parallel strategy
--
-- Run at increasing length limits and watch MaxRSS: two data points
-- extrapolate to the full computation, and each rung gives partial Betti
-- numbers that are useful in their own right.

load "Y0.m2"

envValue = (name, default) -> (
    s := getenv name;
    if s === null or s === "" then default else value s)

lengthLimit = envValue("LENGTH_LIMIT", 6)
parallelizeByDegree = envValue("PARALLELIZE_BY_DEGREE", false)

-- Left at its default of 0, TBB uses every core it can see on the machine,
-- which on a shared node is far more than Slurm granted us.
numTBBThreads = envValue("M2_THREADS", 1)

-- One line on purpose: see the note in make-Y0.m2 about continuation lines
-- beginning with "<<" when M2 reads from stdin.
<< "-- LengthLimit => " << lengthLimit << ", ParallelizeByDegree => " << parallelizeByDegree << ", numTBBThreads => " << numTBBThreads << endl;

elapsedTime b = minimalBetti(Y0,
    DegreeLimit => 3,
    LengthLimit => lengthLimit,
    ParallelizeByDegree => parallelizeByDegree)
b

-- For comparison, the expected ranks at the crux: with h = {1,19,19,1} and
-- i = 11, the terms h_j * binomial(19, i-j) are 75582, 1755182, 1755182, 75582.
