#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default = NULL, required = FALSE) {
  idx <- match(flag, args)
  if (!is.na(idx) && idx < length(args)) {
    return(args[[idx + 1]])
  }
  if (required) {
    stop(sprintf("Missing required argument: %s", flag), call. = FALSE)
  }
  default
}

read_txt <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return("")
  tryCatch(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
           error = function(e) "")
}

extract_content <- function(content) {
  if (is.character(content) && length(content) >= 1) {
    return(content[[1]])
  }
  if (is.list(content)) {
    parts <- vapply(content, function(item) {
      if (is.list(item) && !is.null(item$text)) as.character(item$text) else as.character(item)
    }, character(1), USE.NAMES = FALSE)
    return(paste(parts, collapse = "\n"))
  }
  as.character(content)
}

base_review_path <- get_arg("--base-review", required = TRUE)
output_path <- get_arg("--output", required = TRUE)
check_file <- get_arg("--check-file", default = "")
bioccheck_file <- get_arg("--bioccheck-file", default = "")
coverage_file <- get_arg("--coverage-file", default = "")
guidelines_file <- get_arg("--guidelines-file", default = ".github/bioc-review-guidelines.instructions.md")
model <- get_arg("--model", default = Sys.getenv("GITHUB_MODEL", "gpt-4o"))
max_prompt_chars_arg <- get_arg("--max-prompt-chars", default = "")
max_tokens_arg <- get_arg("--max-tokens", default = "")
api_url <- get_arg("--api-url", default = "")

# Auto-detect provider and configure settings based on model
provider <- if (grepl("gemini", model, ignore.case = TRUE)) "gemini" else "github"

if (provider == "gemini") {
  # Google Gemini configuration
  # API key from: https://aistudio.google.com/app/api-keys
  if (!nzchar(api_url)) api_url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
  max_prompt_chars <- if (nzchar(max_prompt_chars_arg)) as.integer(max_prompt_chars_arg) else 400000L  # ~1M tokens
  max_tokens <- if (nzchar(max_tokens_arg)) as.integer(max_tokens_arg) else 28000L
  token <- Sys.getenv("GEMINI_API_KEY", unset = "")
  token_param <- "key"
} else {
  # GitHub Models configuration
  if (!nzchar(api_url)) api_url <- "https://models.inference.ai.azure.com/chat/completions"
  max_prompt_chars <- if (nzchar(max_prompt_chars_arg)) as.integer(max_prompt_chars_arg) else 28000L  # ~7K tokens (8K limit with margin)
  max_tokens <- if (nzchar(max_tokens_arg)) as.integer(max_tokens_arg) else 28000L
  token <- Sys.getenv("GITHUB_TOKEN", unset = "")
  token_param <- "bearer"
}

if (is.na(max_prompt_chars) || max_prompt_chars <= 0) {
  max_prompt_chars <- if (provider == "gemini") 400000L else 28000L
}
if (is.na(max_tokens) || max_tokens <= 0) max_tokens <- 28000L

message(sprintf("Using provider: %s, model: %s", provider, model))
message(sprintf("Token budget: %d chars (~%d tokens)", max_prompt_chars, as.integer(max_prompt_chars / 4)))

base_review <- read_txt(base_review_path)
context_sections <- list(
  list(title = "Bioconductor Review Guidelines", text = read_txt(guidelines_file)),
  list(title = "Base Static Analysis", text = base_review),
  list(title = "R CMD check results", text = read_txt(check_file)),
  list(title = "BiocCheck results", text = read_txt(bioccheck_file)),
  list(title = "Coverage summary", text = read_txt(coverage_file))
)

prompt_parts <- c(
  "You are preparing an actionable Bioconductor package review.",
  "Use the provided static analysis and artifacts to produce a concise but detailed markdown review.",
  "Prioritize: required fixes first, then strong recommendations, then minor suggestions.",
  "Do not invent facts. If evidence is missing, say so clearly.",
  "Format with sections and bullets.",
  "Do not include any attribution footer (e.g., 'Review performed by...') - this will be added automatically.",
  "",
  "## Input Context"
)

for (section in context_sections) {
  if (!nzchar(section$text)) next
  prompt_parts <- c(prompt_parts, sprintf("\n### %s\n", section$title), section$text)
}

full_prompt <- paste(prompt_parts, collapse = "\n")
truncated <- FALSE
omitted_chars <- 0L
if (nchar(full_prompt, type = "chars", allowNA = FALSE, keepNA = FALSE) > max_prompt_chars) {
  truncated <- TRUE
  omitted_chars <- nchar(full_prompt, type = "chars", allowNA = FALSE, keepNA = FALSE) - max_prompt_chars
  full_prompt <- substr(full_prompt, 1, max_prompt_chars)
}

# Build payload based on provider
if (provider == "gemini") {
  # Gemini API format
  system_instruction <- "You are an expert Bioconductor package reviewer. Produce a markdown review with concrete, evidence-based guidance."
  payload <- toJSON(
    list(
      contents = list(
        list(
          parts = list(
            list(text = paste(system_instruction, "\n\n", full_prompt, sep = ""))
          )
        )
      ),
      generationConfig = list(
        temperature = 0.2,
        maxOutputTokens = max_tokens
      )
    ),
    auto_unbox = TRUE
  )
} else {
  # OpenAI/GitHub Models format
  payload <- toJSON(
    list(
      model = model,
      messages = list(
        list(
          role = "system",
          content = "You are an expert Bioconductor package reviewer. Produce a markdown review with concrete, evidence-based guidance."
        ),
        list(role = "user", content = full_prompt)
      ),
      temperature = 0.2,
      max_tokens = max_tokens
    ),
    auto_unbox = TRUE,
    null = "null"
  )
}

llm_status <- "success"
llm_text <- ""
finish_reason <- "UNKNOWN"

tryCatch({
  payload_file <- tempfile(fileext = ".json")
  writeLines(payload, payload_file, useBytes = TRUE)

  # Build curl command based on provider
  if (provider == "gemini") {
    # Gemini uses API key as query parameter
    api_url_with_key <- paste0(api_url, "?key=", token)
    curl_cmd <- sprintf(
      "curl -sS -X POST -H 'Content-Type: application/json' --data-binary '@%s' '%s'",
      payload_file,
      api_url_with_key
    )
  } else {
    # GitHub Models uses Bearer token
    curl_cmd <- sprintf(
      "curl -sS -X POST -H 'Authorization: Bearer %s' -H 'Content-Type: application/json' --data-binary '@%s' '%s'",
      token,
      payload_file,
      api_url
    )
  }

  message(sprintf("Calling %s API with model: %s", provider, model))
  response_lines <- system(curl_cmd, intern = TRUE)
  status <- attr(response_lines, "status")
  if (!is.null(status) && status != 0) {
    stop(sprintf("curl exited with status %s", status))
  }

  response_text <- paste(response_lines, collapse = "\n")
  message("API response length: ", nchar(response_text), " characters")

  body <- fromJSON(response_text, simplifyVector = FALSE)

  # Check if API returned an error
  if (!is.null(body$error)) {
    error_msg <- if (is.list(body$error) && !is.null(body$error$message)) {
      body$error$message
    } else if (is.character(body$error)) {
      body$error
    } else {
      toJSON(body$error, auto_unbox = TRUE)
    }
    stop(sprintf("API returned error: %s", error_msg))
  }

  # Parse response based on provider
  if (provider == "gemini") {
    # Gemini response format: candidates[].content.parts[].text
    if (is.null(body$candidates) || length(body$candidates) == 0) {
      stop(sprintf("API response missing candidates. Response keys: %s",
                   paste(names(body), collapse = ", ")))
    }
    candidate <- body$candidates[[1]]

    # Check finish reason
    finish_reason <- candidate$finishReason
    if (!is.null(finish_reason)) finish_reason <<- as.character(finish_reason)
    if (!is.null(finish_reason)) {
      message(sprintf("Gemini finish reason: %s", finish_reason))
      if (finish_reason != "STOP") {
        message(sprintf("WARNING: Response finished with %s instead of STOP - may be incomplete", finish_reason))
      }
    }

    content <- candidate$content$parts[[1]]$text
  } else {
    # GitHub Models/OpenAI format: choices[].message.content
    if (is.null(body$choices) || length(body$choices) == 0) {
      stop(sprintf("API response missing choices. Response keys: %s",
                   paste(names(body), collapse = ", ")))
    }
    if (!is.null(body$choices[[1]]$finish_reason)) {
      finish_reason <<- as.character(body$choices[[1]]$finish_reason)
    }
    content <- body$choices[[1]]$message$content
  }

  if (is.null(content) || !nzchar(as.character(content))) {
    stop("API response content is empty or null")
  }

  llm_text <- extract_content(content)
  message("Extracted LLM text length: ", nchar(llm_text), " characters")

  if (!nzchar(llm_text)) {
    stop("Extracted content is empty after processing")
  }
}, error = function(e) {
  message("ERROR: ", conditionMessage(e))
  llm_status <<- "fallback"
  finish_reason <<- "ERROR"
  llm_text <<- paste0(
    "## LLM enhancement unavailable\n",
    "- Attempted model: `", model, "`\n",
    "- Error: `", conditionMessage(e), "`\n\n",
    "The rule-based review is provided below.\n\n",
    base_review
  )
})

provider_name <- if (provider == "gemini") "Google Gemini" else "GitHub Models"
header_lines <- c(
  sprintf("*Review enhanced by **%s (%s)** on %s.*", model, provider_name, as.character(Sys.Date())),
  sprintf("*Finish reason: `%s`.*", finish_reason),
  ""
)

if (truncated) {
  header_lines <- c(
    header_lines,
    "> ⚠️ **Warning: Input context was truncated before sending to the model.**",
    sprintf(
      "> The prompt exceeded `%s` characters; approximately `%s` trailing characters were omitted.",
      max_prompt_chars,
      omitted_chars
    ),
    "> This review may miss findings that appear only in the omitted portion of the artifacts.",
    ""
  )
}

writeLines(c(header_lines, trimws(llm_text), ""), output_path, useBytes = TRUE)

github_output <- Sys.getenv("GITHUB_OUTPUT", unset = "")
if (nzchar(github_output)) {
  finish_reason_output <- gsub("[\r\n]+", " ", finish_reason)
  write(
    c(
      sprintf("review_file=%s", output_path),
      sprintf("llm_status=%s", llm_status),
      sprintf("truncated=%s", if (truncated) "true" else "false"),
      sprintf("omitted_chars=%s", omitted_chars),
      sprintf("finish_reason=%s", finish_reason_output)
    ),
    file = github_output,
    append = TRUE
  )
}