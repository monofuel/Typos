# Typos

An AI text editor using silky.

## Racha

- Typos will be using Racha for the AI components.
- Racha is my personal AI assistant.
- `Racha/src/rachax.nim` is a cli coding tool similar to claude-code or codex-cli.
  - we should be importing this and calling the functions directly for our coding needs.
- `Racha/src/racha_fixer.nim` is the automated CI bot to fix issues and implement PRs.
- `Racha/src/racha_manager.nim` is an experimental new manager to do planning and work with racha fixer.

## AI modes

- some AI modes should be strictly read-only, and some will be read-write.
- rachax is built to NOT have a bash command. all tools should be built into the agent for safety and ease of correct use.

- plan mode
  - read-only mode. AI uses tools to create a plan and prompt the user for approval.
  - while in plan mode, the user can follow up with more changes to the currently selected plan.
  - the UI will assume only one plan at a time.
  - the plan will have a 'code now' button to start implementation.
- ask mode
  - read only mode, AI is answering questions and providing information.
- code mode 
  - optional auto-plan toggle
  - read-write.
  - auto-plan mode will have an agent make a plan before starting the coding task, and automatically accept the plan.
  - code mode is read-write and the agent will persist in coding until the task is complete.

## Syncronous vs Asyncronous

- iterative focused development and asyncronous tasks will be separate UI modes.

### Syncronous

- the default mode will by Syncronous coding.
- the Human and the Agent will be working interactively.
- the UI will focus only on the current task at hand, both the Human and the Agent will be focused on this one task.
  - do one thing, do it well.
- sync mode is good for complex tasks that require a lot of back and forth between the Human and the Agent.

### Asyncronous

- asyncronous mode will be using gitea issues as the task queue.
  - racha-fixer is an automated CI bot that will take issues, implement them, and submit PRs.
- async mode will basically be a UI for the issues and PRs on gitea.
  - we should be able to make a kanban-like board and push issues along and review PRs and submit approvals or make changes.
- Async mode is good for small self-contained tasks that can be easily completed autonomously by an agent.
