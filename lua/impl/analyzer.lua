local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("impl")

local M = {}

function M.refresh()
	local bufnr = vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype
	if ft ~= "go" then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local parser = ts.get_parser(bufnr, "go")
	local tree = parser:parse()[1]
	local root = tree:root()

	local query = ts.query.parse(
		"go",
		[[
		(type_spec
		name: (type_identifier) @name
		type: (struct_type) @struct)
	]]
	)

	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local name = query.captures[id]
		if name == "name" then
			local row, _, _ = node:start()
			-- TODO: query ts for textDocument/typeDefinition
			local implements = "implements: io.Reader"

			vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
				virt_text = { { " -- " .. implements, "Comment" } },
				virt_text_pos = "eol",
			})
		end
	end
end

return M
