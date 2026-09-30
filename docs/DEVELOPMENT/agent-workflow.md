# Agent Workflow

## Goal

Allow multiple AI agents to work in parallel without conflicts.

## Issue Split Rules

Bad:
- Build recipe import

Good:

Agent A - iOS Share Extension
- receives URL
- creates request
- handles UI state

Agent B - Supabase API
- import endpoint
- job state
- validation

Agent C - AI Pipeline
- extraction
- parser
- confidence rules

Agent D - Tests
- fixtures
- integration tests

## Requirements

Every Issue must define:
- Goal
- Input
- Output
- Files allowed
- Dependencies
- Acceptance criteria
- Test plan

Shared contracts first, implementation second.
