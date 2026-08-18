-- Stage 2: minimal Betti numbers of the artinian reduction.
--
-- Reads Y0.m2 (written by make-Y0.m2) and runs minimalBetti at the length
-- limit given in the environment variable LENGTH_LIMIT.
--
-- Run this at increasing limits (6, 8, 10) and watch MaxRSS: two data points
-- extrapolate to the cost of the full computation, and each rung produces
-- usable partial Betti numbers.

load "Y0.m2"

lengthLimit = value getenv "LENGTH_LIMIT"
if lengthLimit === null then lengthLimit = 6

<< "-- DegreeLimit => 3, LengthLimit => " << lengthLimit << endl

elapsedTime b = minimalBetti(Y0, DegreeLimit => 3, LengthLimit => lengthLimit)
b

-- Expected ranks at the crux, for comparison: with h = {1,19,19,1} and i = 11,
-- the four terms h_j * binomial(19, i-j) are 75582, 1755182, 1755182, 75582.
