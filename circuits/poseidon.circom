include "./poseidon_constants_opt.circom";

template Sigma() {
    signal input in;
    signal output out;

    signal in2;
    signal in4;

    in2 <== in*in;
    in4 <== in2*in2;

    out <== in4*in;
}

template Ark(t, C, r) {
    signal input in[t];
    signal output out[t];

    for (var i=0; i<t; i++) {
        out[i] <== in[i] + C[i + r];
    }
}

template PartialRound(t, S, r) {
    signal input in[t];
    signal output out[t];
    var acc = 0;

    for (var i=0; i<t; i++) {
        acc += S[(t*2-1)*r+t+i-1] * in[i];    
    }
    out[0] <== acc;
    for (var i=1; i<t; i++) {
        /* state[k] = F.add(state[k], F.mul(state[0], S[(t*2-1)*r+t+k-1]   )); */
        out[i] <== in[i] + (in[0] * S[(t*2-1)*r+t+i-1]);
    }
}

template Mix(t, M) {
    signal input in[t];
    signal output out[t];

    var lc;
    for (var i=0; i<t; i++) {
        lc = 0;
        for (var j=0; j<t; j++) {
            lc += M[j][i]*in[j];
        }
        out[i] <== lc;
    }
}

template Poseidon(nInputs) {
    signal input inputs[nInputs];
    signal output out;

		// Using recommended parameters from whitepaper https://eprint.iacr.org/2019/458.pdf (table 2, table 8)
		// Generated by https://extgit.iaik.tugraz.at/krypto/hadeshash/-/blob/master/code/calc_round_numbers.py
		// And rounded up to nearest integer that divides by t
    var t = nInputs + 1;
    var nRoundsF = 8;
    var nRoundsP = 35;
    var C[t*(nRoundsF + nRoundsP)] = POSEIDON_C(t);
    var S[t*(nRoundsF + nRoundsP)] = POSEIDON_S(t);
    var M[t][t] = POSEIDON_M(t);
    var P[t][t] = POSEIDON_P(t);

    component ark[nRoundsF];
    component sigmaF[nRoundsF - 1][t];
    component sigmaP[nRoundsP];
    component partialR[nRoundsP];
    component mix[nRoundsF - 1];
    component pix;

    var k;
    // begin 
    /* state = state.map((a, i) => F.add(a, C[i])); */
    ark[0] = Ark(t, C, 0);
    for (var j=0; j<t; j++) {
        if (j<nInputs) {
            ark[0].in[j] <== inputs[j];
        } else {
            ark[0].in[j] <== 0;
        }
    } 

    // begin
    /* for (let r = 0; r < nRoundsF/2-1; r++) { */
    /*     state = state.map(a => pow5(a)); */
    /*     state = state.map((a, i) => F.add(a, C[(r +1)* t +i])); */
    /*     state = state.map((_, i) => */
    /*         state.reduce((acc, a, j) => F.add(acc, F.mul(M[j][i], a)), F.zero) */
    /*     ); */
    /* } */
    var r;
    for(r=0; r < nRoundsF/2; r++) {
        ark[r+1] = Ark(t, C, r*t);
        for (var j=0; j<t; j++) {
            if (r==0) {
                ark[r+1].in[j] <== ark[r].out[j];
            } else {
                ark[r+1].in[j] <== mix[r-1].out[j];
            }
        } 

        mix[r] = Mix(t, M);
        for (var j=0; j<t; j++) {
            sigmaF[r][j] = Sigma();
            sigmaF[r][j].in <== ark[r+1].out[j];
            mix[r].in[j] <== sigmaF[r][j].out;
        }
    }


    // begin
    /* state = state.map(a => pow5(a)); */
    /* state = state.map((a, i) => F.add(a, C[(nRoundsF/2-1 +1)* t +i])); */
    /* state = state.map((_, i) => */
    /*     state.reduce((acc, a, j) => F.add(acc, F.mul(P[j][i], a)), F.zero) */
    /* ); */


    ark[r] = Ark(t, C, r);
    r += 1;
    pix = Mix(t, P);
    for (var j=0; j<t; j++) {
        sigmaF[r][j] = Sigma();
        sigmaF[r][j].in <== ark[r].out[j];
        pix[r].in[j] <== sigmaF[r][j].out;
    }
    r++; 

    // begin
    /* for (let r = 0; r < nRoundsP; r++) { */
    /*     state[0] = pow5(state[0]); */
    /*     state[0] = F.add(state[0], C[(nRoundsF/2 +1)*t + r]); */
    /*     const s0 = state.reduce((acc, a, j) => { */
    /*         return F.add(acc, F.mul(S[(t*2-1)*r+j], a)); */
    /*     }, F.zero); */
    /*     for (let k=1; k<t; k++) { */
    /*         state[k] = F.add(state[k], F.mul(state[0], S[(t*2-1)*r+t+k-1]   )); */
    /*     } */
    /*     state[0] =s0; */

    // First iteration is done outside of the loop in order to match inputs correctly in it
    sigmaP[0] = Sigma();
    sigmaP[0].in <== pix.out[0];

    partialR[0] = PartialRound(t, S, r);

    partialR[0].in[0] <== sigmaP[0].out;
    for(var j=1; j<t; j++) {
        partialR[0].in[j] <== pix.out[j];
    }

    for(var p=1; p<nRoundsP; p++) {
        sigmaP[p] = Sigma();
        sigmaP[p].in <== partialR[p-1].out[0];

        partialR[p] = PartialRound(t, S, p);

        partialR[p].in[0] <== sigmaP[p].out;
        for(var j=1; j<t; j++) {
            partialR[p].in[j] <== partialR[p-1].out[j];
        }
        r++; 
    }
    
    // r == 0 
    k = nRoundsF/2+1;

    ark[k] = Ark(t, C, t*r);
    for (var j=0; j<t; j++) {
        ark[k].in[j] <== mix[k-1].out[j];
    }

    mix[k] = Mix(t, M);
    for (var j=0; j<t; j++) {
        sigmaF[k][j] = Sigma();
        sigmaF[k][j].in <== ark[k].out[j];
        mix[k].in[j] <== sigmaF[k][j].out;
    }

    for(r=1; r < nRoundsF/2-1; r++) {
        k = r + nRoundsF/2+1;

        ark[k] = Ark(t, C, t*r);
        for (var j=0; j<t; j++) {
            ark[k].in[j] <== mix[k-1].out[j];
        }

        mix[k] = Mix(t, M);
        for (var j=0; j<t; j++) {
            sigmaF[k][j] = Sigma();
            sigmaF[k][j].in <== ark[k].out[j];
            mix[k].in[j] <== sigmaF[k][j].out;
        }
    }

    for (var j=0; j<t; j++) {
        k = r + nRoundsF/2;
        mix[k] = Mix(t, M);
        sigmaF[k][j] = Sigma();
        sigmaF[k][j].in <== mix[k-1].out[j];
        mix[k].in[j] <== sigmaF[k][j].out;
    }
    out <== mix[r].out[0];

    /* // old */
    /* for (var i=0; i<nRoundsF + nRoundsP - 1; i++) { */
    /*     ark[i] = Ark(t, C, t*i); */
    /*     for (var j=0; j<t; j++) { */
    /*         if (i==0) { */
    /*             if (j<nInputs) { */
    /*                 ark[i].in[j] <== inputs[j]; */
    /*             } else { */
    /*                 ark[i].in[j] <== 0; */
    /*             } */
    /*         } else { */
    /*             ark[i].in[j] <== mix[i-1].out[j]; */
    /*         } */
    /*     } */
    /*  */
    /*     if (i < nRoundsF/2 || i >= nRoundsP + nRoundsF/2) { */
    /*         k = i < nRoundsF/2 ? i : i - nRoundsP; */
    /*         mix[i] = Mix(t, M); */
    /*         for (var j=0; j<t; j++) { */
    /*             sigmaF[k][j] = Sigma(); */
    /*             sigmaF[k][j].in <== ark[i].out[j]; */
    /*             mix[i].in[j] <== sigmaF[k][j].out; */
    /*         } */
    /*     } else { */
    /*         k = i - nRoundsF/2; */
    /*         mix[i] = Mix(t, M); */
    /*         sigmaP[k] = Sigma(); */
    /*         sigmaP[k].in <== ark[i].out[0]; */
    /*         mix[i].in[0] <== sigmaP[k].out; */
    /*         for (var j=1; j<t; j++) { */
    /*             mix[i].in[j] <== ark[i].out[j]; */
    /*         } */
    /*     } */
    /* } */
    /*  */
    /* // last round is done only for the first word, so we do it manually to save constraints */
    /* component lastSigmaF = Sigma(); */
    /* lastSigmaF.in <== mix[nRoundsF + nRoundsP - 2].out[0] + C[t*(nRoundsF + nRoundsP - 1)]; */
    /* out <== lastSigmaF.out; */
}
