---
# Trigger - when should this workflow run?
on:
  pull_request:
    types: [opened]
  workflow_dispatch:  # Manual trigger

# Permissions - what can this workflow access?
permissions:
  contents: read
  issues: read
  pull-requests: read

# AI engine - Gemini (free Google AI Studio tier; avoids Copilot utility-model rate limits)
#
# The model is pinned. Unpinned, the CLI asks the proxy for `auto-gemini-3`,
# which resolved to `gemini-3.1-flash-tts-preview` — a text-to-speech preview
# with no AI-credits pricing, so every request failed with
# `unknown_model_ai_credits` and the agent job died on every PR.
#
# The model ID must be one the Generative Language API actually serves — the
# CLI calls it directly at v1beta with GEMINI_API_KEY, so proxy alias names do
# not apply. `gemini-3-pro` looks plausible and does not exist; it fails with
# ModelNotFoundError.
#
# Enumerated via ListModels against this repo's key. gemini-2.5-pro is the only
# generally-available pro model: every 3.x pro is `-preview` and can be
# withdrawn without notice. `gemini-pro-latest` and `gemini-flash-latest` are
# floating aliases, rejected for the same reason every other dependency here is
# pinned — a silent upstream swap is exactly what this repo verifies against.
#
# To re-check what is callable, list models with the x-goog-api-key header
# against https://generativelanguage.googleapis.com/v1beta/models.
engine: gemini
model: gemini-2.5-pro

# Network access
network: defaults

# Outputs - what APIs and tools can the AI use?
safe-outputs:
  report-failure-as-issue: false
  add-comment:
    max: 10

---

# ai-auditor

Audit the changes in this pull request for security vulnerabilities, logic bugs, or performance issues.

## Instructions

1.  Review all file changes in the current pull request.
2.  Identify potential security vulnerabilities (e.g., SQL injection, hardcoded secrets, insecure defaults).
3.  Look for logic bugs, edge cases, or potential runtime errors.
4.  Check for performance bottlenecks or inefficient code patterns.
5.  For each identified issue, provide a concise and constructive comment explaining the problem and suggesting a fix.
6.  Use the `add-comment` tool to post your feedback directly on the PR.

Be thorough but focus on high-impact issues. If no issues are found, post a brief summary comment stating that the audit passed.

## Setup

This workflow uses the Gemini engine and requires the `GEMINI_API_KEY` repository secret (free key from https://aistudio.google.com).
