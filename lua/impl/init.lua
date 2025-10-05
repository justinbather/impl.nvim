local M = {}

function M.setup()
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)

			-- Only for gopls
			if client and client.name == "gopls" then
				vim.schedule(function()
					M.refresh()
				end)
			end
		end,
	})

	vim.api.nvim_create_user_command("ImplRefresh", function()
		M.refresh()
	end, {})
end

return M
