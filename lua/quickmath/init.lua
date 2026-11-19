-- Generated using ntangle.nvim
local namespace = vim.api.nvim_create_namespace("quickmath")
local sessions = {}

local vector = {}
vector.__index = vector

local function tagged_expressions(lines)
	local expressions = {}
	local pending

	for row, line in ipairs(lines) do
		local column = 1
		while true do
			local first, last, closing = line:find("<(/?)maths>", column)
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
	vim.api.nvim_buf_set_keymap(buf, "n", "$", [[:lua require"quickmath".go_eol()<CR>]], { silent = true })
	refresh()
end

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

function vec(...)
  -- Create a new vector
  -- with a given set of values
  -- and a dim of the number of values
  local v = {}
  local dim = 0
  if type(...) == "table" then
    v = ...
    dim = #v
  else
    v = {...}
    dim = select("#", ...)
  end
  v.dim = dim
  setmetatable(v, vector)
  return v
end

function isvec(v)
  return getmetatable(v) == vector
end

local function vecmatch(v1, v2)
  return isvec(v1) and isvec(v2) and v1.dim == v2.dim
end

function vector:clone()
  -- Return a copy of the vector
  local v = {}
  for i = 1, self.dim do
    v[i] = self[i]
  end
  v.dim = self.dim
  setmetatable(v, vector)
  return v
end

function vector:unpack()
  -- Return the values of the vector
  -- as a list of values
  return unpack(self, 1, self.dim)
end

function vector:mag()
  -- Return the magnitude of the vector
  local mag = 0
  for i = 1, self.dim do
    mag = mag + self[i] * self[i]
  end
  return math.sqrt(mag)
end

function vector:magsq()
  -- Return the magnitude squared of the vector
  local mag = 0
  for i = 1, self.dim do
    mag = mag + self[i] * self[i]
  end
  return mag
end

function vector:setmag(mag)
  -- Set the magnitude of the vector
  local magsq = self:magsq()
  if magsq == 0 then
    return self:clone()
  end
  local scale = mag / math.sqrt(magsq)
  return self:scale(scale)
end

function vector:scale(s)
  -- Scale a vector by a scalar value
  -- or another vector (element-wise)
  local v = self:clone()
  if isvec(s) then
    if not vecmatch(self, s) then
      error("Cannot scale vectors of different dimensions")
    end
    for i = 1, self.dim do
      v[i] = v[i] * s[i]
    end
  else
    for i = 1, self.dim do
      v[i] = v[i] * s
    end
  end
  return v
end

function vector:norm()
  -- Normalize the vector
  local mag = self:mag()
  local v = self:clone()
  if mag == 0 then
    return v
  end
  for i = 1, self.dim do
    v[i] = v[i] / mag
  end
  return v
end

function vector:dist(v)
  -- Return the distance between two vectors
  if not vecmatch(self, v) then
    error("Cannot calculate distance between vectors of different dimensions")
  end
  local dist = 0
  for i = 1, self.dim do
    dist = dist + (self[i] - v[i]) * (self[i] - v[i])
  end
  return math.sqrt(dist)
end

function vector:distsq(v)
  -- Return the distance squared between two vectors
  if not vecmatch(self, v) then
    error("Cannot calculate distance between vectors of different dimensions")
  end
  local dist = 0
  for i = 1, self.dim do
    dist = dist + (self[i] - v[i]) * (self[i] - v[i])
  end
  return dist
end

function vector:limit(max)
  -- Limit the magnitude of the vector
  local magsq = self:magsq()
  if magsq > max * max then
    return self:clone():setmag(max)
  end
  return self:clone()
end

function vector:__unm()
  -- Return the negative of the vector
  local v = self:clone()
  for i = 1, self.dim do
    v[i] = -self[i]
  end
  return v
end

function vector:__add(v)
  -- Add two vectors
  if not vecmatch(self, v) then
    error("Cannot add vectors of different dimensions")
  end
  local v3 = self:clone()
  for i = 1, self.dim do
    v3[i] = v3[i] + v[i]
  end
  return v3
end

function vector:__sub(v)
  -- Subtract two vectors
  if not vecmatch(self, v) then
    error("Cannot subtract vectors of different dimensions")
  end
  local v3 = self:clone()
  for i = 1, self.dim do
    v3[i] = v3[i] - v[i]
  end
  return v3
end

function vector:__mul(v)
  -- Calculate the dot product of two vectors
  -- or multiply a vector by a scalar
  if isvec(v) then
    if not vecmatch(self, v) then
      error("Cannot multiply vectors of different dimensions")
    end
    local v3 = 0
    for i = 1, self.dim do
      v3 = v3 + self[i] * v[i]
    end
    return v3
  else
    return self:scale(v)
  end
end

function vector:__tostring()
  -- Return a string representation of the vector
  local s = "("
  for i = 1, self.dim do
    s = s .. tostring(self[i])
    if i ~= self.dim then
      s = s .. ", "
    end
  end
  s = s .. ")"
  return s
end

return {
StartSession = StartSession,
go_eol = go_eol,
}
