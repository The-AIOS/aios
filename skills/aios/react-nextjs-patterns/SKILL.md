---
name: react-nextjs-patterns
description: Modern React + Next.js patterns. Use when building Next.js apps (App Router, Server Components, streaming, parallel routes), implementing React state management (Redux Toolkit, Zustand, Jotai, React Query), or applying Next.js framework best practices (file conventions, RSC boundaries, metadata, image/font optimization).
---

# React + Next.js Patterns

Modern Next.js (App Router) + React state-management practices for production apps.

## When to load which reference

| Working on | Read |
|---|---|
| Next.js framework conventions (file structure, metadata, RSC, async APIs) | [references/next-best-practices.md](references/next-best-practices.md) |
| Next.js 14+ App Router (Server Components, streaming, parallel routes, data fetching) | [references/nextjs-app-router-patterns.md](references/nextjs-app-router-patterns.md) |
| React state management (Redux Toolkit, Zustand, Jotai, React Query, server state) | [references/react-state-management.md](references/react-state-management.md) |

## Core decisions

- **Server Components first** — only opt into client (`'use client'`) when you actually need state/effects/handlers.
- **State management hierarchy:** local `useState` → context only for true app-wide concerns → React Query for server state → Zustand for client-shared state → Redux only if the codebase is already there.
- **File-system as router** — App Router conventions are load-bearing; respect them.

For frontend design quality beyond patterns, see [anthropic/frontend-design](../../anthropic/frontend-design/SKILL.md).
