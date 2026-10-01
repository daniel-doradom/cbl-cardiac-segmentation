function applies = offset_suggestion_applies(requests, slice, declined)
%OFFSET_SUGGESTION_APPLIES Whether to suggest kept offsets on this slice.
%   applies = vtseg.offset_suggestion_applies(requests, slice, declined)
%
%   A request is suggested only on a slice right next to one in its Covered
%   list and not in that list itself, and nothing is suggested on a slice in
%   declined, where the user chose Skip. Each request is checked on its own,
%   so one structure already covered here does not hide another. A change
%   therefore moves one slice at a time, and only while it keeps being
%   accepted.

if nargin < 3
    declined = [];
end
applies = false;
if isempty(requests) || ismember(slice, declined)
    return;
end
for index = 1:numel(requests)
    covered = requests(index).Covered;
    if ~ismember(slice, covered) && any(abs(covered - slice) == 1)
        applies = true;
        return;
    end
end
end
