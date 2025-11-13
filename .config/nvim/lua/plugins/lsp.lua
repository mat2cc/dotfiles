return {
	"mason-org/mason-lspconfig.nvim",
	lazy = false,
	dependencies = {
		{ "mason-org/mason.nvim", opts = {}, cmd = "Mason", lazy = false },
		{ "neovim/nvim-lspconfig" },
		{
			"hrsh7th/nvim-cmp",
			opts = function(_, opts)
				opts.sources = opts.sources or {}
				table.insert(opts.sources, {
					name = "lazydev",
					group_index = 0, -- set group index to 0 to skip loading LuaLS completions
				})
			end,
		},
		{ "hrsh7th/cmp-buffer" },
		{ "hrsh7th/cmp-path" },
		{ "hrsh7th/cmp-nvim-lsp" },
		{
			{
				"L3MON4D3/LuaSnip",
				-- follow latest release.
				version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
				-- install jsregexp (optional!).
				build = "make install_jsregexp",
			},
		},
	},
	opts = function()
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("my.lsp", {}),
			callback = function(event)
				vim.keymap.set("n", "<leader>fo", function()
					vim.lsp.buf.format()
				end)
				vim.keymap.set("n", "gd", vim.lsp.buf.definition)
				vim.keymap.set("n", "K", vim.lsp.buf.hover)
				vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol)
				vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float)
				vim.keymap.set("n", "[d", vim.diagnostic.goto_next)
				vim.keymap.set("n", "]d", vim.diagnostic.goto_prev)
				vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
				vim.keymap.set("n", "<leader>rr", vim.lsp.buf.references)
				vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename)
				vim.keymap.set("n", "<leader>hw", function()
					print("hi there")
				end) -- used to test that leader isn't broken
			end,
		})
	end,
	-- config = function()
	--   vim.api.nvim_create_autocmd('LspAttach', {
	--     desc = 'LSP actions',
	--     callback = function(event)
	--       vim.keymap.set("n", "<leader>fo", function() vim.lsp.buf.format() end, opts)
	--       vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
	--       vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
	--       vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
	--       vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
	--       vim.keymap.set("n", "[d", vim.diagnostic.goto_next, opts)
	--       vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, opts)
	--       vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
	--       vim.keymap.set("n", "<leader>rr", vim.lsp.buf.references, opts)
	--       vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
	--       vim.keymap.set("n", "<leader>hw", function() print("hi there") end, opts) -- used to test that leader isn't broken
	--     end
	--   })
	--
	--   -- other settings needed for specific servers
	--   -- local settings = {
	--   --   lua_ls = {
	--   --     settings = {
	--   --       Lua = {
	--   --         completion = {
	--   --           callSnippet = "Replace"
	--   --         }
	--   --       }
	--   --     }
	--   --   }
	--   -- }
	--   -- local lspconfig = require('lspconfig')
	--   --
	--   -- for k, v in pairs(settings) do
	--   --     lspconfig(k, {
	--   --         settings = v
	--   --     })
	--   -- end
	--
	--   -- require('lazydev').setup()
	--   -- require('mason').setup()
	--   -- local mason_lspconfig = require('mason-lspconfig')
	--   -- mason_lspconfig.setup({
	--   -- })
	--   --
	--   local cmp = require('cmp')
	--   local luasnip = require('luasnip')
	--   luasnip.config.setup()
	--
	--   local cmp_select = { behavior = cmp.SelectBehavior.Select }
	--   cmp.setup(
	--   {
	--     mapping = cmp.mapping.preset.insert({
	--       --['<CR>'] = cmp.config.disable,
	--       ['<Tab>'] = cmp.config.disable,
	--       ['<S-Tab>'] = cmp.config.disable,
	--       ['<C-k>'] = cmp.mapping.select_prev_item(cmp_select),
	--       ['<C-j>'] = cmp.mapping.select_next_item(cmp_select),
	--       ['<C-b>'] = cmp.mapping.scroll_docs(-4),
	--       ['<C-f>'] = cmp.mapping.scroll_docs(4),
	--       -- ['<C-y>'] = cmp.mapping.confirm({ select = true }),
	--       ["<C-Space>"] = cmp.mapping.complete(),
	--       ["<C-n>"] = cmp.mapping(function(fallback)
	--         if cmp.visible() then
	--           cmp.select_next_item()
	--         elseif luasnip.expand_or_jumpable() then
	--           luasnip.expand_or_jump()
	--         else
	--           fallback()
	--         end
	--       end, { "i", "s" }),
	--       ["<C-p>"] = cmp.mapping(function(fallback)
	--         if cmp.visible() then
	--           cmp.select_prev_item()
	--         elseif luasnip.jumpable( -1) then
	--           luasnip.jump( -1)
	--         else
	--           fallback()
	--         end
	--       end, { "i", "s" }),
	--     }),
	--     sources = {
	--       { name = "nvim_lsp" },
	--       { name = "luasnip" },
	--       {
	--         name = "buffer",
	--         keyword_length = 5,
	--         option = {
	--           get_bufnrs = function()
	--             local bufs = {}
	--             for _, win in ipairs(vim.api.nvim_list_wins()) do
	--               bufs[vim.api.nvim_win_get_buf(win)] = true
	--             end
	--             return vim.tbl_keys(bufs)
	--           end,
	--         },
	--       },
	--       { name = "path" },
	--     },
	--     snippet = {
	--       expand = function(args)
	--         require("luasnip").lsp_expand(args.body)
	--       end,
	--     }
	--   })
	--
	--
	--   -- local lsp_capabilities = require('cmp_nvim_lsp').default_capabilities()
	--   --
	--   --
	--   -- mason_lspconfig.setup_handlers({
	--   --   function(server_name)
	--   --     lspconfig[server_name].setup({
	--   --       capabilities = lsp_capabilities,
	--   --       settings = (others[server_name] or {}).settings,
	--   --     })
	--   --   end,
	--   -- })
	-- end
}
