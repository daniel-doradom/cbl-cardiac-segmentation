function myocardium = recompute_myocardium(Lendo, Rendo, Epi)
%RECOMPUTE_MYOCARDIUM Derive myocardium while enforcing cavity separation.

if ~isequal(size(Lendo), size(Rendo), size(Epi))
    error('vtseg:MaskSizeMismatch', 'Lendo, Rendo, and Epi must have the same size.');
end
Lendo = logical(Lendo);
Rendo = logical(Rendo);
Epi = logical(Epi);
if any(Lendo(:) & Rendo(:))
    error('vtseg:BloodPoolOverlap', 'Lendo and Rendo must not overlap.');
end
myocardium = Epi & ~Lendo & ~Rendo;
end
