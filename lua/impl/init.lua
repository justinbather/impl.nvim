local M = {}

function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
		pattern = "*.go",
		callback = function()
			require("impl.analyzer").refresh()
		end,
	})
end

return M
