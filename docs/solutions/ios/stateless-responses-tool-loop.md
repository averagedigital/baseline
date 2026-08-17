# Stateless Responses tool loop

## Context

Coach uses streamed Responses API calls with `store: false` and local typed tools.

## Symptoms

A continuation built only with `previous_response_id` depends on server-side response retention and can fail when storage is disabled.

## What did not work

Sending only `function_call_output` plus the prior response ID did not preserve a stateless continuation contract.

## Root cause

The next request needs the model output items that caused the tool calls. Reasoning models also need their returned reasoning item.

## Solution

Keep `store: false`, request `reasoning.encrypted_content`, collect `response.output_item.done` items, and append those items followed by matching `function_call_output` records to the next input.

## Why it works

Each request contains the complete continuation state and matches every tool result to its `call_id` without relying on retained server state.

## Verification

Parser tests assert preservation of multiple output items; simulator tests verify capability-gated request construction and tool schemas.

## Prevention

Do not introduce `previous_response_id` into a stateless flow unless server-side response storage is an explicit product decision.

## Applies when

Use this pattern for Responses API tool loops that disable storage, especially with reasoning models.
