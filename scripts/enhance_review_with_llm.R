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

list_available_models <- function(provider, token) {
  tryCatch({
    if (provider == "gemini") {
      list_url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models?key=%s", token)
      curl_cmd <- sprintf("curl -sS '%s'", list_url)
    } else {
      # GitHub Models list endpoint
      list_url <- "https://models.inference.ai.azure.com/models"
      curl_cmd <- sprintf("curl -sS -H 'Authorization: Bearer %s' '%s'", token, list_url)
    }

    response_lines <- system(curl_cmd, intern = TRUE)
    if (is.null(attr(response_lines, "status")) || attr(response_lines, "status") == 0) {
      response_text <- paste(response_lines, collapse = "\n")
      body <- fromJSON(response_text, simplifyVector = FALSE)

      if (provider == "gemini") {
        # Extract model names from Gemini response
        if (!is.null(body$models)) {
          models <- vapply(body$models, function(m) {
            # Extract just the model name from "models/gemini-xxx"
            name <- sub("^models/", "", m$name)
            # Filter to only generation models (exclude embedding, etc.)
            if (!is.null(m$supportedGenerationMethods) &&
                "generateContent" %in% unlist(m$supportedGenerationMethods)) {
              name
            } else {
              NA_character_
            }
          }, character(1))
          models <- models[!is.na(models)]
          return(sort(models))
        }
      } else {
        # Parse GitHub Models response
        if (!is.null(body$data)) {
          models <- vapply(body$data, function(m) m$id, character(1))
          return(sort(models))
        }
      }
    }
    character(0)
  }, error = function(e) {
    character(0)
  })
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
  max_tokens <- if (nzchar(max_tokens_arg)) as.integer(max_tokens_arg) else 2800L
  token <- Sys.getenv("GEMINI_API_KEY", unset = "")
  token_param <- "key"
} else {
  # GitHub Models configuration
  if (!nzchar(api_url)) api_url <- "https://models.inference.ai.azure.com/chat/completions"
  max_prompt_chars <- if (nzchar(max_prompt_chars_arg)) as.integer(max_prompt_chars_arg) else 28000L  # ~7K tokens (8K limit with margin)
  max_tokens <- if (nzchar(max_tokens_arg)) as.integer(max_tokens_arg) else 2800L
  token <- Sys.getenv("GITHUB_TOKEN", unset = "")
  token_param <- "bearer"
}

if (is.na(max_prompt_chars) || max_prompt_chars <= 0) {
  max_prompt_chars <- if (provider == "gemini") 400000L else 28000L
}
if (is.na(max_tokens) || max_tokens <= 0) max_tokens <- 2800L

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
    content <- body$candidates[[1]]$content$parts[[1]]$text
  } else {
    # GitHub Models/OpenAI format: choices[].message.content
    if (is.null(body$choices) || length(body$choices) == 0) {
      stop(sprintf("API response missing choices. Response keys: %s",
                   paste(names(body), collapse = ", ")))
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

  error_msg <- conditionMessage(e)
  fallback_parts <- c(
    "## LLM enhancement unavailable\n",
    sprintf("- Attempted model: `%s`\n", model),
    sprintf("- Error: `%s`\n", error_msg)
  )

  # If the error suggests a model not found, list available models
  if (grepl("not found|not supported|invalid model|model.*not.*available", error_msg, ignore.case = TRUE)) {
    message("Fetching list of available models...")
    available <- list_available_models(provider, token)
    if (length(available) > 0) {
      fallback_parts <- c(
        fallback_parts,
        "\n### Available models\n",
        sprintf("Try one of these %s models instead:\n", if (provider == "gemini") "Gemini" else "GitHub"),
        paste0("- `", available, "`", collapse = "\n"),
        "\n"
      )
    } else {
      fallback_parts <- c(
        fallback_parts,
        "\n(Could not fetch list of available models)\n"
      )
    }
  }

  fallback_parts <- c(
    fallback_parts,
    "\nThe rule-based review is provided below.\n\n",
    base_review
  )

  llm_text <<- paste0(fallback_parts, collapse = "")
})

provider_name <- if (provider == "gemini") "Google Gemini" else "GitHub Models"
header_lines <- c(
  sprintf("*Review enhanced by **%s (%s)** on %s.*", model, provider_name, as.character(Sys.Date())),
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