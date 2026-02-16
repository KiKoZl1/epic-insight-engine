# Ralph Operating Model (Epic Insight Engine)

This document defines how Ralph is used in this repository.

## Scope
Ralph is an operations orchestrator for improvement loops. It does not replace the LLM model itself.

Ralph can run in the following modes:
- `dev`: frontend and low-risk refactors
- `dataops`: SQL/Edge pipeline tuning
- `report`: evidence pack and report quality loops
- `qa`: regression and acceptance checks
- `custom`: one-off controlled runs

## Core Principles
1. One run, one `run_id`.
2. Every run has hard limits (iterations, timeout, budget).
3. No direct production deploy from autonomous runs.
4. Every run writes audit data (`ralph_runs`, `ralph_actions`, `ralph_eval_results`, `ralph_incidents`).
5. Promotion requires passing all required gates.

## Run Lifecycle
1. Start run (`start_ralph_run`)
2. Plan steps
3. Execute step-by-step and record actions (`record_ralph_action`)
4. Evaluate gates (`record_ralph_eval`)
5. If incidents occur, raise (`raise_ralph_incident`)
6. Finish run (`finish_ralph_run`) with final status

## Status Semantics
- `running`: active
- `completed`: done, passed required checks
- `promotable`: done and ready for merge/deploy review
- `failed`: run failed
- `rolled_back`: changes reverted after failed gates
- `cancelled`: manually stopped

## Default Guardrails
- Max iterations: 8
- Run timeout: 45 minutes
- Build/test retries before hard stop: 2
- Budget limits must be set before run starts

## Promotion Policy
A run is `promotable` only if:
1. Required gates pass
2. No unresolved critical incident
3. Artifacts are complete (summary + evals + action trace)
4. Human review checklist passes

## Human-in-the-Loop
Ralph can automate implementation and testing loops, but release remains human-controlled.

## Production Safety
Ralph must not:
- run destructive git commands
- bypass migrations
- auto-deploy to production
- run open-ended loops without budget and timeout
