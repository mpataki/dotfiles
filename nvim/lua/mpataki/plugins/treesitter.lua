return {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main', -- the `master` branch is locked to Neovim <= 0.11; `main` is the supported rewrite
    lazy = false,
    build = ':TSUpdate',
    dependencies = { 'Hdoc1509/gh-actions.nvim' },
    config = function()
        -- Register the GitHub Actions expression parser before install (main-branch API).
        require('gh-actions.tree-sitter').setup()

        require('nvim-treesitter').setup()

        -- ensure_installed equivalent: install() is async and a no-op when already present.
        require('nvim-treesitter').install {
            'javascript',
            'typescript',
            'tsx',
            'java',
            'groovy',
            'python',
            'c',
            'lua',
            'vim',
            'vimdoc',
            'query',
            'go',
            'gomod',
            'rust',
            'proto',
            'terraform',
            'dockerfile',
            'xml',
            'cpp',
            'markdown',
            'markdown_inline',
            'sql',
            'ruby',
            'yaml',
            'json',
            'toml',
            'bash',
            'html',
            'css',
            'gh_actions_expressions',
        }

        -- The main branch leaves feature activation to the user. Enable highlighting
        -- (and experimental indentation) for any buffer whose filetype has a parser.
        local no_indent = { python = true }
        vim.api.nvim_create_autocmd('FileType', {
            group = vim.api.nvim_create_augroup('mpataki_treesitter', { clear = true }),
            callback = function(args)
                local ft = vim.bo[args.buf].filetype
                local lang = vim.treesitter.language.get_lang(ft)
                if not lang or not vim.treesitter.language.add(lang) then
                    return -- no parser installed for this filetype yet
                end
                vim.treesitter.start(args.buf, lang)
                if not no_indent[ft] then
                    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end
            end,
        })
    end,
}
