return {
    "preservim/vimux",
    init = function()
        vim.g.VimuxOrientation = "h"
        vim.g.VimuxHeight = "38%"
        vim.g.VimuxOpenExtraArgs = "-b" -- for "before", referring to the new pane position relative to the current one (so, on the left)

        vim.keymap.set('n', '<leader>tp', ':VimuxPromptCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tl', ':VimuxRunLastCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tq', ':VimuxCloseRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tx', ':VimuxInterruptRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tz', ':VimuxZoomRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tk', ':VimuxClearTerminalScreen<CR>', { noremap = true, silent = true })
    end,
    config = function()
        -- Store the custom target mode for this Neovim session
        vim.g.VimuxCustomTarget = nil
        
        -- Setup the cross-session targeting by overriding VimuxRunCommand
        vim.cmd([[
          " Save original function and override VimuxRunCommand for marked pane support
          if !exists('g:VimuxTargetSetup')
            let g:VimuxTargetSetup = 1
            
            " Helper function to check if runner exists
            function! s:hasRunner(index)
              let runnerType = VimuxOption('VimuxRunnerType')
              return match(VimuxTmux('list-'.runnerType."s -F '#{".runnerType."_id}'"), a:index)
            endfunction
            
            " Helper function to exit copy mode
            function! s:exitCopyMode()
              try
                call VimuxTmux('copy-mode -q -t '.g:VimuxRunnerIndex)
              catch
                " Ignore if not in copy mode
              endtry
            endfunction
            
            " Store the original VimuxRunCommand implementation
            function! s:VimuxRunCommandOrig(command, ...)
              " Original VimuxRunCommand logic
              if !exists('g:VimuxRunnerIndex') || s:hasRunner(g:VimuxRunnerIndex) ==# -1
                call VimuxOpenRunner()
              endif
              let l:autoreturn = 1
              if exists('a:1')
                let l:autoreturn = a:1
              endif
              let l:resetSequence = VimuxOption('VimuxResetSequence')
              let g:VimuxLastCommand = a:command

              call s:exitCopyMode()
              call VimuxSendKeys(l:resetSequence)
              call VimuxSendText(a:command)
              if l:autoreturn ==# 1
                call VimuxSendKeys('Enter')
              endif
            endfunction
            
            " New VimuxRunCommand with marked pane support
            function! VimuxRunCommand(command, ...)
              " Check if we should use marked pane
              if exists('g:VimuxCustomTarget') && g:VimuxCustomTarget == 'mark'
                " Get the marked pane ID
                let marked_pane = system('tmux list-panes -a -F "#{pane_id} #{?pane_marked,MARKED,}" | grep MARKED | cut -d" " -f1 | tr -d "\n"')
                
                if marked_pane != ''
                  " Set the marked pane as runner - this bypasses hasRunner check
                  let g:VimuxRunnerIndex = marked_pane
                  
                  " Execute command directly on marked pane
                  let l:autoreturn = 1
                  if exists('a:1')
                    let l:autoreturn = a:1
                  endif
                  let l:resetSequence = VimuxOption('VimuxResetSequence')
                  let g:VimuxLastCommand = a:command

                  " Exit copy mode and send command
                  try
                    call VimuxTmux('copy-mode -q -t '.g:VimuxRunnerIndex)
                  catch
                    " Ignore if not in copy mode
                  endtry
                  call VimuxSendKeys(l:resetSequence)
                  call VimuxSendText(a:command)
                  if l:autoreturn ==# 1
                    call VimuxSendKeys('Enter')
                  endif
                  return
                else
                  echo "No marked pane found. Use 'prefix + m' in tmux to mark a pane."
                  return
                endif
              endif
              
              " Default behavior - use original logic
              call call('s:VimuxRunCommandOrig', [a:command] + a:000)
            endfunction
          endif
        ]])
        
        -- Create the VimuxTarget command
        vim.api.nvim_create_user_command('VimuxTarget', function(opts)
          local target = opts.args
          if target == '' then
            if vim.g.VimuxCustomTarget then
              print("Current target: " .. (vim.g.VimuxCustomTarget == 'mark' and 'marked pane' or vim.g.VimuxCustomTarget))
            else
              print("Using default Vimux behavior")
            end
          elseif target == 'mark' then
            vim.g.VimuxCustomTarget = 'mark'
            -- Clear any existing runner index to force re-evaluation
            vim.g.VimuxRunnerIndex = vim.NIL
            print("Vimux will now target the marked pane (use 'prefix + m' in tmux to mark)")
          elseif target == 'clear' then
            vim.g.VimuxCustomTarget = vim.NIL
            vim.g.VimuxRunnerIndex = vim.NIL
            print("Vimux target cleared - using default behavior")
          else
            print("Usage: :VimuxTarget [mark|clear]")
          end
        end, {
          nargs = '?',
          complete = function()
            return { 'mark', 'clear' }
          end,
          desc = "Set Vimux to target marked pane or clear custom targeting"
        })
    end
}
