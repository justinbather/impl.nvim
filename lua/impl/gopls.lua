local M = {}

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

return M
