{ config, pkgs, lib, ... }:

{
  # ========== Neovim (nvim) 基础配置 ==========
  programs.neovim = {
    enable = true;
    # Lua配置：现代Neovim插件大多需要Lua配置
    extraLuaConfig = ''
      -- ========== 基本设置 ==========
      vim.g.mapleader = ','
      vim.g.maplocalleader = ','

      -- 基本编辑器选项
      vim.opt.number = true              -- 行号
      vim.opt.relativenumber = true      -- 相对行号
      vim.opt.tabstop = 4                -- tab宽度
      vim.opt.shiftwidth = 4             -- 自动缩进宽度
      vim.opt.expandtab = true           -- 用空格代替tab
      vim.opt.smartindent = true         -- 智能缩进
      vim.opt.autoindent = true          -- 启用自动缩进
      vim.opt.clipboard = 'unnamedplus'  -- 让系统剪贴板可用
      vim.opt.cursorline = true          -- 高亮当前行
      vim.opt.mouse = 'a'                -- 启用鼠标支持
      vim.cmd('syntax on')                -- 语法高亮
      vim.cmd('filetype plugin indent on')

      -- 快捷键：保存和退出
      vim.keymap.set('n', '<C-s>', ':w<CR>', { noremap = true, silent = true })
      vim.keymap.set('n', '<C-q>', ':q<CR>', { noremap = true, silent = true })
      -- 快速保存
      vim.keymap.set('n', '<leader>w', ':w<CR>', { noremap = true, silent = true })
      -- 快速退出
      vim.keymap.set('n', '<leader>q', ':q<CR>', { noremap = true, silent = true })

      -- nvim-tree.lua 文件树配置
      require("nvim-tree").setup({
        sort_by = "case_sensitive",
        view = {
          width = 30,
        },
        renderer = {
          group_empty = true,
        },
        filters = {
          dotfiles = false, -- 显示点文件
        },
      })
      -- 快捷键：<leader>e 切换文件树
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { noremap = true, silent = true })

      -- telescope.nvim 模糊查找配置
      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
      vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})

      -- lualine.nvim 状态栏配置
      require('lualine').setup({
        options = {
          theme = 'catppuccin'
        }
      })

      -- nvim-cmp 自动补全配置
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        })
      })

      -- nvim-autopairs 自动括号配置
      require('nvim-autopairs').setup({})

      -- Comment.nvim 注释配置（需要 nvim-ts-context-commentstring）
      require('Comment').setup({
        pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),
      })

      -- gitsigns.nvim Git状态配置
      require('gitsigns').setup()

      -- which-key.nvim 快捷键提示
      require('which-key').setup()

      -- 启用主题
      vim.cmd('colorscheme catppuccin')
    '';
    # ========== 插件配置 ==========
    plugins = with pkgs.vimPlugins; [
      # ========== 1. 编辑器类插件 ==========
      # 1.1 主题与外观
      catppuccin-nvim # 主题：现代色彩主题
      lualine-nvim # 状态栏美化：底部状态栏
      nvim-web-devicons # 图标：为各种文件类型提供图标
      indent-blankline-nvim # 缩进线：显示缩进辅助线
      nvim-notify # 通知系统：美观的通知提示

      # 1.2 导航与搜索
      nvim-tree-lua # 文件树浏览：侧边栏文件管理（快捷键：<leader>e 切换文件树）
      telescope-nvim # 全文查找：文件、内容、LSP等搜索（快捷键：<leader>ff 查找文件，<leader>fg 实时grep）
      trouble-nvim # 错误提示：集中显示诊断、错误、警告
      which-key-nvim # 快捷键提示：显示可用快捷键

      # 1.3 工具增强
      toggleterm-nvim # 终端：内嵌终端支持

      # ========== 2. 代码编写类插件 ==========
      # 2.1 语言服务器与语法
      nvim-lspconfig # LSP配置：提供语言服务器协议支持
      nvim-treesitter.withAllGrammars # 树状语法高亮：增强语法高亮和代码分析

      # 2.2 代码补全
      nvim-cmp # 自动补全引擎：主补全框架
      cmp-nvim-lsp # LSP自动补全源
      cmp-buffer # 缓冲区文本补全源
      cmp-path # 文件路径补全源
      cmp-cmdline # 命令行补全源
      nvim-autopairs # 自动补全括号：输入时自动补全括号、引号

      # 2.3 代码片段
      friendly-snippets # 预定义代码片段集合
      luasnip # 代码片段引擎：支持自定义片段

      # 2.4 编辑增强
      vim-surround # 括号/引号配对：处理包围符号（ds/ys/cs）
      comment-nvim # 快速注释：使用gc/gcc注释代码（替代vim-commentary）
      nvim-ts-context-commentstring # 上下文注释：根据上下文提供正确的注释符号
      vim-easymotion # 快速移动：快速跳转到任意位置
      vim-multiple-cursors # 多光标支持：类似VS Code的多光标编辑

      # ========== 3. 特定语言代码类插件 ==========
      vim-nix # Nix语法高亮：Nix语言支持

      # ========== 4. Git工具 ==========
      vim-fugitive # git工具：Git命令集成（:Git）
      gitsigns-nvim # git改动显示：侧边栏显示git状态（替代vim-gitgutter）
      diffview-nvim # 差异查看：查看文件差异和分支比较
    ];
  };
}
