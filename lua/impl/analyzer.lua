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
			local struct_name = ts.get_node_text(node, bufnr)
			local row, _, _ = node:start()

			require("imple.gopls").get_implemented(bufnr, struct_name, function(interfaces)
				if interfaces and #interfaces > 0 then
					local label = table.concat(interfaces, ", ")

					vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
						virt_text = { { " -- " .. label, "Comment" } },
						virt_text_pos = "eol",
					})
				end
			end)
		end
	end
end

return M
