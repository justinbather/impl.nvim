local M = {}

local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("impl")

local function get_client(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "gopls" })
	return clients[1]
end

function M.get_implemented(bufnr, struct_name, callback)
	local client = get_client(bufnr)
	if not client then
		vim.notify("gopls not running", vim.log.levels.WARN)
		callback({})
		return
	end

	local params = { textDocument = vim.lsp.util.make_text_document_params() }

	-- struct methods from current buffer
	client.request("textDocument/documentSymbol", params, function(err, result)
		if err or not result then
			callback({})
			return
		end

		local struct_methods = {}
		for _, symbol in ipairs(result) do
			if symbol.kind == 23 and symbol.name == struct_name and symbol.children then
				for _, m in ipairs(symbol.children) do
					struct_methods[m.name] = true
				end
			end
		end

		-- workspace interfaces
		client.request("workspace/symbol", { query = "" }, function(err2, workspace_symbols)
			if err2 or not workspace_symbols then
				callback({})
				return
			end

			local interfaces = vim.tbl_filter(function(s)
				return s.kind == 11
			end, workspace_symbols)
			local implemented = {}

			for _, iface in ipairs(interfaces) do
				local iface_methods = {}

				for _, s in ipairs(workspace_symbols) do
					if s.containerName == iface.name then
						iface_methods[s.name] = true
					end
				end

				local satisfies = true
				for name, _ in pairs(iface_methods) do
					if not struct_methods[name] then
						satisfies = false
						break
					end
				end

				if satisfies and next(iface_methods) ~= nil then
					table.insert(implemented, iface.name)
				end
			end

			callback(implemented)
		end, bufnr)
	end, bufnr)
end

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

			M.get_implemented(bufnr, struct_name, function(interfaces)
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
