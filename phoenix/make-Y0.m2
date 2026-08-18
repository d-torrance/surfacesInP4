-- Stage 1 of the genus-21 computation: build the artinian reduction Y0 and
-- write it to disk, so the expensive minimalBetti attempts (stage 2) can be
-- rerun without repeating this work.
--
-- Mirrors "surface in M2/K3OfGenus21.m2" lines 1-21.

needsPackage "NongeneralTypeSurfacesInP4"
kk=ZZ/nextPrime 10^4;P4=kk[x_0..x_4];E=kk[e_0..e_4,SkewCommutative=>true];
setRandomSeed("fix decomposition of D");

minimalBetti(X=K3surfaceD11S11Ln(P4,0))
elapsedTime betti(Y=minimalModelOfK3(X,Verbose=>true))

P21=ring Y

elapsedTime (dim Y, degree Y, genera Y)

L4=ideal (vars P21)_{0..4}
elapsedTime X'=trim ker map(P21/Y,P4,gens L4);
assert(
    X==X'
    )

-* computing betti numbers using the artinian reduction *-
P18=kk[(gens P21)_{0..18}]
Y0=sub(Y,P18);dim Y0, degree Y0
assert(dim Y0==0)

-- Hilbert function should be (1,19,19,1), total length 40.
apply(5, i -> hilbertFunction(i, P18/Y0))

-- Checkpoint. Stage 2 reconstructs P18 and Y0 by loading this file.
--
-- One statement per line on purpose: reading from stdin, M2 evaluates any line
-- that forms a complete expression, so a continuation line beginning with "<<"
-- would parse as a prefix << to stdio and silently write to the terminal
-- instead of the file.
-- Written to a temporary name and promoted only if it verifies. A failed
-- assert does NOT halt a script read from stdin, so the rename has to be
-- guarded by an if -- otherwise a corrupt checkpoint gets promoted anyway and
-- stage 2 loads it. Better to leave no checkpoint than a poisonous one.
ckpt = openOut "Y0.m2.tmp";
ckpt << "kk = ZZ/" << char kk << ";" << endl;
ckpt << "P18 = kk[" << demark(",", toString \ gens P18) << "];" << endl;
ckpt << "Y0 = " << toExternalString Y0 << ";" << endl;
close ckpt;

ckptLines = lines get "Y0.m2.tmp";
ckptOK = #ckptLines == 3 and match("^kk = ZZ/", ckptLines#0) and match("^P18 = kk\\[", ckptLines#1) and match("^Y0 = ideal", ckptLines#2);
if ckptOK then (moveFile("Y0.m2.tmp", "Y0.m2"); << "wrote Y0.m2 (" << #(get "Y0.m2") << " bytes)" << endl) else (removeFile "Y0.m2.tmp"; error "checkpoint verification failed -- no Y0.m2 written");
