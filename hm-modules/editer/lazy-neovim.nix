{ config, pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;

    # LazyVim configuration
    extraLuaConfig = ''
      -- LazyVim bootstrap
      local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
          "git",
          "clone",
          "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git",
          "--branch=stable",
          lazypath,
        })
      end
      vim.opt.rtp:prepend(lazypath)

      -- LazyVim configuration
      require("lazy").setup({
        spec = {
          { "LazyVim/LazyVim", import = "lazyvim.plugins" },
          -- Add any additional plugins here
          { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "nix" } } },
        },
        install = { colorscheme = { "catppuccin" } },
        checker = { enabled = true },
        performance = {
          rtp = {
            disabled_plugins = {
              "gzip",
              "matchit",
              "matchparen",
              "netrwPlugin",
              "tarPlugin",
              "tohtml",
              "tutor",
              "zipPlugin",
            },
          },
        },
      })

      -- Basic settings
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.tabstop = 4
      vim.opt.shiftwidth = 4
      vim.opt.expandtab = true
      vim.opt.smartindent = true
      vim.opt.autoindent = true
      vim.opt.clipboard = "unnamedplus"
      vim.opt.cursorline = true
      vim.opt.mouse = "a"

      -- Leader key (LazyVim default is space)
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- Custom keymaps (optional)
      vim.keymap.set('n', '<C-s>', ':w<CR>', { noremap = true, silent = true })
      vim.keymap.set('n', '<C-q>', ':q<CR>', { noremap = true, silent = true })
    '';

    # Required packages for LazyVim
    plugins = with pkgs.vimPlugins; [
      # Core LazyVim dependencies
      lazy-nvim

      # Treesitter (required for syntax highlighting)
      # nvim-treesitter

      # nix语法支持
      vim-nix
    ];
  };
}
