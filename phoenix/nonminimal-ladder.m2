-- Stage 3: nonminimal resolution of the artinian reduction, and extraction of
-- the Koszul matrix M whose rank gives the middle Betti number.
--
-- Why this rather than minimalBetti (see phoenix/README-genus21.md):
-- minimalBetti computes the same nonminimal resolution and then calls
-- rawMinimalBetti on it. That minimalization is dense Gaussian elimination,
-- and it is what exhausted 180 GB after 22.5 hours at LengthLimit => 6.
-- minimalBetti also quietly asks the resolution for LengthLimit + 1 steps
-- (OldChainComplexes/betti.m2), so this does strictly less work.
--
-- Environment:
--   LENGTH_LIMIT           homological degree to stop at
--   DEGREE_LIMIT           strand cutoff; 3 matches Frank's minimalBetti call
--   M2_THREADS             cores available; must match --cpus-per-task
--   PARALLELIZE_BY_DEGREE  "true" for the memory-hungry parallel strategy

load "Y0.m2"

envValue = (name, default) -> (
    s := getenv name;
    if s === null or s === "" then default else value s)

lengthLimit = envValue("LENGTH_LIMIT", 6)
degreeLimit = envValue("DEGREE_LIMIT", 3)
parallelizeByDegree = envValue("PARALLELIZE_BY_DEGREE", false)
numTBBThreads = envValue("M2_THREADS", 1)

<< "-- Nonminimal: LengthLimit => " << lengthLimit << ", DegreeLimit => " << degreeLimit << ", ParallelizeByDegree => " << parallelizeByDegree << ", numTBBThreads => " << numTBBThreads << endl;

elapsedTime fY0 = res(Y0, Strategy => Nonminimal, DegreeLimit => degreeLimit, LengthLimit => lengthLimit, ParallelizeByDegree => parallelizeByDegree);

<< "-- nonminimal ranks: " << apply(lengthLimit+1, i -> rank fY0_i) << endl;
betti fY0

-- Every run so far has sat at 105-112% CPU with system time around 40% of
-- user time and ~1e9 minor page faults, independent of thread count or
-- ParallelizeByDegree. GC mark phases touch all live memory, so
-- numGCs * heapSize is the quantity to compare against those page faults.
-- If collection dominates, GC_INITIAL_HEAP_SIZE and GC_FREE_SPACE_DIVISOR
-- are the levers, not cores.
gcs = GCstats();
<< "-- GC: numGCs=" << gcs#"numGCs" << " heapSize=" << gcs#"heapSize" << " gcCpuTimeSecs=" << gcs#"gcCpuTimeSecs" << " freeSpaceDivisor=" << gcs#"GC_free_space_divisor" << " numGCThreads=" << gcs#"numGCThreads" << endl;

-- Frank's extraction (K3OfGenus21.m2 lines 26-29). Only meaningful once the
-- resolution reaches step 10, where the degree-11 block of d_10 is the
-- 1755182 x 1755182 Koszul matrix.
if lengthLimit >= 10 then (
    elapsedTime posc = positions(degrees fY0_10, d -> d_0 == 11);
    elapsedTime posr = positions(degrees fY0_9, d -> d_0 == 11);
    << "-- block size: " << #posr << " rows x " << #posc << " cols (expect 1755182 x 1755182)" << endl;
    elapsedTime M1 = fY0.dd_10^posr_posc;
    betti M1;
    elapsedTime M = map(kk^(rank target M1), , sub(M1, kk));
    << "-- M: " << numrows M << " x " << numcols M << " over " << describe ring M << endl;

    -- Do NOT call rank M. matrix1.m2:673 sends it to basicRank
    -- (quotring.m2:151), which does mutableMatrix(f, Dense=>true) with Dense
    -- hardcoded, reaching DMat<ARingZZpFlint> with 8-byte entries: 1755182^2
    -- is ~24.6 TB, allocated up front in nmod_mat_init. smat.hpp has no rank
    -- implementation at all, so there is no dense/sparse switch to flip.
    --
    -- syz is the sparse route. Over a field ZZ/p (not a polynomial ring),
    -- comp-gb.cpp:50-64 short-circuits to GaussElimComputation (e/gauss.cpp),
    -- which eliminates on sparse vec lists with a Markowitz-style pivot
    -- heuristic. Note gauss.hpp:21-25 calls itself "very slow ... To be
    -- rewritten" and has no fill-in control, so this may still be
    -- intractable -- but it will not attempt an n^2 allocation.
    --
    -- numberOfExtraSyzygies = nullity(M) - 75582, zero iff the genus-21 K3
    -- has the expected Betti numbers.
    << "-- attempting syz M (sparse Gaussian elimination in the engine)" << endl;
    elapsedTime sM = syz M;
    nullity = numcols sM;
    << "-- nullity = " << nullity << ", expected 75582" << endl;
    << "-- numberOfExtraSyzygies = " << (nullity - 75582) << endl;
    << "-- rank M = " << (numcols M - nullity) << ", expected 1679600" << endl;
    )
