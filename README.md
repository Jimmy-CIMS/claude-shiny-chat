# Claude Shiny Chat

A simple multi-turn chat application powered by [Claude AI](https://www.anthropic.com/claude), built with R Shiny and the [claudeAgentR](../claude-code-sdk-r) SDK.

## Requirements

- R >= 4.1.0
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
  ```bash
  npm install -g @anthropic-ai/claude-code
  claude login
  ```
- R packages: `shiny`, `bslib`, `shinyjs`, `promises`, `commonmark`, `claudeAgentR`

## Installation

```r
# Install dependencies
install.packages(c("shiny", "bslib", "shinyjs", "promises", "commonmark"))

# Install claudeAgentR from GitHub
devtools::install_github("Jimmy-CIMS/claude-code-sdk-r")
```

## Running the App

```r
shiny::runApp(".")
```

Or open `claude-shiny-chat.Rproj` in RStudio and click **Run App**.

## Features

- Multi-turn conversation with context preserved across messages
- Enter to send, Shift+Enter for newline
- "…" placeholder while waiting for Claude's response
- Send button disabled during response to prevent double-submission
- Error messages displayed inline in the chat
- **＋ New conversation** button to reset and start fresh
- Auto-scrolls to latest message
- Per-session Claude subprocess — safe for multiple concurrent users

## Architecture

Each Shiny session gets its own `ClaudeAsyncClient`. Each chat turn starts a
fresh Claude CLI subprocess in `--print --output-format stream-json` mode, and
follow-up turns resume the same Claude session automatically through the SDK.
Responses are delivered as promises, keeping the Shiny event loop non-blocking.

```
Browser → Shiny server → ClaudeAsyncClient → Claude CLI subprocess
                       ←  promise (text)   ←
```
