local function start_session()
  require("quickmath").StartSession()
end

vim.api.nvim_create_user_command("Quickmaths", start_session, { desc = "Show live results from maths tags" })
vim.api.nvim_create_user_command("Quickmath", start_session, { desc = "Alias for Quickmaths" })
