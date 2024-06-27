# llm.nvim

`llm.nvim` is a Neovim plugin that integrates AI-powered chat functionality directly into your editor. It allows you to interact with large language models like DeepSeek Coder or Claude, enhancing your coding experience with AI assistance.

## Features

- AI-powered chat interface within Neovim
- Support for multiple AI models (DeepSeek Coder, Claude)
- Conversation history management
- Customizable system prompts
- Markdown rendering for better readability

## Demo

[Demo](https://github.com/skromez/llm.nvim/assets/42495435/f6a0b7aa-360b-4908-8bfc-96c60f1a0cce)

## Requirements

- Neovim 0.5+
- [nvim-nio](https://github.com/nvim-neotest/nvim-nio)
- An API key for OpenRouter

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "skromez/llm.nvim",
  dependencies = { "nvim-neotest/nvim-nio" },
  config = function()
    require("llm").setup({
      api_key = "your-openrouter-api-key",
      model = "deepseek/deepseek-coder", -- or "anthropic/claude-3-sonnet"
    })
  end,
}
```

## Usage

After installation, you can open the AI chat window with the following command:

```vim
:lua require("llm").open_chat()
```

You might want to map this to a keybinding for easier access:

```lua
vim.keymap.set("n", "<leader>ai", require("llm").open_chat, { desc = "Open AI Chat" })
```

In the chat window:

- Type your message and press `<Enter>` to send it to the AI
- Press `<C-q>` to cancel the current response

## Configuration

You can configure the plugin by passing options to the `setup` function:

```lua
require("llm").setup({
  api_key = "your-openrouter-api-key",
  model = "deepseek/deepseek-coder",
  system_prompt = "Your custom system prompt here",
})
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
