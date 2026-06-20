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
engine: gemini

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
