library(shiny)
library(bslib)
library(shinyjs)
library(promises)
library(commonmark)
library(claudeAgentR)

`%||%` <- function(x, y) if (is.null(x)) y else x

# Render Markdown text as HTML (used for assistant messages)
md_html <- function(text) {
  safe_text <- gsub("<[^>]+>", "", text %||% "", perl = TRUE)
  HTML(markdown_html(safe_text, extensions = TRUE, smart = TRUE))
}

# Safe error message extraction — works for both condition objects and strings
err_msg <- function(err) {
  if (inherits(err, "condition")) conditionMessage(err) else as.character(err)
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- page_sidebar(
  title    = "Claude Chat",
  fillable = TRUE,
  theme    = bs_theme(
    bootswatch = "flatly",
    primary    = "#1a73e8"
  ),

  useShinyjs(),

  # highlight.js for code blocks inside assistant messages
  tags$head(
    tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css"
    ),
    tags$link(
      rel  = "stylesheet",
      href = "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css"
    ),
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
    ),
    tags$style(HTML("
      /* ── Chat bubbles ─────────────────────────────────────── */
      .chat-msg               { margin-bottom: 14px; }
      .chat-msg.user-msg      { text-align: right; }
      .chat-msg.asst-msg,
      .chat-msg.thinking-msg,
      .chat-msg.error-msg     { text-align: left; }

      .bubble {
        display: inline-block;
        max-width: 82%;
        padding: 10px 14px;
        border-radius: 16px;
        font-size: 0.88rem;
        line-height: 1.6;
        text-align: left;
        word-wrap: break-word;
      }

      .user-msg     .bubble { background:#1a73e8; color:#fff;    border-bottom-right-radius:4px; }
      .asst-msg     .bubble { background:#f1f3f4; color:#212529; border-bottom-left-radius:4px; }
      .thinking-msg .bubble { background:#f1f3f4; padding:14px;  border-bottom-left-radius:4px; }
      .error-msg    .bubble {
        background:#fdecea; color:#c62828;
        border:1px solid #f5c6cb; border-bottom-left-radius:4px;
      }

      /* ── Markdown inside assistant bubbles ────────────────── */
      .asst-msg .bubble p:last-child { margin-bottom: 0; }
      .asst-msg .bubble pre {
        background: #fff;
        border: 1px solid #e0e0e0;
        border-radius: 6px;
        padding: 10px;
        overflow-x: auto;
        margin: 8px 0;
      }
      .asst-msg .bubble code { font-size: 0.81rem; }
      .asst-msg .bubble ul,
      .asst-msg .bubble ol   { padding-left: 1.3em; margin-bottom: 0.5em; }
      .asst-msg .bubble table {
        border-collapse: collapse;
        font-size: 0.82rem;
        margin-bottom: 0.5em;
      }
      .asst-msg .bubble th,
      .asst-msg .bubble td   { border:1px solid #ddd; padding: 4px 8px; }
      .asst-msg .bubble th   { background: #f5f5f5; }

      /* ── Typing animation ─────────────────────────────────── */
      .dot {
        display: inline-block;
        width: 7px; height: 7px;
        border-radius: 50%;
        background: #bbb;
        margin: 0 2px;
        animation: bounce 1.2s infinite;
      }
      .dot:nth-child(2) { animation-delay: .2s; }
      .dot:nth-child(3) { animation-delay: .4s; }
      @keyframes bounce {
        0%, 60%, 100% { transform: translateY(0); opacity: .4; }
        30%            { transform: translateY(-5px); opacity: 1; }
      }

      /* ── Input area ───────────────────────────────────────── */
      #user_input {
        resize: none;
        border-radius: 20px;
        width: 100% !important;
      }
      #chat-input-row .shiny-input-container {
        margin-bottom: 0 !important;
        width: 100%;
      }
    "))
  ),

  # ── Sidebar ──────────────────────────────────────────────────────────────
  sidebar = sidebar(
    title = "Settings",
    width = 270,
    open  = "desktop",

    selectInput("model", "Model",
      choices = c(
        "Claude Sonnet 4.6" = "claude-sonnet-4-6",
        "Claude Opus 4.7"   = "claude-opus-4-7",
        "Claude Haiku 4.5"  = "claude-haiku-4-5-20251001"
      ),
      selected = "claude-sonnet-4-6"
    ),

    textAreaInput("system_prompt", "System prompt",
      placeholder = "You are a helpful assistant.",
      rows = 4
    ),

    helpText("Settings apply from the next new conversation."),

    hr(),

    actionButton("new_chat", "＋ New conversation",
      class = "btn-outline-secondary w-100"
    ),

    hr(),

    uiOutput("cost_ui")
  ),

  # ── Main chat card ────────────────────────────────────────────────────────
  card(
    fill = TRUE,
    card_body(
      fill     = TRUE,
      fillable = TRUE,
      class    = "d-flex flex-column p-0",

      # Scrollable message area
      div(
        id    = "chat-box",
        class = "flex-grow-1 overflow-auto p-3",
        style = "min-height: 0;",
        uiOutput("chat_ui")
      ),

      # Input row pinned to bottom
      div(
        class = "border-top bg-white p-3",
        div(
          id    = "chat-input-row",
          class = "d-flex gap-2 align-items-end",
          div(
            class = "flex-grow-1",
            style = "min-width: 0;",
            textAreaInput("user_input", NULL,
              placeholder = "Message Claude… (Enter = send, Shift+Enter = newline)",
              rows = 1
            )
          ),
          actionButton("send", label = NULL,
            icon  = icon("paper-plane"),
            class = "btn-primary rounded-circle",
            style = "width:42px; height:42px; padding:0; flex-shrink:0;"
          )
        )
      )
    )
  ),

  # ── Client-side scripts ───────────────────────────────────────────────────
  tags$script(HTML("
    // Enter to send (Shift+Enter = newline)
    $(document).on('keydown', '#user_input', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        $('#send').click();
      }
    });

    // Auto-resize textarea while typing
    $(document).on('input', '#user_input', function() {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 120) + 'px';
    });

    // Auto-scroll + re-run highlight.js after Shiny updates DOM
    var chatBox = document.getElementById('chat-box');
    if (chatBox) {
      new MutationObserver(function() {
        chatBox.scrollTop = chatBox.scrollHeight;
        chatBox.querySelectorAll('pre code:not(.hljs)').forEach(function(el) {
          hljs.highlightElement(el);
        });
      }).observe(chatBox, { childList: true, subtree: true });
    }
  "))
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  client     <- NULL
  connected  <- reactiveVal(FALSE)
  history    <- reactiveVal(list())
  waiting    <- reactiveVal(FALSE)
  total_cost <- reactiveVal(0)

  make_client <- function() {
    sp <- trimws(input$system_prompt %||% "")
    claude_async_client(
      model         = input$model %||% "claude-sonnet-4-6",
      system_prompt = if (nzchar(sp)) sp else NULL
    )
  }

  add_msg <- function(role, content) {
    history(c(history(), list(list(role = role, content = content))))
  }

  replace_last <- function(role, content) {
    h <- history()
    h[[length(h)]] <- list(role = role, content = content)
    history(h)
  }

  reset_client <- function() {
    if (!is.null(client)) {
      client$close()
      client <<- NULL
    }
    connected(FALSE)
  }

  fail_request <- function(message, reset_connection = TRUE) {
    if (reset_connection) {
      reset_client()
    }
    replace_last("error", message)
    set_waiting(FALSE)
  }

  set_waiting <- function(on) {
    waiting(on)
    if (on) disable("send") else enable("send")
  }

  # ── Send ────────────────────────────────────────────────────────────────

  observeEvent(input$send, {
    req(!waiting())
    msg <- trimws(input$user_input)
    req(nzchar(msg))

    if (is.null(client)) client <<- make_client()

    updateTextAreaInput(session, "user_input", value = "")
    runjs("var el=document.getElementById('user_input'); el.style.height='auto';")
    add_msg("user", msg)
    add_msg("thinking", NULL)
    set_waiting(TRUE)

    is_first_turn <- !connected()
    p <- if (is_first_turn) client$connect(msg) else client$query(msg)

    p %...>% (function(result) {
      tryCatch({
        if (is_first_turn) connected(TRUE)
        replace_last("assistant", result$text %||% "")
        total_cost(total_cost() + (
          result$result$total_cost_usd %||%
          result$result$cost_usd %||%
          0
        ))
        set_waiting(FALSE)
      }, error = function(err) {
        fail_request(
          paste("App error:", conditionMessage(err)),
          reset_connection = is_first_turn
        )
      })
    }) %...!% (function(err) {
      fail_request(err_msg(err), reset_connection = is_first_turn)
    })
  })

  # ── New conversation ─────────────────────────────────────────────────────

  observeEvent(input$new_chat, {
    req(!waiting())
    reset_client()
    history(list())
    total_cost(0)
  })

  # ── Render chat ──────────────────────────────────────────────────────────

  output$chat_ui <- renderUI({
    msgs <- history()
    if (length(msgs) == 0) {
      return(div(
        class = "text-center text-muted py-5",
        tags$i(class = "bi bi-chat-dots fs-1 d-block mb-3", style = "opacity:.3;"),
        p("Start a conversation with Claude.")
      ))
    }

    lapply(msgs, function(m) {
      switch(m$role,
        user = div(class = "chat-msg user-msg",
          div(class = "bubble", m$content)
        ),
        assistant = div(class = "chat-msg asst-msg",
          div(class = "bubble", md_html(m$content))
        ),
        thinking = div(class = "chat-msg thinking-msg",
          div(class = "bubble",
            span(class = "dot"), span(class = "dot"), span(class = "dot")
          )
        ),
        error = div(class = "chat-msg error-msg",
          div(class = "bubble",
            tags$i(class = "bi bi-exclamation-circle me-1"),
            m$content
          )
        )
      )
    })
  })

  # ── Cost display ─────────────────────────────────────────────────────────

  output$cost_ui <- renderUI({
    cost <- total_cost()
    if (cost == 0) return(NULL)
    div(class = "text-muted text-center small",
      sprintf("Session cost: $%.5f", cost)
    )
  })

  # ── Cleanup ──────────────────────────────────────────────────────────────

  session$onSessionEnded(function() {
    if (!is.null(client)) client$close()
  })
}

shinyApp(ui, server)
