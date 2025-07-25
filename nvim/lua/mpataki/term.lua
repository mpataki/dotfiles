-- Sets up some nvim term mode utilities

local TermOpenModes = {
    TAB = 1,
    CURRENT_WINDOW = 2,
    VERTICAL_SPLIT = 3,
    HORIZONTAL_SPLIT = 4,
}

function StartTerm(command, openMode)
    if openMode == TermOpenModes.CURRENT_WINDOW then
        vim.cmd('terminal ' .. command)
    elseif openMode == TermOpenModes.HORIZONTAL_SPLIT then
        vim.cmd('horizontal belowright split term://' .. command)
    elseif openMode == TermOpenModes.VERTICAL_SPLIT then
        vim.cmd('vertical rightbelow split term://' .. command)
    else -- TAB
        vim.cmd('tabedit term://' .. command)
    end

    -- set the command in a buf var so we can more easily restart it
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_var(bufnr, 'terminal_command', command)
    vim.api.nvim_command('normal! G')
end

local function sendSigtermToTerminal(bufnr)
    -- Ensure the buffer is a valid terminal
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buftype') == 'terminal' then
        -- Get the job ID
        local job_id = vim.api.nvim_buf_get_var(bufnr, 'terminal_job_id')

        if job_id then
            -- Send SIGTERM to the job
            vim.fn.jobstop(job_id)
        else
            print("No job ID found for buffer " .. bufnr)
        end
    else
        print("Buffer " .. bufnr .. " is not a terminal")
    end
end

function RestartTerm()
    if vim.bo.buftype == 'terminal' then
        local bufnr = vim.api.nvim_get_current_buf()
        local command = vim.api.nvim_buf_get_var(bufnr, 'terminal_command')

        -- kill any running process
        sendSigtermToTerminal(bufnr)

        StartTerm(command, TermOpenModes.CURRENT_WINDOW)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

-- Term default (Tab Window)
vim.api.nvim_create_user_command(
    'Term',
    function(opts)
        StartTerm(opts.args, TermOpenModes.TAB)
    end,
    {nargs = '*'}
)

-- Term Veritical Split
vim.api.nvim_create_user_command(
    'Termv',
    function(opts)
        StartTerm(opts.args, TermOpenModes.VERTICAL_SPLIT)
    end,
    {nargs = '*'}
)

-- Term Horizonal Split
vim.api.nvim_create_user_command(
    'Termh',
    function(opts)
        StartTerm(opts.args, TermOpenModes.HORIZONTAL_SPLIT)
    end,
    {nargs = '*'}
)

-- Term Current Window
vim.api.nvim_create_user_command(
    'Termc',
    function(opts)
        StartTerm(opts.args, TermOpenModes.CURRENT_WINDOW)
    end,
    {nargs = '*'}
)

vim.api.nvim_create_user_command('RestartTerm', RestartTerm, {})

--vim.keymap.set({'n','t'}, '<Leader>r', RestartTerm)
