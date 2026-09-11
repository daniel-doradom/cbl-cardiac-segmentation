classdef ReviewStyle
%REVIEWSTYLE Shared look of the vtseg MATLAB review and result windows.
%
% Every figure the MATLAB pipeline opens goes through newFigure, so they all
% share one dark surface, one type scale and one title pattern,
% "FigN: Stage: detail", where N is MATLAB's own figure number. Controls come
% from section, label, button, slider, toggle and field, so a window built
% from them looks like the mask correction window. The class holds no state;
% every method is static.

    methods (Static)

        function theme = theme()
        %THEME Colours and type shared by every review window.
        % A dark surface keeps grayscale images and coloured contours the
        % brightest things on screen, which is what a reviewer looks at.
            theme = struct( ...
                'figure', [0.11 0.13 0.16], ...   % window background
                'panel', [0.16 0.19 0.23], ...    % side panels and header bars
                'border', [0.30 0.34 0.40], ...   % 1 px panel outline
                'field', [0.21 0.24 0.29], ...    % sliders and text fields
                'text', [0.93 0.94 0.96], ...
                'muted', [0.66 0.70 0.76], ...
                'primary', [0.15 0.45 0.90], ...  % the one action to take next
                'neutral', [0.26 0.30 0.36], ...  % every other action
                'danger', [0.72 0.22 0.22], ...   % actions that throw work away
                'font_size', 10);
        end

        function handle = newFigure(name, varargin)
        %NEWFIGURE A themed figure titled "FigN: name", N being its figure number.
        % Extra name-value pairs are passed to figure(). Axes, labels and
        % titles created in the figure inherit light colours through
        % figure-level defaults, so plain title() and xlabel() calls stay
        % readable on the dark surface.
            theme = vtseg.ReviewStyle.theme();
            handle = figure('Name', name, 'NumberTitle', 'off', ...
                'Color', theme.figure, varargin{:});
            % MATLAB's own "Figure N:" prefix is replaced by a shorter "FigN:"
            % so the number stays visible without crowding out the name.
            number = get(handle, 'Number');
            if ~isempty(number)
                set(handle, 'Name', sprintf('Fig%d: %s', number, name));
            end
            set(handle, ...
                'DefaultAxesColor', theme.figure, ...
                'DefaultAxesXColor', theme.muted, ...
                'DefaultAxesYColor', theme.muted, ...
                'DefaultAxesZColor', theme.muted, ...
                'DefaultAxesGridColor', theme.border, ...
                'DefaultAxesMinorGridColor', theme.border, ...
                'DefaultTextColor', theme.text, ...
                'DefaultUipanelBackgroundColor', theme.panel, ...
                'DefaultUipanelForegroundColor', theme.muted, ...
                'DefaultUicontrolBackgroundColor', theme.panel, ...
                'DefaultUicontrolForegroundColor', theme.text);
        end

        function panel = section(parent, position, label)
        %SECTION One outlined panel; an empty label gives an untitled bar.
            theme = vtseg.ReviewStyle.theme();
            panel = uipanel(parent, 'Units', 'normalized', 'Position', position, ...
                'Title', label, 'TitlePosition', 'lefttop', ...
                'BackgroundColor', theme.panel, 'ForegroundColor', theme.muted, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'FontSize', theme.font_size - 1, 'FontWeight', 'bold');
            % Newer releases replace HighlightColor/ShadowColor with
            % BorderColor and warn when the old pair is set.
            if isprop(panel, 'BorderColor')
                set(panel, 'BorderColor', theme.border);
            else
                set(panel, 'HighlightColor', theme.border, 'ShadowColor', theme.border);
            end
        end

        function handle = label(parent, position, text, alignment, muted)
        %LABEL Static text on a panel; muted text is for values and hints.
            theme = vtseg.ReviewStyle.theme();
            color = theme.text;
            if muted
                color = theme.muted;
            end
            handle = uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
                'Position', position, 'String', text, ...
                'HorizontalAlignment', alignment, ...
                'BackgroundColor', theme.panel, 'ForegroundColor', color, ...
                'FontSize', theme.font_size);
        end

        function handle = button(parent, position, text, callback, kind)
        %BUTTON A push button styled 'primary', 'neutral' or 'danger'.
            theme = vtseg.ReviewStyle.theme();
            switch kind
                case 'primary'
                    background = theme.primary;
                    foreground = [1 1 1];
                case 'danger'
                    background = theme.danger;
                    foreground = [1 1 1];
                otherwise
                    background = theme.neutral;
                    foreground = theme.text;
            end
            handle = uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
                'Position', position, 'String', text, 'Callback', callback, ...
                'BackgroundColor', background, 'ForegroundColor', foreground, ...
                'FontSize', theme.font_size, 'FontWeight', 'bold');
        end

        function handle = slider(parent, position, minimum, maximum, value, step, callback)
        %SLIDER A themed slider; step is the two-element SliderStep.
            theme = vtseg.ReviewStyle.theme();
            handle = uicontrol(parent, 'Style', 'slider', 'Units', 'normalized', ...
                'Position', position, 'Min', minimum, 'Max', maximum, ...
                'Value', value, 'SliderStep', step, ...
                'BackgroundColor', theme.field, 'Callback', callback);
        end

        function handle = toggle(parent, position, text, value, callback)
        %TOGGLE A themed toggle button.
            theme = vtseg.ReviewStyle.theme();
            handle = uicontrol(parent, 'Style', 'togglebutton', 'Units', 'normalized', ...
                'Position', position, 'String', text, 'Value', value, ...
                'BackgroundColor', theme.neutral, 'ForegroundColor', theme.text, ...
                'FontSize', theme.font_size, 'FontWeight', 'bold', ...
                'Callback', callback);
        end

        function handle = field(parent, position, text, callback)
        %FIELD A themed single-line edit field.
            theme = vtseg.ReviewStyle.theme();
            handle = uicontrol(parent, 'Style', 'edit', 'Units', 'normalized', ...
                'Position', position, 'String', text, ...
                'BackgroundColor', theme.field, 'ForegroundColor', theme.text, ...
                'FontSize', theme.font_size, 'Callback', callback);
        end

        function axesTitle(ax, text, varargin)
        %AXESTITLE Axes title in the theme; file names are shown verbatim.
        % Extra name-value pairs (for example 'FontSize', 8) override the
        % defaults because MATLAB applies the last value given.
            theme = vtseg.ReviewStyle.theme();
            title(ax, text, 'Interpreter', 'none', 'Color', theme.text, ...
                'FontSize', theme.font_size + 1, 'FontWeight', 'normal', varargin{:});
        end

        function figureTitle(target, text)
        %FIGURETITLE Overall title above a tiled layout or subplot grid.
            theme = vtseg.ReviewStyle.theme();
            sgtitle(target, text, 'Interpreter', 'none', 'Color', theme.text, ...
                'FontSize', theme.font_size + 2, 'FontWeight', 'bold');
        end

        function handle = colorbarFor(ax)
        %COLORBARFOR A colour bar whose ticks and labels are readable on the theme.
            theme = vtseg.ReviewStyle.theme();
            handle = colorbar(ax);
            set(handle, 'Color', theme.text);
        end

    end
end
