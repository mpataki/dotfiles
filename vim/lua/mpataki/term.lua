-- Sets up some nvim term mode utilities

function StartTerm(command, inCurrentPane)
    if inCurrentPane then
        vim.cmd('terminal ' .. command)
    else
        vim.cmd('tabedit term://' .. command)
    end

    -- set the command in a buf var so we can more easily restart it
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_var(bufnr, 'terminal_command', command)
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

        StartTerm(command, true)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

vim.api.nvim_create_user_command(
    'Term',
    function(opts)
        StartTerm(opts.args)
    end,
    {nargs = '*'}
)

vim.api.nvim_create_user_command('RestartTerm', RestartTerm, {})

vim.keymap.set({'n','t'}, '<Leader>r', RestartTerm)
