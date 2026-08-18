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
"Y0.m2" << "kk = ZZ/" << char kk << ";" << endl
        << "P18 = kk[" << demark(",", toString \ gens P18) << "];" << endl
        << "Y0 = " << toExternalString Y0 << ";" << endl << close;

<< "wrote Y0.m2" << endl
