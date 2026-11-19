##quickmath
@bind_select_virtual_keymap+=
vim.api.nvim_buf_set_keymap(buf, "n", "$", [[:lua require"quickmath".go_eol()<CR>]], { silent = true })

@functions+=
local function go_eol()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_get_current_line()
	local row, column = unpack(vim.api.nvim_win_get_cursor(0))
	local at_end = vim.str_utfindex(line, column) == vim.str_utfindex(line) - 1
	if not at_end then
		vim.api.nvim_win_set_cursor(0, { row, #line })
		return
	end

	local session = sessions[buf]
	local result = session and session.results[row]
	if result then
		draw_results(buf, session.results, row)
		vim.schedule(function()
			if vim.fn.getchar() == string.byte("y") then
				vim.fn.setreg("+", result)
			end
			if sessions[buf] == session then
				draw_results(buf, session.results)
			end
		end)
	end
end

@export_symbols+=
go_eol = go_eol,
