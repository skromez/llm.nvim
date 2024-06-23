local M = {}

local nio = require("nio")

local config = {
	api_key = "",
	model = "deepseek/deepseek-coder",
	system_prompt = [[
You are an AI programming assistant integrated into a code editor. Your purpose is to help the user with programming tasks as they write code.
Key capabilities:
- Thoroughly analyze the user's code and provide insightful suggestions for improvements related to best practices, performance, readability, and maintainability. Explain your reasoning.
- Answer coding questions in detail, using examples from the user's own code when relevant. Break down complex topics step-by-step.
- Spot potential bugs and logical errors. Alert the user and suggest fixes.
- Upon request, add helpful comments explaining complex or unclear code.
- Suggest relevant documentation, StackOverflow answers, and other resources related to the user's code and questions.
- Engage in back-and-forth conversations to understand the user's intent and provide the most helpful information.
- Keep concise and use markdown.
- When asked to create code, only generate the code. No bugs.
- Think step by step
    ]],
}

local is_cancelled = false
local conversation_history = {}

local function is_window_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function is_buffer_valid(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function append_header(bufnr, header_text)
	if not is_buffer_valid(bufnr) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, { "" })

	local icon = header_text:find("llm") and "" or ""
	local ns_id = vim.api.nvim_create_namespace("header")

	vim.api.nvim_set_hl(0, "text", { fg = "#B3C121", bold = true })
	vim.api.nvim_set_hl(0, "line", { fg = "#FF8C00" })

	vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_count, 0, {
		virt_text = {
			{ string.format("%s %s ", icon, header_text), "text" },
			{ string.rep("─", 1000), "line" },
		},
		virt_text_pos = "overlay",
		hl_mode = "combine",
		priority = 100,
	})

	local win = vim.api.nvim_get_current_win()
	line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, line_count + 1, -1, false, { "", "" })
	vim.api.nvim_win_set_cursor(win, { line_count + 2, 0 })
end

local function auto_scroll(win, bufnr)
	local window_height = vim.api.nvim_win_get_height(win)
	local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
	local buffer_line_count = vim.api.nvim_buf_line_count(bufnr)

	if (buffer_line_count - cursor_line) < (window_height * 0.2) then
		vim.api.nvim_win_call(win, function()
			vim.cmd("normal! zz")
		end)
	end
end

local function append_chunk_to_buffer(win, bufnr, chunk)
	if not is_window_valid(win) or not is_buffer_valid(bufnr) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

	local lines = vim.split(chunk, "\n")
	if #lines == 1 then
		vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { last_line .. lines[1] })
	else
		vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { last_line .. lines[1] })
		vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, vim.list_slice(lines, 2))
	end

	auto_scroll(win, bufnr)
end

local function append_padding_to_buffer(bufnr)
	if not is_buffer_valid(bufnr) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local last_line_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]
	line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, line_count, -1, false, { "" })
	local win = vim.api.nvim_get_current_win()

	append_header(bufnr, "user")

	line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_win_set_cursor(win, { line_count, #last_line_content })
end

local function send_to_llm(bufnr, win, text)
	is_cancelled = false
	table.insert(conversation_history, { role = "user", content = text })

	local messages = {
		{ role = "system", content = config.system_prompt },
	}
	for _, msg in ipairs(conversation_history) do
		table.insert(messages, msg)
	end

	local data = {
		model = config.model,
		messages = messages,
		stream = true,
	}

	nio.run(function()
		local response = nio.process.run({
			cmd = "curl",
			args = {
				"-N",
				"-X",
				"POST",
				"-H",
				"Content-Type: application/json",
				"-H",
				"Authorization: Bearer " .. config.api_key,
				"-d",
				vim.fn.json_encode(data),
				"https://openrouter.ai/api/v1/chat/completions",
			},
		})
		local buffer = ""
		local is_first_chunk = true
		local assistant_response = ""
		if is_buffer_valid(bufnr) then
			append_header(bufnr, "llm")
		else
			return
		end
		while true do
			if is_cancelled then
				vim.schedule(function()
					append_chunk_to_buffer(win, bufnr, " [Response cancelled]")
					vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
					append_header(bufnr, "user")
					local line_count = vim.api.nvim_buf_line_count(bufnr)
					vim.api.nvim_win_set_cursor(win, { line_count, 0 })
				end)
				break
			end

			if not is_window_valid(win) or not is_buffer_valid(bufnr) then
				break
			end

			local chunk = response.stdout.read(1024)
			if not chunk then
				break
			end
			buffer = buffer .. chunk
			local lines = {}
			for line in buffer:gmatch("(.-)\r?\n") do
				table.insert(lines, line)
			end
			buffer = buffer:sub(#table.concat(lines, "\n") + 1)
			for _, line in ipairs(lines) do
				local data_start = line:find("data: ")
				if line:find('"error": {"') then
					if is_window_valid(win) and is_buffer_valid(bufnr) then
						vim.schedule(function()
							local data_json = vim.fn.json_decode(line:sub(data_start + 6))
							local error_message = data_json.error.message
							append_chunk_to_buffer(win, bufnr, "[" .. error_message .. "]")
						end)
					end
					return
				end

				if line == "data: [DONE]" then
					if is_buffer_valid(bufnr) then
						vim.schedule(function()
							table.insert(conversation_history, { role = "assistant", content = assistant_response })
							append_padding_to_buffer(bufnr)
						end)
					end
					return
				else
					if data_start then
						local json_str = line:sub(data_start + 6)
						nio.sleep(1)
						if is_window_valid(win) and is_buffer_valid(bufnr) then
							vim.schedule(function()
								local success, data_json = pcall(vim.fn.json_decode, json_str)
								if success and data_json.choices and data_json.choices[1].delta.content then
									local content = data_json.choices[1].delta.content
									if is_first_chunk and content:match("^%s") and config.model:find("deepseek") then
										content = content:sub(2)
										is_first_chunk = false
									end
									assistant_response = assistant_response .. content
									append_chunk_to_buffer(win, bufnr, content)
								end
							end)
						else
							return
						end
					end
				end
			end
		end
	end)
end

local function process_text(bufnr, win)
	is_cancelled = false

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local ns_id = vim.api.nvim_create_namespace("header")
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

	if #extmarks > 0 then
		local last_header_line = extmarks[#extmarks][2]

		local content_lines = {}
		for i = last_header_line + 2, #lines do
			table.insert(content_lines, lines[i])
		end

		local text = table.concat(content_lines, "\n")

		send_to_llm(bufnr, win, text)
	end
end

function M.create_chat_window()
	local width = math.floor(vim.o.columns * 0.3)
	local buf = vim.api.nvim_create_buf(false, true)

	vim.cmd("botright vsplit")
	local win = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, width)

	local buf_options = {
		buftype = "nofile",
		bufhidden = "hide",
		swapfile = false,
		modifiable = true,
		filetype = "markdown",
	}
	for option, value in pairs(buf_options) do
		vim.api.nvim_set_option_value(option, value, { buf = buf })
	end

	local win_options = {
		wrap = true,
		cursorline = true,
		number = false,
		relativenumber = false,
	}
	for option, value in pairs(win_options) do
		vim.api.nvim_set_option_value(option, value, { win = win })
	end

	vim.api.nvim_command("TSBufEnable highlight")

	vim.keymap.set({ "n", "v" }, "d", "<NOP>", { buffer = buf, noremap = true, silent = true })
	vim.keymap.set({ "n", "v" }, "dd", "<NOP>", { buffer = buf, noremap = true, silent = true })
	vim.keymap.set({ "n", "v" }, "D", "<NOP>", { buffer = buf, noremap = true, silent = true })

	local keymaps = {
		{
			mode = "n",
			lhs = "<CR>",
			rhs = function()
				local line_count = vim.api.nvim_buf_line_count(buf)
				vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "" })
				process_text(buf, win)
			end,
		},
		{
			mode = { "n", "i" },
			lhs = "<C-q>",
			rhs = function()
				is_cancelled = true
			end,
		},
	}

	for _, keymap in ipairs(keymaps) do
		vim.keymap.set(keymap.mode, keymap.lhs, keymap.rhs, {
			noremap = true,
			silent = true,
			buffer = buf,
		})
	end

	append_header(buf, "user")
	vim.cmd("startinsert")

	conversation_history = {} -- Reset conversation history when creating a new chat window
end

function M.open_chat()
	M.create_chat_window()
end

function M.setup(opts)
	config.api_key = opts.api_key or config.api_key
	config.model = opts.model or config.model
	config.system_prompt = opts.system_prompt or config.system_prompt
end

return M
