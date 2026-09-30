function limits = mask_offset_limits(structure, Lendo, Rendo, Epi, ~)
%MASK_OFFSET_LIMITS Neighbours that stop a grow or shrink of one structure.
%   limits = vtseg.mask_offset_limits(structure, Lendo, Rendo, Epi, lepi)
%
%   All masks are 2D slices of the same size; lepi may be empty. structure
%   is 'Lendo', 'Rendo', 'Epi' or 'lepi'. The rules mirror the checks run
%   before a slice is accepted: the two cavities may not overlap, and both
%   must stay inside Epi.
%     Lendo grows up to Rendo and the outside of Epi.
%     Rendo grows up to Lendo and the outside of Epi.
%     Epi shrinks down to Lendo and Rendo, and grows freely.
%     lepi grows up to Rendo and shrinks down to Lendo.
%   An empty Epi is treated as absent rather than as a wall everywhere.

% lepi is accepted for a uniform call but no rule needs it: every limit is
% set by the two cavities and Epi.
Lendo = logical(Lendo); Rendo = logical(Rendo); Epi = logical(Epi);
outside_epi = false(size(Epi));
if any(Epi(:))
    outside_epi = ~Epi;
end
none = false(size(Epi));
switch structure
    case 'Lendo'
        limits = struct('blocked', Rendo | outside_epi, 'protected', none);
    case 'Rendo'
        limits = struct('blocked', Lendo | outside_epi, 'protected', none);
    case 'Epi'
        limits = struct('blocked', none, 'protected', Lendo | Rendo);
    case 'lepi'
        limits = struct('blocked', Rendo, 'protected', Lendo);
    otherwise
        error('vtseg:OffsetStructure', 'Unknown structure "%s".', structure);
end
end
