-- computations for the (11, 11, 5, 2, 21) example:
needsPackage"NongeneralTypeSurfacesInP4"
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
-* two much memory on my machine but might work on a cluster: *-
elapsedTime minimalBetti(Y0,DegreeLimit=>3,LengthLimit=>10)



