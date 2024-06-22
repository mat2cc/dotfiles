return {
    'stevearc/oil.nvim',
    opts = {
      view_options = {
        show_hidden = true
      }
    },
    keys = {
        { "<leader>sf",  function() require('oil').open() end },
    },
    lazy = false -- needed to work with `nvim .` command
}
