vim.g.lsp_servers = {
	-- Copied from github/rijulkap
	ruff = { init_options = {
		settings = {
			format = {
				tabWidth = 4,
			},
		},
	} },
	lua_ls = {
		settings = {
			Lua = {
				runtime = {
					version = "LuaJIT",
				},
				completion = {
					callSnippet = "Replace",
				},
				-- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
				diagnostics = {
					globals = { "vim" },
					disable = { "missing-fields", "undefined-doc-name" },
				},
				workspace = {
					library = {
						vim.env.VIMRUNTIME,
						vim.fn.expand("~/.config/nvim/lua"),
					},
				},
				hint = { enable = true },
				checkThirdParty = false,
			},
		},
	},
}

vim.g.other_mason_servers = { "stylua" }

return {
	{
		"mason-org/mason.nvim",
		opts = {},
	},
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
			"saghen/blink.cmp",

			-- Allows extra capabilities provided by nvim-cmp
			"hrsh7th/nvim-cmp",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-cmdline",

			-- Tailwind
			"jcha0713/cmp-tw2css",
		},
		event = { "VeryLazy", "BufReadPre", "BufNewFile" },
		config = function(_)
			local mr = require("mason-registry")
			mr.refresh(function()
				for _, tool in ipairs(vim.g.other_mason_servers) do
					local p = mr.get_package(tool)
					if not p:is_installed() then
						p:install()
					end
				end
			end)

			-- Configure and get names of lsp servers
			local lsp_server_names = {}
			for lsp_server_name, _ in pairs(vim.g.lsp_servers) do
				-- Add custom config settings
				local lsp_server_settings = vim.g.lsp_servers[lsp_server_name] or {}
				vim.lsp.config(lsp_server_name, lsp_server_settings)

				table.insert(lsp_server_names, lsp_server_name)
			end

			local capabilities = require("blink.cmp").get_lsp_capabilities(nil, true)
			vim.lsp.config("*", { capabilities = capabilities })

			require("mason-lspconfig").setup({
				ensure_installed = lsp_server_names,
				automatic_enable = true,
			})

			local function setup_document_highlight(bufnr)
				local highlight_augroup = vim.api.nvim_create_augroup("LspDocumentHighlight", { clear = false })

				vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
					group = highlight_augroup,
					buffer = bufnr,
					callback = vim.lsp.buf.document_highlight,
				})

				vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
					group = highlight_augroup,
					buffer = bufnr,
					callback = vim.lsp.buf.clear_references,
				})

				vim.api.nvim_create_autocmd("LspDetach", {
					group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
					callback = function(event2)
						vim.lsp.buf.clear_references()
						vim.api.nvim_clear_autocmds({ group = "LspDocumentHighlight", buffer = event2.buf })
					end,
				})
			end

			local function setup_codelens(bufnr)
				vim.lsp.codelens.refresh()
				vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
					buffer = bufnr,
					callback = vim.lsp.codelens.refresh,
				})
			end

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
				callback = function(event)
					local map = function(keys, func, desc)
						vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					map("gd", require("fzf-lua").lsp_definitions, "[G]oto [D]efinition")
					map("gr", require("fzf-lua").lsp_references, "[G]oto [R]eferences")
					map("gI", require("fzf-lua").lsp_implementations, "[G]oto [I]mplementation")
					map("<leader>D", require("fzf-lua").lsp_typedefs, "Type [D]efinition")
					map("<leader>ds", require("fzf-lua").lsp_document_symbols, "[D]ocument [S]ymbols")
					map("<leader>ws", require("fzf-lua").lsp_live_workspace_symbols, "[W]orkspace [S]ymbols")
					map("<leader>cr", vim.lsp.buf.rename, "[R]e[n]ame")
					map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
					map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
					map("<leader>lk", vim.diagnostic.open_float, "Open Diagnostics in Floating Window")
					map("<leader>ln", function()
						vim.diagnostic.jump({ count = 1, float = true })
					end, "Go to next diagnostic")
					map("<leader>lp", function()
						vim.diagnostic.jump({ count = -1, float = true })
					end, "Go to previous diagnostic")

					local client = vim.lsp.get_client_by_id(event.data.client_id)
					if client then
						if
							client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf)
						then
							setup_document_highlight(event.buf)
						end
						if client:supports_method(vim.lsp.protocol.Methods.textDocument_codeLens, event.buf) then
							setup_codelens(event.buf)
						end
						if client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
							vim.lsp.inlay_hint.enable(true)
						end
						if client.name == "ruff" then
							client.server_capabilities.hoverProvider = false
						end
					end
				end,
			})

			vim.lsp.set_log_level("off")

			vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
				border = "rounded",
				max_height = math.floor(vim.o.lines * 0.5),
				max_width = math.floor(vim.o.columns * 0.4),
			})

			vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
				border = "rounded",
				max_height = math.floor(vim.o.lines * 0.5),
				max_width = math.floor(vim.o.columns * 0.4),
			})

			-- wrappers to allow for toggling
			local def_virtual_text = {
				isTrue = {
					severity = { max = "WARN" },
					source = "if_many",
					spacing = 4,
					prefix = "• ",
				},
				isFalse = false,
			}

			local function truncate_message(message, max_length)
				if #message > max_length then
					return message:sub(1, max_length) .. "..."
				end
				return message
			end

			local def_virtual_lines = {
				isTrue = {
					current_line = true,
					severity = { min = "ERROR" },
					format = function(diagnostic)
						local max_length = 80 -- Set your preferred max length
						return "✖ " .. truncate_message(diagnostic.message, max_length)
					end,
				},
				isFalse = false,
			}

			local default_diagnostic_config = {
				update_in_insert = false,
				virtual_lines = def_virtual_lines.isFalse,
				virtual_text = def_virtual_text.isTrue,
				underline = true,
				severity_sort = true,
				float = {
					focusable = true,
					style = "minimal",
					border = "rounded",
					source = "always",
					header = "",
					prefix = "",
				},
				signs = {
					text = {
						-- [vim.diagnostic.severity.ERROR] = " ",
						-- [vim.diagnostic.severity.WARN] = " ",
						-- [vim.diagnostic.severity.INFO] = " ",
						-- [vim.diagnostic.severity.HINT] = " ",
						[vim.diagnostic.severity.ERROR] = "",
						[vim.diagnostic.severity.WARN] = "",
						[vim.diagnostic.severity.INFO] = "",
						[vim.diagnostic.severity.HINT] = "",
					},
					numhl = {
						[vim.diagnostic.severity.ERROR] = "ErrorMsg", -- Just cause its also bold
						[vim.diagnostic.severity.WARN] = "DiagnosticWarn",
						[vim.diagnostic.severity.INFO] = "DiagnosticInfo",
						[vim.diagnostic.severity.HINT] = "DiagnosticHint",
					},
				},
			}

			vim.diagnostic.config(default_diagnostic_config)

			-- Toggle virtual lines with <leader>uv
			local virtual_lines_enabled = false

			vim.keymap.set("n", "<leader>uv", function()
				-- Toggle the virtual_lines_enabled state
				virtual_lines_enabled = not virtual_lines_enabled

				vim.diagnostic.config({
					virtual_lines = virtual_lines_enabled and def_virtual_lines.isTrue or def_virtual_lines.isFalse,
				})

				if virtual_lines_enabled then
					print("Virtual lines enabled (current line highlighting on)")
				else
					print("Virtual lines disabled (current line highlighting off)")
				end
			end, { desc = "Toggle virtual lines diagnostics (current line)" })

			-- Completion in command mode
			local cmp = require("cmp")

			cmp.setup.cmdline("/", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = "buffer", max_item_count = 5 },
				},
			})

			cmp.setup.cmdline(":", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = "path", max_item_count = 5 },
				}, {
					{ name = "cmdline", max_item_count = 5 },
				}),
			})
		end,
	},
	{
		"folke/lazydev.nvim",
		ft = "lua", -- only load on lua files
		opts = {
			library = {
				-- See the configuration section for more details
				-- Load luvit types when the `vim.uv` word is found
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
			sources = {
				-- add lazydev to your completion providers
				default = { "lazydev" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100, -- show at a higher priority than lsp
					},
				},
			},
		},
	},

	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets" },
		version = "1.*",

		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			-- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
			-- 'super-tab' for mappings similar to vscode (tab to accept)
			-- 'enter' for enter to accept
			-- 'none' for no mappings
			--
			-- All presets have the following mappings:
			-- C-space: Open menu or open docs if already open
			-- C-n/C-p or Up/Down: Select next/previous item
			-- C-e: Hide menu
			-- C-k: Toggle signature help (if signature.enabled = true)
			--
			-- See :h blink-cmp-config-keymap for defining your own keymap
			keymap = {
				preset = "default",
			},

			signature = {
				enabled = true,
			},

			appearance = {
				use_nvim_cmp_as_default = false,
				-- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
				-- Adjusts spacing to ensure icons are aligned
				nerd_font_variant = "mono",
			},

			-- (Default) Only show the documentation popup when manually triggered
			completion = {
				accept = {
					auto_brackets = {
						enabled = true,
					},
				},
				menu = {
					draw = {
						treesitter = { "lsp" },
					},
				},
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 400,
				},
			},
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
			},
			fuzzy = { implementation = "prefer_rust_with_warning" },
		},
		opts_extend = { "sources.default" },
	},
	{
		"pmizio/typescript-tools.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
		opts = {},
	},
}
