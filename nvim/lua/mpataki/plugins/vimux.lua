return {
  "preservim/vimux",
  init = function()
    vim.g.VimuxOrientation = "h"
    vim.g.VimuxHeight = "38%"
    vim.g.VimuxOpenExtraArgs = "-b" -- for "before", referring to the new pane position relative to the current one (so, on the left)
  end,
  config = function()
    -- Mode tracking: 'vimux' (managed runner) or 'marked' (target marked pane)
    local targetMode = 'vimux'
    local lastMarkedCommand = nil

    -- Marked pane helpers
    local function getMarkedPane()
      local result = vim.fn.system('tmux list-panes -a -F "#{pane_id} #{?pane_marked,MARKED,}" | grep MARKED | cut -d" " -f1 | tr -d "\n"')
      return result ~= '' and result or nil
    end

    local function sendToMarked(cmd, enter)
      local pane = getMarkedPane()
      if not pane then
        print("No marked pane found. Use 'prefix + m' in tmux to mark a pane.")
        return false
      end

      -- Send command directly to marked pane via tmux
      vim.fn.system(string.format("tmux send-keys -t %s -X cancel", pane)) -- Exit copy mode
      vim.fn.system(string.format("tmux send-keys -t %s -l %s", vim.fn.shellescape(pane), vim.fn.shellescape(cmd)))
      if enter then
        vim.fn.system(string.format("tmux send-keys -t %s Enter", vim.fn.shellescape(pane)))
      end

      lastMarkedCommand = cmd
      return true
    end

    -- Mode-aware command wrappers
    local function promptCommand()
      local cmd = vim.fn.input('Command? ')
      if cmd == '' then return end

      if targetMode == 'marked' then
        sendToMarked(cmd, true)
      else
        vim.cmd(string.format('VimuxRunCommand "%s"', cmd:gsub('"', '\\"')))
      end
    end

    local function runLastCommand()
      if targetMode == 'marked' then
        if lastMarkedCommand then
          sendToMarked(lastMarkedCommand, true)
        else
          print("No previous command in marked pane mode")
        end
      else
        vim.cmd('VimuxRunLastCommand')
      end
    end

    local function interruptRunner()
      if targetMode == 'marked' then
        local pane = getMarkedPane()
        if pane then
          vim.fn.system(string.format("tmux send-keys -t %s C-c", vim.fn.shellescape(pane)))
        end
      else
        vim.cmd('VimuxInterruptRunner')
      end
    end

    local function clearTerminal()
      if targetMode == 'marked' then
        sendToMarked('clear', true)
      else
        vim.cmd('VimuxClearTerminalScreen')
      end
    end

    local function toggleMode()
      if targetMode == 'marked' then
        targetMode = 'vimux'
        print("Target: Vimux managed runner")
      else
        local pane = getMarkedPane()
        if pane then
          targetMode = 'marked'
          print("Target: marked pane " .. pane)
        else
          print("No marked pane found. Use 'prefix + m' in tmux to mark a pane.")
        end
      end
    end

    -- Keybindings (mode-aware)
    vim.keymap.set('n', '<leader>tp', promptCommand, { desc = 'Prompt for command' })
    vim.keymap.set('n', '<leader>tl', runLastCommand, { desc = 'Run last command' })
    vim.keymap.set('n', '<leader>tx', interruptRunner, { desc = 'Interrupt runner' })
    vim.keymap.set('n', '<leader>tk', clearTerminal, { desc = 'Clear terminal' })
    vim.keymap.set('n', '<leader>tm', toggleMode, { desc = 'Toggle target mode (Vimux/marked)' })

    -- Vimux-only commands (don't make sense for marked panes)
    vim.keymap.set('n', '<leader>tq', ':VimuxCloseRunner<CR>', { desc = 'Close Vimux runner' })
    vim.keymap.set('n', '<leader>tz', ':VimuxZoomRunner<CR>', { desc = 'Zoom Vimux runner' })
  end
}
