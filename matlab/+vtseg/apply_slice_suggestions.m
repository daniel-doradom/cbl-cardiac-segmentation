function [masks, details] = apply_slice_suggestions(masks, requests, slice, pixel_spacing)
%APPLY_SLICE_SUGGESTIONS Apply every kept change suggested for one slice.
%   [masks, details] = vtseg.apply_slice_suggestions(masks, requests, slice, ...
%       pixel_spacing)
%
%   requests mixes Grow / shrink requests (Kind 'offset', see
%   vtseg.apply_offset_suggestion) and Review Islands requests (Kind
%   'islands', see vtseg.apply_island_suggestion). Grow / shrink requests are
%   applied first, so an island clean-up acts on the outline as it will be.
%   A request whose Covered list already holds slice is skipped.
%
%   details has one entry per request, in the order of requests: Kind,
%   Structure, Changed, Skipped, and Info, the detail of the function that
%   applied it.

details = repmat(struct('Kind', '', 'Structure', '', 'Changed', false, ...
    'Skipped', '', 'Info', []), numel(requests), 1);
kinds = {requests.Kind};
order = [find(strcmp(kinds, 'offset')), find(~strcmp(kinds, 'offset'))];
for index = order
    request = requests(index);
    details(index).Kind = request.Kind;
    details(index).Structure = request.Structure;
    if ismember(slice, request.Covered)
        details(index).Skipped = 'this slice already has this change';
        continue;
    end
    if strcmp(request.Kind, 'islands')
        [masks, info] = vtseg.apply_island_suggestion(masks, request, slice, pixel_spacing);
    else
        [masks, info] = vtseg.apply_offset_suggestion(masks, request, slice, pixel_spacing);
    end
    details(index).Changed = info.Changed;
    details(index).Skipped = info.Skipped;
    details(index).Info = info;
end
end
