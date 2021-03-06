function [rho, Diagnostics] = rga_more_photons( measurements, eta, maxIterations, stoppingREigMinusN, minPhotons, maxPhotons, startingRho)
% performs iterations of the regularized gradient ascent maximum likelihood
%   rga_iterations(rho, measurements, eta, maxIterations,
%   stoppingREigMinusN, S) performs iteraions of the regularized gradient
%   ascent maximum likelihood method. measurements can be a N-by-2 or
%   N-by-3 array containing N measurement results, where
%   measurementArray(n,:) = [phase angle, quadrature observed, number of
%   observations], but if the third column is absent it assums each result
%   was observed once.  Also, measurements can be the structre containing
%   POVMs made by make_measurement_struct.  eta is the efficiency of the
%   homodyne detector. Each iteration will apply the regularized gradient
%   ascent until maxIterations is reached or the largest eigenvalue of R
%   minus the total number of measurements is less than stoppingREigMinusN.
%   S is the structure generated by init_tables.  Upon completing the
%   iterations for the initial photon number minPhotons, rga_more_photons
%   expands to Hilbert space to maxPhotons and checks the new rEigMinusN in
%   the larger Hilbert space.  If the value is smaller than
%   stoppingReigMinusN, the work is done.  If the value is larger than
%   stoppingReigMinusN, rga iterations are performed in the space of
%   minPhotons+1.  This continues adding photons until a solution is found
%   with rEigMinusN < stoppingReigMinusN in the maxPhotons space.
%
%   WARNING!!!  This stopping criterion for the number of photons is not
%   effective.  When the algorithm stops adding photons depends critically
%   on the value of maxPhotons.  We believe this is not a reliable method
%   to decide how many photons should be included for a good tomography.
%
%   [rho, Diagnostics] = also returns a structure with the following
%   diagnostic information.
%      Diagnostics.rhoArray = density matrix at each iteration
%      Diagnostics.loglikelihoodList = loglikelihood at each iteration
%      Diagnostics.rArray = 3D array of r matrices at each iteration.
%      Diagnostics.rEigMinusNList = list of (maximum eigenvalue of r) -
%         (number of measurements) at each iteration.
%      Diagnostics.Measurements = strucutre for measurement
%         restults, made by make_measurement_struct.
%      Diganostics.iterationCounter = array of [iteration number, goal
%          radius, maximum eigenvalue of m, lambdaR (lagrange multiplier),
%          current loglikelihood]

S = init_tables(minPhotons);
Smax = init_tables(maxPhotons);

Diagnostics.photons = zeros(maxIterations+1,1);
Diagnostics.rhoArray = zeros(S.dimHilbertSpace,S.dimHilbertSpace,maxIterations+1);
Diagnostics.loglikelihoodList = zeros(maxIterations+1,1);
Diagnostics.rArray = zeros(S.dimHilbertSpace, S.dimHilbertSpace, maxIterations+1);
Diagnostics.rEigMinusNList = zeros(maxIterations+1, 1);
iterationCounter = zeros(1,6); 

format short g
disp('   iteration,   photons, step,        mMaxEig,     lambda,     loglik,       max(eig(R))-N')

if isnumeric(measurements)
    Measurements = make_measurement_struct(measurements, eta, S);
    MeasurementsMax = make_measurement_struct(measurements, eta, Smax);
elseif isstruct(measurements)
    Measurements = measurements;
    MeasurementsMax = make_measurement_struct(measurements, eta, S);
end

% initial guess to begin maxlik r*rho*r algorithm, the maximally mixed
% state
if nargin == 6
    rho = eye(S.dimHilbertSpace) ./ (S.dimHilbertSpace);
elseif nargin == 7
    rho = startingRho;
end

nIteration = 1;
stepSize = 1;
R = make_r_struct(rho, Measurements);
Diagnostics = add_diagnostic(S, R, Diagnostics, nIteration);
newCounterRow = [nIteration-1, S.photons, 0, 0, 0, R.loglike, R.rEigMinusN];
disp(newCounterRow)
iterationCounter = newCounterRow;
rMax = stoppingREigMinusN + 2;
while S.photons <= maxPhotons && rMax > stoppingREigMinusN
    while R.rEigMinusN > stoppingREigMinusN && nIteration <= maxIterations
        nIteration = nIteration + 1;
        reduceStepSize = true;
        rho = mix_rho(R.rho, Measurements);
        newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
        disp(newCounterRow)
        iterationCounter = [iterationCounter; newCounterRow];
        R = make_r_struct(rho, Measurements);
        RI = make_ri_struct(R.rho, R.r);
        v = v_big_vector(RI);
        m = m_big_matrix(RI, Measurements, R.tprl);
        [mDiagonalizer, mDiag] = eig(m);
        mEigList = diag(mDiag);
        mMaxEigenvalue = max(mEigList);
        lambdaStart = max([mMaxEigenvalue; 0]);
        stepCounter = 0;
        while reduceStepSize
            stepCounter = stepCounter+1;
            if stepCounter > 20;
                return
            end
            lambdaR = lambdaStart;
            increasedLambdaR = true;
            while increasedLambdaR
                newCounterRow = [nIteration-1, S.photons, stepSize, mMaxEigenvalue, lambdaR, R.loglike, R.rEigMinusN];
                disp(newCounterRow)
                iterationCounter = [iterationCounter; newCounterRow];
                aRI = ari_of_lambda(lambdaR, mEigList, mDiagonalizer, v);
                checkStepSize = aRI.'*aRI;
                if checkStepSize <= stepSize
                    increasedLambdaR = false;
                elseif checkStepSize > stepSize
                    lambdaR = 2*lambdaR;
                end
            end %finding lambdaR

            a = unvectorize_r_i(aRI);
            rhoTest = (RI.rhoSqrt+a)*(RI.rhoSqrt+a');
            rhoTest = rhoTest/trace(rhoTest);
            RTest = make_r_struct(rhoTest, Measurements);
            if RTest.loglike > R.loglike
                reduceStepSize = false;
                R = RTest;
                newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
                disp(newCounterRow)
                iterationCounter = [iterationCounter; newCounterRow]; 
            else
                stepSize = stepSize/2;
                reduceStepSize = true;
            end
        end % end finding small enough radius
        Diagnostics = add_diagnostic(S, R, Diagnostics, nIteration);
    end % rga iterations
    stepSize = 1;
    rhoAddRows = R.rho;
    rhoAddRows(Smax.dimHilbertSpace, Smax.dimHilbertSpace) = 0;
    Rmax = make_r_struct(rhoAddRows, MeasurementsMax);
    rMax = Rmax.rEigMinusN
    if S.photons <= maxPhotons && rMax > stoppingREigMinusN
        S = init_tables(S.photons+1);
        Measurements = make_measurement_struct(Measurements.measurementArray, eta, S);
        rhoAddRow = R.rho;
        rhoAddRow(S.dimHilbertSpace, S.dimHilbertSpace) = 0;
        rho = mix_rho(rhoAddRow, Measurements);
        R = make_r_struct(rho, Measurements);
        newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
        disp(newCounterRow)
        iterationCounter = [iterationCounter; newCounterRow];
    end
end % adding photons
if nIteration > maxIterations
    warning('Tomography:fewIterations','maximum number of iterations reached before fidelity converged')
end

% trim extra rows from Diangostics
Diagnostics.photons((nIteration+1):end) = [];
Diagnostics.rhoArray(:,:,(nIteration+1):end) = [];
Diagnostics.loglikelihoodList((nIteration+1):end) = [];
Diagnostics.rArray(:,:,(nIteration+1):end) = [];
Diagnostics.rEigMinusNList((nIteration+1):end) = [];
Diagnostics.Measurements = Measurements;
Diagnostics.iterationCounter = iterationCounter;

    
rho = R.rho;
end



function R = make_r_struct(rho, Measurements)
R.rho = rho;
R.tprl = tr_povm_rho_list(rho, Measurements);
R.r = r_or_gradient(R.rho, Measurements, R.tprl, 'R');
R.rEigMinusN = real(max_eig(R.r)) - Measurements.nTotalMeasurements;
R.loglike = loglikelihood(R.rho, Measurements, R.tprl);
end



function Diagnostics = add_diagnostic(S, R, Diagnostics, nIteration)
sizeRho = size(R.rho,1);
sizeRhoArray = size(Diagnostics.rhoArray,1);
if sizeRho ~= sizeRhoArray
    Diagnostics.rhoArray(sizeRho,sizeRho,:)=0;
    Diagnostics.rArray(sizeRho, sizeRho,:) = 0;
end
Diagnostics.photons(nIteration,1) = S.photons;
Diagnostics.rhoArray(:,:,nIteration) = R.rho;
Diagnostics.rArray(:,:,nIteration) = R.r;
Diagnostics.rEigMinusNList(nIteration,1) = R.rEigMinusN;
Diagnostics.loglikelihoodList(nIteration,1) = R.loglike;
end

function rho = mix_rho(rho, Measurements)
d = diag(rho);
nZeros = sum(d==0);
if nZeros ~=0
    dm = diag(diag(rho)==0)/nZeros;
    rho = (1-1/Measurements.nTotalMeasurements)*rho + 1/Measurements.nTotalMeasurements*dm;
end
end

% nIteration = 1;
% stepSize = 1;
% R = make_r_struct(rho, Measurements);
% Diagnostics = add_diagnostic(S, R, Diagnostics, nIteration);
% newCounterRow = [nIteration-1, S.photons, 0, 0, 0, R.loglike, R.rEigMinusN];
% disp(newCounterRow)
% iterationCounter = newCounterRow;
% while S.photons <= maxPhotons
%     while R.rEigMinusN > stoppingREigMinusN && nIteration <= maxIterations
%         nIteration = nIteration + 1;
%         reduceStepSize = true;
%         rho = mix_rho(R.rho, Measurements);
%         newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
%         disp(newCounterRow)
%         iterationCounter = [iterationCounter; newCounterRow];
%         R = make_r_struct(rho, Measurements);
%         RI = make_ri_struct(R.rho, R.r);
%         v = v_big_vector(RI);
%         m = m_big_matrix(RI, Measurements, R.tprl);
%         [mDiagonalizer, mDiag] = eig(m);
%         mEigList = diag(mDiag);
%         mMaxEigenvalue = max(mEigList);
%         lambdaStart = max([mMaxEigenvalue; 0]);
%         stepCounter = 0;
%         while reduceStepSize
%             stepCounter = stepCounter+1;
%             if stepCounter > 20;
%                 return
%             end
%             lambdaR = lambdaStart;
%             increasedLambdaR = true;
%             while increasedLambdaR
%                 newCounterRow = [nIteration-1, S.photons, stepSize, mMaxEigenvalue, lambdaR, R.loglike, R.rEigMinusN];
%                 disp(newCounterRow)
%                 iterationCounter = [iterationCounter; newCounterRow];
%                 aRI = ari_of_lambda(lambdaR, mEigList, mDiagonalizer, v);
%                 checkStepSize = aRI.'*aRI;
%                 if checkStepSize <= stepSize
%                     increasedLambdaR = false;
%                 elseif checkStepSize > stepSize
%                     lambdaR = 2*lambdaR;
%                 end
%             end %finding lambdaR
% 
%             a = unvectorize_r_i(aRI);
%             rhoTest = (RI.rhoSqrt+a)*(RI.rhoSqrt+a');
%             rhoTest = rhoTest/trace(rhoTest);
%             RTest = make_r_struct(rhoTest, Measurements);
%             if RTest.loglike > R.loglike
%                 reduceStepSize = false;
%                 R = RTest;
%                 newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
%                 disp(newCounterRow)
%                 iterationCounter = [iterationCounter; newCounterRow]; 
%             else
%                 stepSize = stepSize/2;
%                 reduceStepSize = true;
%             end
%         end % end finding small enough radius
%         Diagnostics = add_diagnostic(S, R, Diagnostics, nIteration);
%     end % rga iterations
%     stepSize = 1;
%     S = init_tables(S.photons+1);
%     Measurements = make_measurement_struct(Measurements.measurementArray, eta, S);
%     rhoAddRow = R.rho;
%     rhoAddRow(S.dimHilbertSpace, S.dimHilbertSpace) = 0;
%     R = make_r_struct(rhoAddRow, Measurements);
%     newCounterRow = [nIteration-1, S.photons, stepSize, 0, 0, R.loglike, R.rEigMinusN];
%     disp(newCounterRow)
%     iterationCounter = [iterationCounter; newCounterRow];
% end % adding photons
% if nIteration > maxIterations
%     warning('Tomography:fewIterations','maximum number of iterations reached before fidelity converged')
% end
