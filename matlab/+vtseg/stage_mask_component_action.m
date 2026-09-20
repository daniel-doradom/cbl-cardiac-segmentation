function [staged_mask, details] = stage_mask_component_action( ...
        original_mask, current_staged_mask, action, selected_index, pixel_spacing)
%STAGE_MASK_COMPONENT_ACTION Apply a reversible component-review action.

if nargin < 4 || isempty(selected_index)
    selected_index = 1;
end
if nargin < 5 || isempty(pixel_spacing)
    pixel_spacing = [1, 1];
end
if ~isequal(size(original_mask), size(current_staged_mask))
    error('vtseg:ComponentMaskSize', 'Original and staged masks must have the same size.');
end

original_mask = logical(original_mask);
current_staged_mask = logical(current_staged_mask);
analysis = vtseg.analyze_mask_components(current_staged_mask, pixel_spacing);
action = validatestring(action, ...
    {'keep_largest', 'remove_selected', 'restore', 'keep_all', 'cancel'});
staged_mask = current_staged_mask;

switch action
    case 'keep_largest'
        staged_mask = false(size(current_staged_mask));
        if ~isempty(analysis.LargestIndex)
            staged_mask(analysis.PixelIdxList{analysis.LargestIndex}) = true;
        end
    case 'remove_selected'
        if analysis.Count == 0 || selected_index < 1 || selected_index > analysis.Count || ...
                selected_index ~= round(selected_index)
            error('vtseg:ComponentSelection', ...
                'Selected component must be an integer between 1 and %d.', analysis.Count);
        end
        staged_mask(analysis.PixelIdxList{selected_index}) = false;
    case {'restore', 'keep_all', 'cancel'}
        staged_mask = original_mask;
end

final_analysis = vtseg.analyze_mask_components(staged_mask, pixel_spacing);
original_analysis = vtseg.analyze_mask_components(original_mask, pixel_spacing);
removed = original_mask & ~staged_mask;
removed_analysis = vtseg.analyze_mask_components(removed, pixel_spacing);
details = struct( ...
    'Action', action, ...
    'OriginalComponentCount', original_analysis.Count, ...
    'FinalComponentCount', final_analysis.Count, ...
    'RemovedAreasPixels', removed_analysis.AreasPixels, ...
    'RemovedAreasMm2', removed_analysis.AreasMm2);
end
