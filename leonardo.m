 %This tomography code is used to simulate measurements
 %Made in a "Schordinger cat state" optical state to find the maximum
 %State of verisimilitude for this set of measurements.
 % In the reconstruction, we use histograms with squared
 %Respective measuring phases generating a matrix with lines (angle,
 %Center of the bin, number of counts in the bin) and from this matrix
 %We did an optimization process to calculate the state fidelity
 %And the new state generated by the histogram.
 %The infinite dimensional state space for the harmonic oscillator will be
 %Represented on the basis of the number of photons.
 %Let's truncate Hilbert space in photons maxPhotonNumber
 maxPhotonNumber = 10;

% First, pre-compute a lot of numbers, such as coefficients for Hermite
% polynomials factorials, bi,nomial coefficients.
S = init_tables(maxPhotonNumber);

% Make state vector for Schrodinger cat state.
alpha = 1;  % amplitude of coherent states in the superposition
phase = 0;  % phase between superposition
psi = generate_cat_vector(alpha, phase, S);
% The Schrodinger cat state suffers from some loss by passing through a
% medium with 80 % efficiency.
etaState = 0.8;
rho = apply_loss(psi,etaState,S);
%Now it should be represented by a density matrix, rho.
%  We chose 20 equally spaced phases in which our detector
  % measures this state.
  nMeasurements = 20000;

m = 20;% Number of equally spaced angles
                angles = pi*[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]/m; 
               angles = repmat(angles,1,ceil (nMeasurements/m)); 
                angles = angles(1:nMeasurements).';
                
 % The homodyne detector has efficiency 90 %.
etaDetector = 0.9;
% Now, we make the measurements of state rho.  Notice we have to specify
% maximum and minimum possible measurement results -7 and 7.
samples = homodyne_samples(-7,7,etaDetector,angles,rho,S);
% Structure containing the POVM element corresponding to each measurement
% result.  Note that the POVMs are not pure projectors.  The homodyne
% detector's efficiency has been included in the computation of the POVMs.
Povms = make_measurement_struct(samples,etaDetector,S);

% Now we will use the R*rho*R algorithm until we have done 2000 iterations
% or we reach stoppingCriterion 0.01 (whichever happens first).
% stoppingCriterion is an upper bound on the difference between the true
% maximum log-likelihood and the log-likelihood of that iterations's state.
maxIterations = 2000;
stoppingCriterion = 0.01;

[rhoML2, Diagnostics ] = combined_optimization( samples, S, etaDetector, 0, maxIterations, stoppingCriterion);

% Fidelity between the true state and the rebuilt state.
fidelity(rhoML2, rho)

b=1000;
m=20;
%  Constructs the matrix M that has as lines (angle, center of the bin, number of counts in the bin)
M = matrix_histogram(samples,b,m);


Povmshistogram = make_measurement_struct(M,etaDetector,S);

[Rhohistogram, Diagnostics] = combined_optimization (M, S, etaDetector, 0, maxIterations, stoppingCriterion);
% Calculates the fidelity between the true state and the reconstructed state
% Using the histogram
Fidelity (rhohistogram, rho)