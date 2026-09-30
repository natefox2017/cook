# iOS Architecture V1

## Stack

- SwiftUI
- Swift Concurrency
- iOS Share Extension

## Modules

App
- Features
- Domain
- Data
- Services
- Shared UI

Share Extension
- Receive URL/text/media
- Create import request
- Return immediately

## Rules

Share Extension must not:
- run long AI tasks
- parse videos
- become a full editor

Long processing belongs to backend.

## Parallel Development Boundaries

iOS agents can work independently on:
- UI screens
- navigation
- networking
- domain models
- tests

Shared contracts must be frozen first.
