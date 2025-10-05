local M = {}

local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("impl")

function M.get_implemented(bufnr, struct_name, callback)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then
    callback({})
    return
  end

  -- Find struct position in file
  local parser = ts.get_parser(bufnr, "go")
  local tree = parser:parse()[1]
  local root = tree:root()

  local query = ts.query.parse(
    "go",
    [[
      (type_spec
        name: (type_identifier) @name
        type: (struct_type))
    ]]
  )

  local byte_offset = nil
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "name" then
      local name = ts.get_node_text(node, bufnr)
      if name == struct_name then
        local row, col = node:start()
        -- Get byte offset for gopls type query
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        byte_offset = vim.str_byteindex(line, col)
        break
      end
    end
  end

  if not byte_offset then
    vim.notify("impl.nvim: could not locate struct position", vim.log.levels.WARN)
    callback({})
    return
  end

  local cmd = {
    "gopls",
    "type",
    "-json",
    string.format("%s:#%d", filename, byte_offset),
  }

  vim.system(cmd, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout or res.stdout == "" then
      callback({})
      return
    end

    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or not data or not data.Implements then
      callback({})
      return
    end

    local interfaces = {}
    for _, impl in ipairs(data.Implements) do
      table.insert(interfaces, impl.Name)
    end

    callback(interfaces)
  end)
end
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
