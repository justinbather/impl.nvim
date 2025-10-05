if vim.g.loaded_impl then
	return
end
vim.g.loaded_impl = true

require("impl").setup()
