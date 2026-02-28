# Typos

An AI text editor using silky.

- very WIP, don't use yet.

- `typos` is a gui tool using silky for agentic coding.
- `typoi` is a cli tool for agentic coding at the command line, primarily with a focus for being scripted but also for interactive use.

## AI modes

- some AI modes should be strictly read-only, and some will be read-write.
- Typos is built to NOT have a bash command. all tools should be built into the agent for safety and ease of correct use.

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
