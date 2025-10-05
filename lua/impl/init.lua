local M = {}

local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("impl")

local function get_client(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "gopls" })
	return clients[1]
end

-- Ask gopls which interfaces a struct implements
function M.get_implemented(bufnr, struct_name, callback)
	local client = get_client(bufnr)
	if not client then
		vim.notify("impl.nvim: gopls not running", vim.log.levels.WARN)
		callback({})
		return
	end

	local params = { textDocument = vim.lsp.util.make_text_document_params() }

	client.request("textDocument/documentSymbol", params, function(err, result)
		if err or not result then
			callback({})
			return
		end

		-- Gather methods of this struct
		local struct_methods = {}
		for _, symbol in ipairs(result) do
			if symbol.kind == 23 and symbol.name == struct_name and symbol.children then
				for _, child in ipairs(symbol.children) do
					struct_methods[child.name] = true
				end
			end
		end

		-- Search all workspace interfaces
		client.request("workspace/symbol", { query = "" }, function(err2, workspace_symbols)
			if err2 or not workspace_symbols then
				callback({})
				return
			end

			local interfaces = {}
			local iface_methods = {}

			-- First, collect interface -> methods
			for _, symbol in ipairs(workspace_symbols) do
				if symbol.kind == 11 then
					iface_methods[symbol.name] = {}
					table.insert(interfaces, symbol.name)
				elseif symbol.containerName and iface_methods[symbol.containerName] then
					iface_methods[symbol.containerName][symbol.name] = true
				end
			end

			-- Compare struct methods to each interface
			local implemented = {}
			for iface, methods in pairs(iface_methods) do
				local ok = true
				for mname, _ in pairs(methods) do
					if not struct_methods[mname] then
						ok = false
						break
					end
				end
				if ok and next(methods) ~= nil then
					table.insert(implemented, iface)
				end
			end

			callback(implemented)
		end, bufnr)
	end, bufnr)
end
function M.refresh()
	vim.notify("impl.nvim: loading interfaces", vim.log.levels.INFO)
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "go" then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local ok, parser = pcall(ts.get_parser, bufnr, "go")
	if not ok then
		vim.notify("impl.nvim: treesitter parser not found for Go", vim.log.levels.WARN)
		return
	end

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

	for id, node in query:iter_captures(root, bufnr, 0, -1) do
		if query.captures[id] == "name" then
			local struct_name = ts.get_node_text(node, bufnr)
			local row = select(1, node:start())

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
			if client and client.name == "gopls" then
				vim.notify("impl.nvim: gopls loaded", vim.log.levels.INFO)
				vim.defer_fn(M.refresh, 500)
			end
		end,
	})

	vim.api.nvim_create_user_command("ImplRefresh", function()
		M.refresh()
	end, {})
end

return M
