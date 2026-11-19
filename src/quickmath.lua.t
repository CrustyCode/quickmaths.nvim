##quickmath
@../lua/quickmath/init.lua=
-- Generated using ntangle.nvim
@variables
@evaluate_tagged_math
@start_session
@functions
return {
@export_symbols
}

@variables+=
local namespace = vim.api.nvim_create_namespace("quickmath")
local sessions = {}

@evaluate_tagged_math+=
local function tagged_expressions(lines)
	local expressions = {}
	local pending

	for row, line in ipairs(lines) do
		local column = 1
		while true do
			local first, last, closing = line:find("<(/?)math>", column)
			if pending then
				local expression = vim.trim(line:sub(column, first and first - 1))
				if expression ~= "" then
					table.insert(pending, { row = row, text = expression })
				end
			end

			if not first then
				break
			end
			if closing == "" then
				pending = {}
			elseif pending then
				vim.list_extend(expressions, pending)
				pending = nil
			end
			column = last + 1
		end
	end

	return expressions
end

local function draw_results(buf, results, selected_row)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	for row, result in pairs(results) do
		local highlight = row == selected_row and "Visual" or "Special"
		vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
			virt_text = {{ result, highlight }},
		})
	end
end

local function evaluate(expressions)
	if #expressions == 0 then
		return {}
	end

	local code = {}
	local anonymous = 0
	for i, expression in ipairs(expressions) do
		local name = expression.text:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=")
		if name then
			code[i] = expression.text
		else
			anonymous = anonymous + 1
			name = ("anon%d"):format(anonymous)
			code[i] = name .. " = " .. expression.text
		end
		expression.name = name
	end

	local env = setmetatable({ vec = vec }, { __index = _G })
	for name, fn in pairs(math) do
		env[name] = fn
	end

	local chunk, err = loadstring(table.concat(code, "\n"), "=quickmath")
	if chunk then
		local ok
		ok, err = pcall(setfenv(chunk, env))
		if ok then
			err = nil
		end
	end

	if err then
		err = tostring(err)
		local index = tonumber(err:match("^quickmath:(%d+):"))
		local expression = expressions[index] or expressions[#expressions]
		return { [expression.row] = err:gsub("[\r\n]+", " ") }
	end

	local results = {}
	for _, expression in ipairs(expressions) do
		local value = rawget(env, expression.name)
		local kind = type(value)
		if kind == "number" or (kind == "table" and (value.is_complex or isvec(value))) then
			local row = expression.row
			local result = tostring(value)
			results[row] = results[row] and (results[row] .. " | " .. result) or result
		end
	end
	return results
end

@start_session+=
local function StartSession()
	local buf = vim.api.nvim_get_current_buf()
	if sessions[buf] then
		return
	end

	local session = {}
	sessions[buf] = session
	local function refresh()
		if sessions[buf] ~= session or not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
		session.results = evaluate(tagged_expressions(lines))
		draw_results(buf, session.results)
	end

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = vim.schedule_wrap(refresh),
		on_detach = function()
			sessions[buf] = nil
		end,
	})
	@bind_select_virtual_keymap
	refresh()
end

@export_symbols+=
StartSession = StartSession,
