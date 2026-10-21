%% StatTesting.m
% Performs statistical testing across multiple groups.
% Each group corresponds to one CellTrackAnalysis_results.xlsx file.
% Reads a single column from the PerTrack_Metrics sheet of each file.

% Last updated: 10/20/2026
% By Clara Shin

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% % %%% % %%% % %%% % %%% % %%% % %%% % %%% % %%% % %%% % %%% % %%% % %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% MAIN PARAMETERS

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

test_type = 4;              % Statistical test to run:
                            %   1 = Two-sample KS test     (kstest2)       group_count = 2
                            %   2 = Kruskal-Wallis test    (kruskalwallis) group_count >= 2
                            %   3 = Two-sample t-test      (ttest2)        group_count = 2
                            %   4 = One-way ANOVA          (anova1)        group_count >= 2

group_count = 3;            % Number of groups (= number of Excel files to select).
                            % Ignored and overridden to 2 for test_type 1 and 3.
                            % Must be a positive integer >= 2.

excel_column_name = 'Tumbles_per_s';
                            % Column to read from the PerTrack_Metrics sheet.
                            % e.g. 'TumbleCount', 'Tumbles_per_s',
                            %      'MeanRunDuration_s', 'TrackDuration_s'

pooled = false;             % true or false
                            % false = one Excel file per group.
                            % true  = each group can contain multiple Excel files (e.g. several trials). 
                            % Add files for each group in a window and click Done

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% =========================================================
%  Validate parameters
%  =========================================================

if ~(islogical(pooled) && isscalar(pooled))
    error('pooled must be either true or false (logical).');
end

if ~isnumeric(test_type) || ~ismember(test_type, 1:5)
    error('test_type must be an integer from 1 to 5. Got: %g', test_type);
end

% test_type 1 (kstest2) and 3 (ttest2) are two-sample tests only
if ismember(test_type, [1, 3])
    if group_count ~= 2
        fprintf('Note: test_type %d requires exactly 2 groups. Overriding group_count to 2.\n', test_type);
    end
    group_count = 2;
else
    if ~isnumeric(group_count) || group_count < 2 || floor(group_count) ~= group_count
        error('group_count must be an integer >= 2. Got: %g', group_count);
    end
end
group_count = double(group_count);

test_names = {'Two-sample KS Test (kstest2)', ...
              'Kruskal-Wallis Test (kruskalwallis)', ...
              'Two-sample t-test (ttest2)', ...
              'One-way ANOVA (anova1)', ...
              'Two-way ANOVA (anova2)'};
fprintf('Test selected : %s\n', test_names{test_type});

%% =========================================================
%  Select files
%  =========================================================

file_paths  = cell(1, group_count);   % each entry is a cell array of file paths
group_names = cell(1, group_count);

for g = 1 : group_count
    group_names{g} = sprintf('Group%d', g);

    if pooled
        % Window with "Add file(s)" and "Done" buttons (see local function below)
        file_paths{g} = select_pooled_files(g, group_count);
    else
        [fname, fpath] = uigetfile('*.xlsx', ...
            sprintf('Select Excel file for Group %d of %d', g, group_count));

        if isequal(fname, 0)
            error('File selection cancelled for Group %d. Aborting.', g);
        end

        file_paths{g} = {fullfile(fpath, fname)};
    end
end

%% =========================================================
%  Read column from each file
%  =========================================================

groups = cell(1, group_count);

for g = 1 : group_count
    groups{g} = [];

    for f = 1 : numel(file_paths{g})
        try
            T = readtable(file_paths{g}{f}, 'Sheet', 'PerTrack_Metrics');
        catch ME
            error('Could not read sheet "PerTrack_Metrics" from file:\n  %s\nError: %s', ...
                file_paths{g}{f}, ME.message);
        end

        if ~ismember(excel_column_name, T.Properties.VariableNames)
            error('Column "%s" not found in PerTrack_Metrics sheet of:\n  %s\nAvailable columns: %s', ...
                excel_column_name, file_paths{g}{f}, ...
                strjoin(T.Properties.VariableNames, ', '));
        end

        col_data = T.(excel_column_name);
        col_data = col_data(isfinite(col_data));

        groups{g} = [groups{g}; col_data(:)];   % pool raw values across files
    end

    if isempty(groups{g})
        error('Column "%s" in Group %d contains no finite values after removing NaNs.', ...
            excel_column_name, g);
    end
end

%% =========================================================
%  Assign data matrix
%  =========================================================

for g = 1 : group_count
    assignin('base', group_names{g}, groups{g});
end

max_n      = max(cellfun(@numel, groups));
dataMatrix = NaN(max_n, group_count);
for g = 1 : group_count
    n = numel(groups{g});
    dataMatrix(1:n, g) = groups{g};
end

fprintf('\nData matrix built: %d rows x %d groups.\n', max_n, group_count);

%% =========================================================
%  Run selected statistical test
%  =========================================================

fprintf('\n--- %s ---\n', test_names{test_type});
fprintf('Column tested : %s\n', excel_column_name);
fprintf('Groups        : %s\n\n', strjoin(group_names, ', '));

p     = NaN;
tbl   = [];
stats = [];

switch test_type

    % ---------------------------------------------------------
    case 1   % kstest2 — two-sample Kolmogorov-Smirnov test
    % ---------------------------------------------------------
        [h, p, ks2stat] = kstest2(groups{1}, groups{2});
        fprintf('KS statistic  : %.6f\n', ks2stat);
        fprintf('p-value       : %.6f\n', p);
        fprintf('Reject H0     : %s\n', mat2str(logical(h)));

    % ---------------------------------------------------------
    case 2   % kruskalwallis
    % ---------------------------------------------------------
        [p, tbl, stats] = kruskalwallis(dataMatrix, group_names, 'on');
        fprintf('p-value       : %.6f\n', p);

        if p < 0.05 && group_count > 2
            fprintf('\n--- Post-hoc Multiple Comparisons (Dunn-Sidak) ---\n');
            figure('Units','inches', 'Position',[1 1 8 5], 'Color','white');
            multcompare(stats, 'CriticalValueType', 'dunn-sidak');
            title(sprintf('Multiple Comparisons — %s', excel_column_name), ...
                'FontSize', 13, 'FontWeight', 'bold');
        end

    % ---------------------------------------------------------
    case 3   % ttest2 — two-sample t-test
    % ---------------------------------------------------------
        [h, p, ci, ttstats] = ttest2(groups{1}, groups{2});
        fprintf('t-statistic   : %.6f\n', ttstats.tstat);
        fprintf('Degrees of f. : %d\n',   ttstats.df);
        fprintf('95%% CI        : [%.6f, %.6f]\n', ci(1), ci(2));
        fprintf('p-value       : %.6f\n', p);
        fprintf('Reject H0     : %s\n', mat2str(logical(h)));

    % ---------------------------------------------------------
    case 4   % anova1 — one-way ANOVA
    % ---------------------------------------------------------
        [p, tbl, stats] = anova1(dataMatrix, group_names, 'on');
        fprintf('p-value       : %.6f\n', p);

        if p < 0.05 && group_count > 2
            fprintf('\n--- Post-hoc Multiple Comparisons (Tukey-Kramer) ---\n');
            figure('Units','inches', 'Position',[1 1 8 5], 'Color','white');
            multcompare(stats);
            title(sprintf('Multiple Comparisons — %s', excel_column_name), ...
                'FontSize', 13, 'FontWeight', 'bold');
        end

end

%% =========================================================
%  Significance label (shared for all tests)
%  =========================================================

p_display = p(1);   % for anova2, report the column (group) p-value
if p_display < 0.001
    sig_str = '*** (p < 0.001)';
elseif p_display < 0.01
    sig_str = '** (p < 0.01)';
elseif p_display < 0.05
    sig_str = '* (p < 0.05)';
else
    sig_str = 'n.s. (p >= 0.05)';
end
fprintf('Significance  : %s\n\n', sig_str);

%% =========================================================
%  Summary statistics per group
%  =========================================================

if ~pooled
    fprintf('--- Summary Statistics: %s ---\n', excel_column_name);
    fprintf('%-12s  %6s  %10s  %10s  %10s  %10s\n', ...
        'Group', 'N', 'Mean', 'Median', 'Std', 'IQR');
    fprintf('%s\n', repmat('-', 1, 66));

    for g = 1 : group_count
        d = groups{g};
        fprintf('%-12s  %6d  %10.4f  %10.4f  %10.4f  %10.4f\n', ...
            group_names{g}, numel(d), mean(d), median(d), std(d), iqr(d));
    end
    fprintf('\n');
end

%% =========================================================
%  Pooled statistics per group (only when pooled = true)
%  =========================================================

if pooled
    fprintf('--- Pooled Statistics: %s ---\n', excel_column_name);
    fprintf('%-12s  %6s  %6s  %14s  %14s  %12s  %12s  %12s  %12s\n', ...
        'Group', 'Files', 'n', 'Pooled Mean', 'Pooled Median', ...
        'Pooled Std', 'Pooled IQR', 'Variance', 'SEM');
    fprintf('%s\n', repmat('-', 1, 118));

    for g = 1 : group_count
        d = groups{g};
        n = numel(d);
        if n > 1
            sd  = std(d);
            vr  = var(d);
            sem = sd / sqrt(n);
        else
            sd = NaN;  vr = NaN;  sem = NaN;
        end
        fprintf('%-12s  %6d  %6d  %14.4f  %14.4f  %12.4f  %12.4f  %12.4f  %12.4f\n', ...
            group_names{g}, numel(file_paths{g}), n, mean(d), median(d), ...
            sd, iqr(d), vr, sem);
    end
    fprintf('\n');
end

%% =========================================================
%  Local function: multi-file selection for one pooled group
%  =========================================================

function paths = select_pooled_files(g, group_count)
% Repeats: file picker (multi-select allowed) -> prompt showing the files

    persistent lastDir
    if isempty(lastDir) || ~isfolder(lastDir), lastDir = pwd; end

    ttl        = sprintf('Group %d of %d', g, group_count);
    paths      = {};
    batchSizes = [];     % number of files added by each pick (for Undo)

    while true
        [fn, fp] = uigetfile(fullfile(lastDir, '*.xlsx'), ...
            sprintf('%s: select Excel file(s)', ttl), 'MultiSelect', 'on');

        if ~isequal(fn, 0)
            if ischar(fn), fn = {fn}; end
            lastDir = fp;
            added = 0;
            for k = 1 : numel(fn)
                newp = fullfile(fp, fn{k});
                if ~ismember(newp, paths)
                    paths{end+1} = newp; 
                    added = added + 1;
                end
            end
            batchSizes(end+1) = added; 
        elseif isempty(paths)
            error('File selection cancelled for Group %d. Aborting.', g);
        end

        % ---- Prompt: add more, undo, or done ----
        names = cell(1, numel(paths));
        for k = 1 : numel(paths)
            [~, nm, ext] = fileparts(paths{k});
            names{k} = [nm ext];
        end
        maxShow = 12;
        if numel(names) > maxShow
            shown = [names(1:maxShow), {sprintf('... and %d more', numel(names) - maxShow)}];
        else
            shown = names;
        end
        msg = [{sprintf('%s: %d file(s) selected so far:', ttl, numel(paths)); ''}; ...
               shown(:); {''; 'Add more files for this group, or click Done.'}];

        choice = questdlg(msg, ttl, 'Add more files', 'Undo last add', 'Done', 'Add more files');

        switch choice
            case 'Done'
                if isempty(paths)
                    warndlg(sprintf('Please add at least one file for Group %d.', g), ...
                        'No files selected');
                else
                    return;
                end
            case 'Undo last add'
                if ~isempty(batchSizes)
                    paths(end - batchSizes(end) + 1 : end) = [];
                    batchSizes(end) = [];
                end
            case 'Add more files'
                % loop again
            otherwise   % dialog closed with the X
                error('File selection cancelled for Group %d. Aborting.', g);
        end
    end
end