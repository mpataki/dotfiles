return {
	'nvim-telescope/telescope.nvim',
	dependencies = {
		{ 'nvim-lua/plenary.nvim' },
		{ 'nvim-telescope/telescope-ui-select.nvim' },
	},
	cmd = 'TSUpdate',
	config = function()
		local telescope = require('telescope')
		local actions = require("telescope.actions")
		local builtin = require('telescope.builtin')
		local entry_display = require('telescope.pickers.entry_display')

		local git_icons = {
			A = { '✚', 'diffAdded' },
			M = { '●', 'DiagnosticWarn' },
			D = { '✖', 'diffRemoved' },
			R = { '➜', 'DiagnosticInfo' },
			C = { '⊕', 'diffAdded' },
			T = { '◆', 'DiagnosticWarn' },
			['?'] = { '?', 'DiagnosticWarn' },
		}

		local git_displayer = entry_display.create({
			separator = ' ',
			items = {
				{ width = 2 },
				{ remaining = true },
			},
		})

		local pr_displayer = entry_display.create({
			separator = ' ',
			items = {
				{ width = 2 },
				{ remaining = true },
				{ width = 8, right_justify = true },
				{ width = 5 },
			},
		})

		telescope.setup({
			defaults = {
				layout_strategy = 'vertical',
				layout_config = {
					vertical = {
						preview_cutoff = 10,
						preview_height = 0.5,
						width = 0.95,
						height = 0.95,
					},
				},
				mappings = {
					i = {
						["<esc>"] = actions.close
					}
				},
			},
			pickers = {
				find_files = {
					hidden = true,
					find_command = { "fd", "--type", "f", "--hidden", "--exclude", ".git" },
					path_display = {"smart"},
					layout_strategy = "vertical",
				},
				buffers = {
					path_display = {"smart"},
					layout_strategy = "vertical",
				},
				live_grep = {
					additional_args = { "--hidden", "--glob", "!.git/**" },
					path_display = {"smart"},
					layout_strategy = "vertical",
				},
			},
			extensions = {
				['ui-select'] = {
					require('telescope.themes').get_dropdown({})
				}
			}
		})

		telescope.load_extension("ui-select")

		-- vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
		-- vim.keymap.set('n', '<C-p>', builtin.git_files, {})
		vim.keymap.set('n', '<C-p>', builtin.find_files, {})
		-- vim.keymap.set('n', '<leader>ps', function()
		--     builtin.grep_string({ search = vim.fn.input("Grep > ") });
		-- end)

		vim.keymap.set('n', '<leader>b', function()
			builtin.buffers();
		end)

		vim.keymap.set('n', '<leader>ps', builtin.live_grep, {})

		-- Git diff picker (1/2) — see also git_pr_files below. Extract at 3.
		local function git_status_files()
			local pickers = require('telescope.pickers')
			local finders = require('telescope.finders')
			local conf = require('telescope.config').values
			local previewers = require('telescope.previewers')

			-- Fetch line stats
			local numstat = {}
			local stat_lines = vim.fn.systemlist({ 'git', 'diff', '--numstat', 'HEAD' })
			for _, sl in ipairs(stat_lines) do
				local add, del, file = sl:match("^(%d+)\t(%d+)\t(.+)$")
				if add and file then
					numstat[file] = { add = tonumber(add), del = tonumber(del) }
				end
			end

			local output = vim.fn.systemlist({ 'git', 'status', '--porcelain' })
			local results = {}
			for _, line in ipairs(output) do
				local xy = line:sub(1, 2)
				local file = line:sub(4)
				local x, y = xy:sub(1, 1), xy:sub(2, 2)
				local char = xy == '??' and '?' or (x ~= ' ' and x or y)
				table.insert(results, { status = char, file = file })
			end

			local total_add, total_del = 0, 0
			for _, s in pairs(numstat) do
				total_add = total_add + s.add
				total_del = total_del + s.del
			end

			pickers.new({
				layout_config = { preview_height = 0.7 },
			}, {
				prompt_title = "Git Status  +" .. total_add .. "/-" .. total_del,
				finder = finders.new_table({
					results = results,
					entry_maker = function(entry)
						local info = git_icons[entry.status] or { entry.status, 'Comment' }
						local stats = numstat[entry.file] or { add = 0, del = 0 }
						return {
							value = entry,
							display = function()
								return pr_displayer({
									{ info[1], info[2] },
									{ entry.file, info[2] },
									{ '+' .. stats.add, 'diffAdded' },
									{ '/-' .. stats.del, 'diffRemoved' },
								})
							end,
							ordinal = entry.file,
							path = entry.file,
						}
					end,
				}),
				previewer = previewers.new_termopen_previewer({
					get_command = function(entry)
						return { 'bash', '-c', 'git diff --no-color HEAD -- '
							.. vim.fn.shellescape(entry.value.file)
							.. ' | delta --no-gitconfig --dark --width=${COLUMNS:-80} --hunk-header-style=omit; cat' }
					end,
				}),
				sorter = conf.generic_sorter({}),
			}):find()
		end

		-- Git diff picker (2/2) — see also git_status_files above. Extract at 3.
		local function git_pr_files()
			local pickers = require('telescope.pickers')
			local finders = require('telescope.finders')
			local conf = require('telescope.config').values
			local previewers = require('telescope.previewers')

			local base = vim.fn.system("git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
			if base == "" then
				vim.notify("Could not find merge base", vim.log.levels.ERROR)
				return
			end

			vim.cmd('DiffPRBase')

			-- Fetch line stats per file
			local numstat = {}
			local stat_lines = vim.fn.systemlist({ 'git', 'diff', '--numstat', base .. '...HEAD' })
			for _, sl in ipairs(stat_lines) do
				local add, del, file = sl:match("^(%d+)\t(%d+)\t(.+)$")
				if add and file then
					-- Renames: "prefix/{old => new}/suffix" → "prefix/new/suffix"
					local prefix, new_part, suffix = file:match("^(.-){.- => (.-)}(.*)$")
					if prefix then
						file = prefix .. new_part .. suffix
					end
					numstat[file] = { add = tonumber(add), del = tonumber(del) }
				end
			end

			local output = vim.fn.systemlist({ 'git', 'diff', '--name-status', base .. '...HEAD' })
			if vim.v.shell_error ~= 0 then
				vim.notify("git diff failed", vim.log.levels.ERROR)
				return
			end

			local results = {}
			for _, line in ipairs(output) do
				local status, rest = line:match("^(%S+)\t(.+)$")
				if not status then
					status, rest = line:match("^(%S+)%s+(.+)$")
				end
				if status and rest then
					if status:sub(1, 1) == 'R' or status:sub(1, 1) == 'C' then
						local old_file, new_file = rest:match("^(.-)\t(.+)$")
						if not old_file then
							old_file, new_file = rest:match("^(.-)%s+(%S+)$")
						end
						table.insert(results, { status = status:sub(1, 1), file = new_file, old_file = old_file })
					else
						table.insert(results, { status = status, file = rest })
					end
				end
			end

			local total_add, total_del = 0, 0
			for _, s in pairs(numstat) do
				total_add = total_add + s.add
				total_del = total_del + s.del
			end

			pickers.new({
				layout_config = { preview_height = 0.7 },
			}, {
				prompt_title = "PR Files (vs " .. base:sub(1, 8) .. ")  +" .. total_add .. "/-" .. total_del,
				finder = finders.new_table({
					results = results,
					entry_maker = function(entry)
						local info = git_icons[entry.status] or { entry.status, 'Comment' }
						local file_label = entry.old_file
							and (entry.old_file .. ' → ' .. entry.file)
							or entry.file
						local stats = numstat[entry.file] or { add = 0, del = 0 }
						return {
							value = entry,
							display = function()
								return pr_displayer({
									{ info[1], info[2] },
									{ file_label, info[2] },
									{ '+' .. stats.add, 'diffAdded' },
									{ '/-' .. stats.del, 'diffRemoved' },
								})
							end,
							ordinal = entry.file,
							path = entry.file,
						}
					end,
				}),
				previewer = previewers.new_termopen_previewer({
					get_command = function(entry)
						local paths = entry.value.old_file
							and (vim.fn.shellescape(entry.value.old_file) .. ' ' .. vim.fn.shellescape(entry.value.file))
							or vim.fn.shellescape(entry.value.file)
						return { 'bash', '-c', 'git diff --no-color ' .. base .. '...HEAD -- ' .. paths
							.. ' | delta --no-gitconfig --dark --width=${COLUMNS:-80} --hunk-header-style=omit; cat' }
					end,
				}),
				sorter = conf.generic_sorter({}),
			}):find()
		end

		vim.keymap.set('n', '<leader>gs', git_status_files, { desc = 'Git status (HEAD)' })
		vim.keymap.set('n', '<leader>gS', git_pr_files, { desc = 'Git status (PR base)' })
	end
}
