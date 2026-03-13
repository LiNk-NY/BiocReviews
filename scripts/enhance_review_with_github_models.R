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
model <- get_arg("--model", default = Sys.getenv("GITHUB_MODEL", "meta-llama-3.1-405b-instruct"))
max_prompt_chars <- as.integer(get_arg("--max-prompt-chars", default = Sys.getenv("MAX_PROMPT_CHARS", "120000")))
max_tokens <- as.integer(get_arg("--max-tokens", default = Sys.getenv("REVIEW_MAX_TOKENS", "2800")))
api_url <- get_arg("--api-url", default = "https://models.inference.ai.azure.com/chat/completions")

if (is.na(max_prompt_chars) || max_prompt_chars <= 0) max_prompt_chars <- 120000L
if (is.na(max_tokens) || max_tokens <= 0) max_tokens <- 2800L

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

token <- Sys.getenv("GITHUB_TOKEN", unset = "")
llm_status <- "success"
llm_text <- ""

tryCatch({
  payload_file <- tempfile(fileext = ".json")
  writeLines(payload, payload_file, useBytes = TRUE)

  # Use system() with proper quoting to avoid word-splitting issues on macOS
  curl_cmd <- sprintf(
    "curl -sS -X POST -H 'Authorization: Bearer %s' -H 'Content-Type: application/json' --data-binary '@%s' '%s'",
    token,
    payload_file,
    api_url
  )

  response_lines <- system(curl_cmd, intern = TRUE)
  status <- attr(response_lines, "status")
  if (!is.null(status) && status != 0) {
    stop(sprintf("curl exited with status %s", status))
  }

  body <- fromJSON(paste(response_lines, collapse = "\n"), simplifyVector = FALSE)
  content <- body$choices[[1]]$message$content
  llm_text <- extract_content(content)
}, error = function(e) {
  llm_status <<- "fallback"
  llm_text <<- paste0(
    "## LLM enhancement unavailable\n",
    "- Attempted model: `", model, "`\n",
    "- Error: `", class(e)[1], "`\n\n",
    "The rule-based review is provided below.\n\n",
    base_review
  )
})

header_lines <- c(
  sprintf("*Review enhanced by **%s (GitHub Models)** on %s.*", model, as.character(Sys.Date())),
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
  write(
    c(
      sprintf("review_file=%s", output_path),
      sprintf("llm_status=%s", llm_status),
      sprintf("truncated=%s", if (truncated) "true" else "false"),
      sprintf("omitted_chars=%s", omitted_chars)
    ),
    file = github_output,
    append = TRUE
  )
}