-- Review view driven by the `review-view` Claude skill; the state layout is documented in review.sh.
-- Notes render as virtual lines and unchanged stretches fold, so line numbers stay true.
-- Past tasks show read-only `gitsigns://<gitdir>//<rev>:<path>` buffers instead of the real files.

local M = {}

local SCRIPT = vim.fn.expand("~/.claude/skills/review-view/review.sh")
local ns = vim.api.nvim_create_namespace("review_notes")
local panel_ns = vim.api.nvim_create_namespace("review_panel")
local ICON = { pending = "◌", working = "●", ready = "◆", responding = "✎", deferred = "⏸", reviewed = "✓" }
local STATUS_HL = {
    pending = "Comment",
    working = "DiagnosticWarn",
    ready = "DiagnosticInfo",
    responding = "DiagnosticHint",
    deferred = "Comment",
    reviewed = "DiagnosticOk",
}

local state = {
    dir = nil, root = nil, meta = nil, plan = "", tasks = {}, notes = {}, group = nil,
    enabled = true, watcher = nil, panel = nil, rows = {},
}
vim.g.review_context = vim.g.review_context or 3
-- Which companion pane is on the right; cached briefly because selections fire often.
local visible = { pane = nil, at = 0 }
vim.g.review_tree_width = vim.g.review_tree_width or 40

-- Set when the review opens and on every colorscheme change, which would otherwise clear them.
local function set_highlights()
    vim.api.nvim_set_hl(0, "ReviewNote", { default = true, link = "DiagnosticVirtualTextInfo" })
    vim.api.nvim_set_hl(0, "ReviewRead", {
        default = true, strikethrough = true, fg = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg,
    })
end

local function read_json(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    return ok and data or nil
end

local function git(args)
    local out = vim.fn.systemlist(vim.list_extend({ "git" }, args))
    return vim.v.shell_error == 0 and out[1] or nil
end

local function script(args, on_done)
    vim.system(vim.list_extend({ SCRIPT }, args), { cwd = state.root, text = true }, function(res)
        if res.code ~= 0 then
            vim.schedule(function()
                vim.api.nvim_echo({ { "review: " .. vim.trim(res.stderr or ""), "WarningMsg" } }, false, {})
            end)
        elseif on_done then
            vim.schedule(on_done)
        end
    end)
end

--- @return string? path repo-relative path
--- @return string? rev set for gitsigns revision buffers
local function rel_path(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" or not state.root then return nil end
    local rev, p = name:match("^gitsigns://.-//([^:]*):(.+)$")
    if p then return p, rev end
    name = vim.fn.fnamemodify(name, ":p")
    if name:sub(1, #state.root + 1) ~= state.root .. "/" then return nil end
    return name:sub(#state.root + 2)
end

-- Prefer the line holding `anchor` nearest the recorded line, so notes survive small edits.
local function resolve_line(lines, note)
    local line = math.max(1, math.min(note.line or 1, #lines))
    if not note.anchor or note.anchor == "" then return line end
    if lines[line] and lines[line]:find(note.anchor, 1, true) then return line end
    for d = 1, #lines do
        for _, l in ipairs({ line - d, line + d }) do
            if lines[l] and lines[l]:find(note.anchor, 1, true) then return l end
        end
    end
    return line
end

local function render(buf)
    if not vim.api.nvim_buf_is_loaded(buf) then return end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local path = rel_path(buf)
    if not state.enabled or not path then return end

    local task = state.group and state.group.task
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cs = vim.bo[buf].commentstring
    local prefix = vim.trim(cs ~= "" and cs:match("^(.-)%%s") or "//") .. " "
    for _, note in ipairs(state.notes) do
        if note.file == path and (not task or not note.task or note.task == task) then
            local lnum = resolve_line(lines, note)
            local indent = (lines[lnum] or ""):match("^%s*")
            local virt = {}
            for i, chunk in ipairs(vim.split(note.text, "\n", { trimempty = true })) do
                local label = i == 1 and "REVIEW: " or "        "
                table.insert(virt, { { indent .. prefix .. label .. chunk, "ReviewNote" } })
            end
            note._lnum = lnum
            vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, { virt_lines = virt, virt_lines_above = true })
        end
    end
end

local function pathspec()
    local spec = { "." }
    for _, p in ipairs(state.meta.exclude or {}) do table.insert(spec, ":(exclude,glob)" .. p) end
    return spec
end

local function diff_args(g, extra)
    local args = vim.list_extend({ "git", "-C", state.root, "diff" }, extra)
    table.insert(args, g.from)
    if g.to then table.insert(args, g.to) end
    table.insert(args, "--")
    return args
end

-- New-side line ranges changed in the current group; nil when git has no diff (untracked or unchanged).
local function changed_ranges(path)
    local args = diff_args(state.group, { "-U0", "--no-color", "--no-ext-diff" })
    table.insert(args, path)
    local out = vim.fn.systemlist(args)
    if vim.v.shell_error ~= 0 or #out == 0 then return nil end
    local ranges = {}
    for _, l in ipairs(out) do
        local s, c = l:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
        if s then
            s, c = tonumber(s), c == "" and 1 or tonumber(c)
            -- A pure deletion (count 0) sits after line s; keep that spot visible.
            table.insert(ranges, c == 0 and { math.max(s, 1), math.max(s, 1) } or { s, s + c - 1 })
        end
    end
    return ranges
end

local function fold(buf, win)
    local path, rev = rel_path(buf)
    if not path or not state.group or not vim.api.nvim_win_is_valid(win) then return end
    if vim.t[vim.api.nvim_win_get_tabpage(win)].review_plain then return end
    -- Past tasks fold revision buffers only; working-tree groups fold real files only.
    if (state.group.to ~= nil) ~= (rev ~= nil) then return end
    local ranges = changed_ranges(path)
    if not ranges then return end
    local ctx, last = vim.g.review_context, vim.api.nvim_buf_line_count(buf)

    vim.wo[win][0].foldmethod = "manual"
    vim.wo[win][0].foldenable = true
    vim.wo[win][0].foldtext = "v:lua.require'mattc.review'.foldtext()"
    vim.wo[win][0].fillchars = "fold: "
    vim.api.nvim_win_call(win, function()
        vim.cmd("silent! normal! zE")
        local from = 1
        local function gap(to)
            if to - from >= 1 then vim.cmd(("%d,%dfold"):format(from, to)) end
        end
        for _, r in ipairs(ranges) do
            gap(r[1] - ctx - 1)
            from = math.max(from, r[2] + ctx + 1)
        end
        gap(last)
        vim.cmd("silent! normal! zM")
    end)
end

function M.foldtext()
    local n = vim.v.foldend - vim.v.foldstart + 1
    return ("    ··· %d unchanged lines · zo to expand ···"):format(n)
end

local function refold_all()
    for _, win in ipairs(vim.api.nvim_list_wins()) do fold(vim.api.nvim_win_get_buf(win), win) end
end

local function render_all()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do render(buf) end
end

-- Groups --------------------------------------------------------------------

local function all_group()
    return { title = "All changes", from = state.meta.base, files = state.meta.files }
end

-- `built` is the task's latest commit when the group was made; a newer one means a fix landed.
local function task_group(t, r)
    local suffix = r.label == "task" and "" or (" · " .. r.label)
    local ranges = t.ranges or {}
    return {
        title = ("%d. %s%s"):format(t.id, t.title, suffix), task = t.id, from = r.from, to = r.to,
        built = (ranges[#ranges] or r).to,
    }
end

-- The whole task with its fixes folded in, as the squash will leave it; a fix row still opens
-- just that fix. `key` stays the same across fixes, so read marks carry over.
local function task_whole(t)
    local ranges = t.ranges or {}
    if #ranges <= 1 then
        local g = ranges[1] and task_group(t, ranges[1])
        if g then g.key = "task" .. t.id end
        return g
    end
    local out = vim.fn.systemlist({ SCRIPT, "task-view", tostring(t.id) })
    local from, to = (out[#out] or ""):match("^(%x+) (%x+)$")
    if vim.v.shell_error ~= 0 or not from then
        vim.api.nvim_echo({ { ("review: task %d's fixes don't replay onto it; showing the latest fix"):format(t.id), "WarningMsg" } }, false, {})
        return task_group(t, ranges[#ranges])
    end
    local fixes = #ranges - 1
    return {
        title = ("%d. %s (with %d fix%s)"):format(t.id, t.title, fixes, fixes == 1 and "" or "es"),
        task = t.id, from = from, to = to, key = "task" .. t.id, built = ranges[#ranges].to,
    }
end

local function list_groups()
    local groups = { all_group() }
    for _, t in ipairs(state.tasks) do
        local whole = task_whole(t)
        if whole then table.insert(groups, whole) end
        for i, r in ipairs(t.ranges or {}) do
            if i > 1 then table.insert(groups, task_group(t, r)) end
        end
    end
    return groups
end

local function group_files(g)
    if g.files then return g.files end
    local files = {}
    for _, l in ipairs(vim.fn.systemlist(vim.list_extend(diff_args(g, { "--name-status", "--no-renames" }), pathspec()))) do
        local status, path = l:match("^(%a)%s+(.+)$")
        -- Against the working tree, a snapshot's untracked files read as deleted; only real deletions count.
        if path and not (status == "D" and not g.to and vim.uv.fs_stat(state.root .. "/" .. path)) then
            table.insert(files, path)
        end
    end
    return files
end

local function find_task(id)
    for _, t in ipairs(state.tasks) do
        if t.id == id then return t end
    end
end

-- Task panel ----------------------------------------------------------------

local open_group

local TOP_HEIGHT = 6

local function render_summary()
    local b = state.summary
    if not b or not vim.api.nvim_buf_is_valid(b) then return end
    local g = state.group or {}
    local t = g.task and find_task(g.task)
    local title, body
    if t then
        title = ("%s %s  ·  %s"):format(ICON[t.status] or "", g.title, t.status)
        body = t.summary or "(no summary yet)"
    else
        title = (state.plan ~= "" and state.plan or "Review") .. (state.meta.squashed and "  (squashed)" or "")
        body = state.plan_summary or ""
    end
    local lines = { title }
    vim.list_extend(lines, vim.split(body, "\n", { trimempty = true }))
    vim.bo[b].modifiable = true
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    vim.api.nvim_buf_clear_namespace(b, panel_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(b, panel_ns, 0, 0, { end_col = #lines[1], hl_group = "Title" })
end

local function render_panel()
    render_summary()
    local b = state.panel
    if not b or not vim.api.nvim_buf_is_valid(b) then return end
    local lines, marks = {}, {}
    state.rows = {}
    local function row(text, entry, icon_col, icon, hl)
        table.insert(lines, text)
        state.rows[#lines] = entry
        if icon then table.insert(marks, { #lines - 1, icon_col, icon_col + #icon, hl }) end
    end

    local cur = state.group or {}
    row((cur.task == nil and cur.title and "▸" or " ") .. "   All changes", { group = all_group() })
    for _, t in ipairs(state.tasks) do
        local lead = (cur.task == t.id and "▸" or " ") .. " "
        local icon = ICON[t.status] or "?"
        local text = ("%s%s %d %s"):format(lead, icon, t.id, t.title)
        local first = (t.ranges or {})[1]
        row(text .. (first and ("  " .. first.to:sub(1, 7)) or ""), { task = t }, #lead, icon, STATUS_HL[t.status])
        if first then table.insert(marks, { #lines - 1, #text + 2, #text + 9, "Comment" }) end
        for i, r in ipairs(t.ranges or {}) do
            if i > 1 then
                local fix = "      · " .. r.label
                row(fix .. "  " .. r.to:sub(1, 7), { task = t, range = r })
                table.insert(marks, { #lines - 1, #fix + 2, #fix + 9, "Comment" })
            end
        end
    end

    vim.bo[b].modifiable = true
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    vim.api.nvim_buf_clear_namespace(b, panel_ns, 0, -1)
    for _, m in ipairs(marks) do
        vim.api.nvim_buf_set_extmark(b, panel_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end
end

local function row_under_cursor()
    return state.rows[vim.api.nvim_win_get_cursor(0)[1]]
end

local function open_row()
    local r = row_under_cursor()
    if not r then return end
    if r.group then return open_group(r.group) end
    local g = r.range and task_group(r.task, r.range) or task_whole(r.task)
    if not g then
        return vim.api.nvim_echo({ { ("task %d has no commit yet"):format(r.task.id), "Comment" } }, false, {})
    end
    open_group(g)
end

local function approve(id)
    if id then script({ "status", tostring(id), "reviewed" }) end
end

local function scratch(name, ft)
    -- A reloaded module would otherwise collide with the previous load's buffer names.
    local old = vim.fn.bufnr(name)
    if old ~= -1 then vim.api.nvim_buf_delete(old, { force = true }) end
    local b = vim.api.nvim_create_buf(false, true)
    vim.bo[b].bufhidden = "hide"
    vim.bo[b].filetype = ft
    vim.api.nvim_buf_set_name(b, name)
    return b
end

local function panel_buf()
    if state.panel and vim.api.nvim_buf_is_valid(state.panel) then return state.panel end
    local b = scratch("review://tasks", "reviewtasks")
    vim.keymap.set("n", "<CR>", open_row, { buffer = b, desc = "Open task" })
    vim.keymap.set("n", "a", function()
        local r = row_under_cursor()
        approve(r and r.task and r.task.id)
    end, { buffer = b, desc = "Mark task reviewed" })
    state.panel = b
    return b
end

local function summary_buf()
    if state.summary and vim.api.nvim_buf_is_valid(state.summary) then return state.summary end
    state.summary = scratch("review://summary", "markdown")
    return state.summary
end

-- Top row across the whole of nvim: task list | summary. gitsigns' tree and file pane sit below.
local function show_panel()
    local list_buf, sum_buf = panel_buf(), summary_buf()
    if #vim.fn.win_findbuf(list_buf) > 0 then return render_panel() end
    local tree
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):match("^gitsigns%-diff://") then tree = win end
    end
    local origin = vim.api.nvim_get_current_win()

    vim.cmd(("topleft %dsplit"):format(TOP_HEIGHT))
    local list = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(list, list_buf)
    vim.cmd("rightbelow vsplit")
    local sum = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(sum, sum_buf)

    for _, win in ipairs({ list, sum }) do
        for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", winfixheight = true }) do
            vim.wo[win][0][opt] = val
        end
    end
    vim.wo[list][0].cursorline = true
    vim.wo[sum][0].wrap, vim.wo[sum][0].linebreak = true, true
    vim.api.nvim_win_set_width(list, math.max(30, math.floor(vim.o.columns * 0.4)))
    vim.api.nvim_win_set_height(list, TOP_HEIGHT)
    if tree then
        vim.api.nvim_win_set_width(tree, vim.g.review_tree_width)
        vim.wo[tree][0].winfixwidth = true
    end
    if vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
    render_panel()
end

function open_group(g, restore)
    local files = group_files(g)
    -- gitsigns reuses only a lone empty tab; anything else gets a new tab and the old view lingers.
    vim.cmd.tabnew()
    vim.cmd("silent! tabonly")
    state.group = g
    if g.task then script({ "companion", tostring(g.task) }, function() visible.at = 0 end) end
    if #files == 0 then return show_panel() end
    -- An explicit list keeps unrelated untracked files (scratch plans, notes) out of the tree.
    local paths = vim.tbl_map(function(p) return ":(top,literal)" .. p end, files)
    require("gitsigns").diff(g.to and (g.from .. ".." .. g.to) or g.from, paths, { diff = "unified" },
        function()
            vim.schedule(function()
                show_panel()
                M.draw_tree_marks()
                if restore then M.restore_position(restore) end
            end)
        end)
end

-- Opens the next (dir 1) or previous (-1) task that has a commit, at its latest range.
local function step_task(dir)
    local ready = vim.tbl_filter(function(t) return #(t.ranges or {}) > 0 end, state.tasks)
    if #ready == 0 then
        return vim.api.nvim_echo({ { "review: no task has a commit yet", "Comment" } }, false, {})
    end
    local cur = state.group and state.group.task
    local pick
    if not cur then
        pick = dir > 0 and ready[1] or ready[#ready]
    else
        for i = dir > 0 and 1 or #ready, dir > 0 and #ready or 1, dir do
            if (dir > 0 and ready[i].id > cur) or (dir < 0 and ready[i].id < cur) then pick = ready[i] break end
        end
    end
    if not pick then
        return vim.api.nvim_echo({ { ("review: no %s task"):format(dir > 0 and "next" or "previous"), "Comment" } }, false, {})
    end
    open_group(task_whole(pick))
end

local function pick_group()
    vim.ui.select(list_groups(), {
        prompt = "Review group",
        format_item = function(g)
            local t = g.task and find_task(g.task)
            local icon = t and ICON[t.status] or " "
            return ("%s %s %s"):format(state.group and g.title == state.group.title and "▸" or " ", icon, g.title)
        end,
    }, function(g) if g then open_group(g) end end)
end

-- Sends `path:lines` to the visible task companion and focuses it, ready for the question.
local function send_selection()
    local s, e = vim.fn.line("v"), vim.fn.line(".")
    if s > e then s, e = e, s end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    local path, rev = rel_path(0)
    if not path then return end
    local ref = s == e and ("%s:%d"):format(path, s) or ("%s:%d-%d"):format(path, s, e)
    if rev then ref = ref .. (" (task snapshot %s)"):format(rev:sub(1, 8)) end
    local pane
    for _, l in ipairs(vim.fn.systemlist({ "tmux", "list-panes", "-t", state.meta.window or "", "-F", "#{pane_id} #{@review_task}" })) do
        if l:match("^%S+ %S+$") then pane = l:match("^%S+") break end
    end
    if not pane then
        return vim.api.nvim_echo({ { "review: open a task first; no companion is showing", "WarningMsg" } }, false, {})
    end
    vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", ref .. " " })
    vim.fn.system({ "tmux", "select-pane", "-t", pane })
end

-- State ---------------------------------------------------------------------

local function load_state()
    state.meta = read_json(state.dir .. "/meta.json") or state.meta
    local t = read_json(state.dir .. "/tasks.json") or {}
    state.plan, state.plan_summary, state.tasks = t.plan or "", t.summary, t.tasks or {}
    state.notes = (read_json(state.dir .. "/notes.json") or {}).notes or {}
    render_all()
    render_panel()
    if M.refresh_open_task then M.refresh_open_task() end
end

local function watch()
    if state.watcher then state.watcher:stop() end
    state.watcher = vim.uv.new_fs_event()
    local timer = vim.uv.new_timer()
    local watched = { ["meta.json"] = true, ["tasks.json"] = true, ["notes.json"] = true }
    -- Watch the directory: the script replaces files with mv, which would orphan a file watch.
    state.watcher:start(state.dir, {}, function(_, fname)
        if watched[fname] then timer:start(100, 0, vim.schedule_wrap(load_state)) end
    end)
end

-- Opens the working-tree file in a plain tab; from a past task, at the same line as it reads now.
local function open_real_file()
    local path, rev = rel_path(0)
    if not path then return end
    local full = state.root .. "/" .. path
    if not vim.uv.fs_stat(full) then
        return vim.api.nvim_echo({ { "review: " .. path .. " no longer exists", "WarningMsg" } }, false, {})
    end
    local lnum, text = vim.api.nvim_win_get_cursor(0)[1], vim.trim(vim.api.nvim_get_current_line())
    vim.cmd("tabnew")
    vim.t.review_plain = true
    vim.cmd.edit(vim.fn.fnameescape(full))
    -- Neovim restores folds from the last window that showed this buffer; a plain tab wants none.
    vim.cmd("silent! normal! zE")
    vim.wo[0][0].foldenable = false
    if rev then lnum = resolve_line(vim.api.nvim_buf_get_lines(0, 0, -1, false), { line = lnum, anchor = text }) end
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    vim.cmd("normal! zz")
end

-- Read marks ------------------------------------------------------------------
-- Kept per diff in read.json, so a task's fix starts unread. gitsigns keeps its tree rows on a
-- private panel object; it's reached through the tree's <CR> keymap, and its render is wrapped
-- so the strikethrough survives redraws. If that lookup fails, marks are saved but not drawn.

local read_ns = vim.api.nvim_create_namespace("review_read")

local function group_key(g)
    return g.key or (g.from .. ".." .. (g.to or "worktree"))
end

local function read_set()
    local all = read_json(state.dir .. "/read.json") or {}
    return all, all[group_key(state.group)] or {}
end

-- Blob id of each path on the group's new side: what a read mark remembers, so a fix that
-- changes the file clears the mark and one that doesn't leaves it.
local function blob_ids(g, paths)
    local ids = {}
    if #paths == 0 then return ids end
    if g.to then
        for _, l in ipairs(vim.fn.systemlist(vim.list_extend({ "git", "-C", state.root, "ls-tree", g.to, "--" }, paths))) do
            local id, p = l:match("^%d+ %a+ (%x+)\t(.+)$")
            if id then ids[p] = id end
        end
    else
        local present = vim.tbl_filter(function(p) return vim.uv.fs_stat(state.root .. "/" .. p) ~= nil end, paths)
        if #present == 0 then return ids end
        local out = vim.fn.systemlist(vim.list_extend({ "git", "-C", state.root, "hash-object", "--" }, present))
        for i, p in ipairs(present) do ids[p] = out[i] end
    end
    return ids
end

local read_cache = {}

-- Paths still read in the open group: marked, and unchanged since.
local function valid_read()
    local g = state.group
    local stamp = group_key(g) .. "|" .. (g.to or "")
    -- Commits never change, so their result keeps; the working tree can change at any time.
    if g.to and read_cache.stamp == stamp then return read_cache.set end
    local _, read = read_set()
    local ids, set = blob_ids(g, vim.tbl_keys(read)), {}
    for p, id in pairs(read) do
        if id == true or ids[p] == id then set[p] = true end
    end
    read_cache = { stamp = stamp, set = set }
    return set
end

local function tree_panel(buf)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if m.lhs == "<CR>" and m.callback then
            for i = 1, 20 do
                local name, v = debug.getupvalue(m.callback, i)
                if not name then break end
                if type(v) == "table" and v.rows and v.buf == buf then return v end
            end
        end
    end
end

local function draw_read(panel)
    if not state.group or not vim.api.nvim_buf_is_valid(panel.buf) then return end
    local read = valid_read()
    local count = vim.api.nvim_buf_line_count(panel.buf)
    vim.api.nvim_buf_clear_namespace(panel.buf, read_ns, 0, -1)
    for lnum, node in pairs(panel.rows) do
        if not node.directory and read[node.path] then
            -- Long names wrap onto rows that aren't in `rows`; strike those too.
            local last = lnum
            while last < count and not panel.rows[last + 1]
                and vim.trim(vim.api.nvim_buf_get_lines(panel.buf, last, last + 1, false)[1] or "") ~= "" do
                last = last + 1
            end
            vim.api.nvim_buf_set_extmark(panel.buf, read_ns, lnum - 1, 0,
                { end_row = last, end_col = 0, hl_group = "ReviewRead", priority = 200 })
        end
    end
end

local function hook_tree(panel)
    local mt = getmetatable(panel)
    if mt and not mt._review_read then
        local render = mt.render
        mt.render = function(self, ...)
            local r = render(self, ...)
            pcall(draw_read, self)
            return r
        end
        mt._review_read = true
    end
    draw_read(panel)
end

local function current_tree()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf):match("^gitsigns%-diff://") then return buf, win end
    end
end

local toggle_read

function M.draw_tree_marks()
    local tree = current_tree()
    local panel = tree and tree_panel(tree)
    if not panel then return end
    hook_tree(panel)
    vim.keymap.set("n", "r", toggle_read, { buffer = tree, desc = "Toggle file read" })
end

function toggle_read()
    if not state.group then return end
    local tree, tree_win = current_tree()
    local panel = tree and tree_panel(tree)
    local path
    if panel and vim.api.nvim_get_current_win() == tree_win then
        local node = panel.rows[vim.api.nvim_win_get_cursor(tree_win)[1]]
        path = node and not node.directory and node.path
    else
        path = rel_path(0)
    end
    if not path then return end
    local all, read = read_set()
    if valid_read()[path] then
        read[path] = nil
    else
        read[path] = blob_ids(state.group, { path })[path] or true
    end
    all[group_key(state.group)] = next(read) and read or nil
    read_cache = {}
    local f = io.open(state.dir .. "/read.json", "w")
    if f then
        f:write(vim.json.encode(all))
        f:close()
    end
    if panel then hook_tree(panel) end
end

local function file_pane()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
        if not name:match("^gitsigns%-diff://") and not name:match("^review://") then return win end
    end
end

-- After a rebuild: back to the same file, and the same line as it reads now.
function M.restore_position(r)
    local tree = current_tree()
    local panel = tree and tree_panel(tree)
    if not panel then return end
    for i, lnum in ipairs(panel.file_lnums) do
        local node = panel.rows[lnum]
        if node and node.path == r.path then
            if i ~= panel.current_file then panel:navigate(i - panel.current_file) end
            break
        end
    end
    vim.defer_fn(function()
        local pane = file_pane()
        if not pane then return end
        vim.api.nvim_set_current_win(pane)
        local buf = vim.api.nvim_win_get_buf(pane)
        local lnum = resolve_line(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { line = r.line, anchor = r.text })
        pcall(vim.api.nvim_win_set_cursor, pane, { lnum, 0 })
        vim.cmd("normal! zvzz")
    end, 150)
end

-- When a fix lands on the task on screen, rebuild it in place. Other tasks need nothing: they're
-- built fresh whenever they're opened. A plain tab is left alone until the user comes back.
function M.refresh_open_task()
    local g = state.group
    if not g or not g.task or not g.built or vim.t.review_plain then return end
    local t = find_task(g.task)
    local last = t and t.ranges and t.ranges[#t.ranges]
    if not last or last.to == g.built then return end
    -- The rebuild opens a tab, which re-enters here through TabEnter; this makes that a no-op.
    g.built = last.to
    local restore
    local pane = file_pane()
    if pane then
        local path = rel_path(vim.api.nvim_win_get_buf(pane))
        local cursor = vim.api.nvim_win_get_cursor(pane)[1]
        local text = vim.trim(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(pane), cursor - 1, cursor, false)[1] or "")
        if path then restore = { path = path, line = cursor, text = text } end
    end
    open_group(task_whole(t), restore)
    vim.api.nvim_echo({ { ("review: task %d updated (%s)"):format(t.id, last.label), "Comment" } }, false, {})
end

-- IDE selection routing ------------------------------------------------------
-- claudecode.nvim broadcasts selections to every connected Claude, parked companions included.
-- Each connection is traced to its tmux pane (peer port → lsof → parent pids), and selections
-- go only to the companion showing on the right. No match means nothing is sent.

local client_panes = {}

local function pane_of_client(client)
    if client_panes[client.id] then return client_panes[client.id] end
    local ok, peer = pcall(function() return client.tcp_handle:getpeername() end)
    if not ok or not peer or not peer.port then return nil end
    local panes = {}
    for _, l in ipairs(vim.fn.systemlist({ "tmux", "list-panes", "-a", "-F", "#{pane_pid} #{pane_id}" })) do
        local pid, id = l:match("^(%d+) (%S+)$")
        if pid then panes[pid] = id end
    end
    local me = tostring(vim.fn.getpid())
    for _, pid in ipairs(vim.fn.systemlist({ "lsof", "-nP", "-t", "-iTCP:" .. peer.port, "-sTCP:ESTABLISHED" })) do
        while pid ~= me and pid ~= "" and pid ~= "0" and pid ~= "1" and not panes[pid] do
            pid = vim.trim(vim.fn.system({ "ps", "-o", "ppid=", "-p", pid }))
        end
        if panes[pid] then
            client_panes[client.id] = panes[pid]
            return panes[pid]
        end
    end
end

local function visible_companion()
    local now = vim.uv.now()
    if now - visible.at < 500 then return visible.pane end
    visible.pane, visible.at = nil, now
    for _, l in ipairs(vim.fn.systemlist({ "tmux", "list-panes", "-t", state.meta.window or "", "-F", "#{pane_id} #{@review_task}" })) do
        local id, task = l:match("^(%S+) (%S+)$")
        if task then visible.pane = id break end
    end
    return visible.pane
end

local function route_selections()
    local server = require("claudecode.server.init")
    if server._review_routed then return end
    local broadcast = server.broadcast
    server.broadcast = function(method, params)
        if method ~= "selection_changed" and method ~= "at_mentioned" then return broadcast(method, params) end
        -- Lookups shell out, which a libuv callback can't do.
        if vim.in_fast_event() then
            vim.schedule(function() server.broadcast(method, params) end)
            return true
        end
        -- The review's own panels (task list, summary, file tree) aren't code worth sending.
        local path = params and params.filePath or ""
        if path:match("^review://") or path:match("^gitsigns%-diff://") then return false end
        local tcp, target = server.state.server, visible_companion()
        if not tcp or not target then return false end
        -- Past-task buffers are gitsigns://…//<sha>:<path>; name the repo file instead (the text is the snapshot's).
        local rel = params and params.filePath and params.filePath:match("^gitsigns://.-//[^:]*:(.+)$")
        if rel then params.filePath, params.fileUrl = state.root .. "/" .. rel, "file://" .. state.root .. "/" .. rel end
        for _, client in pairs(tcp.clients or {}) do
            if pane_of_client(client) == target then return server.send(client, method, params) end
        end
        return false
    end
    server._review_routed = true
end

local function start_ide_server()
    if not pcall(require("lazy").load, { plugins = { "claudecode.nvim" } }) or not package.loaded["claudecode"] then return end
    route_selections()
    local port = require("claudecode").state.port
    local f = port and io.open(state.dir .. "/ide-port", "w")
    if f then
        f:write(tostring(port))
        f:close()
    end
end

local function jump(dir)
    local buf = vim.api.nvim_get_current_buf()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    if dir < 0 then marks = vim.iter(marks):rev():totable() end
    for _, m in ipairs(marks) do
        local l = m[2] + 1
        if (dir > 0 and l > cur) or (dir < 0 and l < cur) then
            vim.api.nvim_win_set_cursor(0, { l, 0 })
            vim.cmd("normal! zv")
            return
        end
    end
end

local function notes_to_qf()
    local items = {}
    for _, n in ipairs(state.notes) do
        table.insert(items, {
            filename = state.root .. "/" .. n.file,
            lnum = n._lnum or n.line or 1,
            text = (n.task and ("[task %d] "):format(n.task) or "") .. n.text:gsub("\n", " "),
        })
    end
    vim.fn.setqflist({}, " ", { title = "REVIEW notes", items = items })
    vim.cmd.copen()
end

function M.open()
    state.root = git({ "rev-parse", "--show-toplevel" })
    if not state.root then return vim.notify("review: not in a git repo", vim.log.levels.ERROR) end
    state.dir = vim.fn.fnamemodify(git({ "rev-parse", "--path-format=absolute", "--git-path", "review" }), ":p"):gsub("/$", "")
    state.meta = read_json(state.dir .. "/meta.json")
    if not state.meta or not state.meta.base then
        return vim.notify("review: no meta.json in " .. state.dir .. "; start a review from Claude", vim.log.levels.ERROR)
    end
    set_highlights()
    local hl_group = vim.api.nvim_create_augroup("ReviewHighlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = hl_group, callback = set_highlights })
    -- A fix that landed while a plain tab was open is applied on the way back.
    vim.api.nvim_create_autocmd("TabEnter", { group = hl_group, callback = function() M.refresh_open_task() end })
    load_state()
    watch()
    start_ide_server()

    local group = vim.api.nvim_create_augroup("ReviewNotes", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
        group = group,
        callback = function(ev)
            render(ev.buf)
            -- Deferred so gitsigns has finished setting up the window before folds go in.
            local win = vim.api.nvim_get_current_win()
            vim.schedule(function() fold(ev.buf, win) end)
        end,
    })

    local function widen(d)
        return function()
            vim.g.review_context = math.max(0, vim.g.review_context + d)
            refold_all()
            vim.api.nvim_echo({ { ("review: %d lines of context"):format(vim.g.review_context) } }, false, {})
        end
    end
    -- Moves to the next (dir 1) or previous (-1) unread file through gitsigns' own navigation,
    -- then hands focus back to the file pane, which gitsigns moves to the tree asynchronously.
    local function step_file(dir)
        return function()
            local tree = current_tree()
            local panel = tree and tree_panel(tree)
            if not panel then return end
            local pane
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
                if not name:match("^gitsigns%-diff://") and not name:match("^review://") then pane = win end
            end
            local read = valid_read()
            local target
            for i = panel.current_file + dir, dir > 0 and #panel.file_lnums or 1, dir do
                local node = panel.rows[panel.file_lnums[i]]
                if node and not read[node.path] then target = i break end
            end
            if not target then
                return vim.api.nvim_echo({ { ("review: no %s unread file"):format(dir > 0 and "next" or "previous"), "Comment" } }, false, {})
            end
            panel:navigate(target - panel.current_file)
            vim.defer_fn(function()
                if pane and vim.api.nvim_win_is_valid(pane) then vim.api.nvim_set_current_win(pane) end
            end, 50)
        end
    end
    vim.keymap.set("n", "]r", function() jump(1) end, { desc = "Next REVIEW note" })
    vim.keymap.set("n", "[r", function() jump(-1) end, { desc = "Previous REVIEW note" })
    vim.keymap.set("n", "<leader>Rq", notes_to_qf, { desc = "REVIEW notes to quickfix" })
    vim.keymap.set("n", "<leader>Rt", function()
        state.enabled = not state.enabled
        render_all()
    end, { desc = "Toggle REVIEW notes" })
    vim.keymap.set("n", "<leader>R+", widen(5), { desc = "More context around changes" })
    vim.keymap.set("n", "<leader>R-", widen(-5), { desc = "Less context around changes" })
    vim.keymap.set("n", "<leader>Rg", pick_group, { desc = "Pick review group (task)" })
    vim.keymap.set("n", "<leader>Rn", step_file(1), { desc = "Next unread file" })
    vim.keymap.set("n", "<leader>Rp", step_file(-1), { desc = "Previous unread file" })
    vim.keymap.set("n", "<leader>Rr", toggle_read, { desc = "Toggle file read" })
    vim.keymap.set("n", "<leader>RN", function() step_task(1) end, { desc = "Next task" })
    vim.keymap.set("n", "<leader>RP", function() step_task(-1) end, { desc = "Previous task" })
    vim.keymap.set("n", "<leader>Ro", open_real_file, { desc = "Open the real file in a new tab" })
    vim.keymap.set("n", "<leader>Ra", function() approve(state.group and state.group.task) end,
        { desc = "Mark the open task reviewed" })
    vim.keymap.set("v", "<leader>Rs", send_selection, { desc = "Send selection to the task's Claude" })

    require("lazy").load({ plugins = { "gitsigns.nvim" } })
    open_group(all_group())
end

function M.setup()
    vim.api.nvim_create_user_command("Review", M.open, { desc = "Open the Claude review view" })
end

return M
