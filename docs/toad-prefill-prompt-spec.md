# Toad: --prompt flag for prefilling chat input

One-line change to `toad run` and `toad acp` CLI commands.

## What

Add a `--prompt` / `-P` option that sets `initial_prompt` on the
`ToadApp`, which flows through to `Conversation._initial_prompt`.
The text appears in the chat input, pre-filled but **not sent**.

## Why

`canon.sh` needs to open Toad with `/canon-start` pre-written in the
chat box so the user just hits Enter.

## Changes

### `src/toad/cli.py` — `run_agent()` function

Add parameter:

```python
@click.option("-P", "--prompt", default=None, help="Pre-fill the chat input")
```

Pass to `ToadApp`:

```python
app = ToadApp(project_dir=project_dir, initial_prompt=prompt)
```

### `src/toad/cli.py` — `acp()` function

Same `--prompt` option, pass to `ToadApp`:

```python
app = ToadApp(agent_data=agent_data, project_dir=project_dir, initial_prompt=prompt)
```

### `src/toad/app.py` — `ToadApp.__init__()`

Accept `initial_prompt: str | None = None`, store it, pass to
`launch_agent()` which already accepts it (line 887).

## Usage after change

```bash
# Toad opens, Claude connects, "/canon-start" is in the input box
toad run . --prompt "/canon-start"

# Same with toad acp
toad acp claude --project-dir . --prompt "/canon-start"
```

## Behavior

- Text appears in the PromptTextArea, cursor at end
- NOT auto-sent — user presses Enter to confirm
- If `--prompt` not provided, behavior unchanged
