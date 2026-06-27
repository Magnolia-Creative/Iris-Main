# JIT Editor Follow-Ups

## Prompt-Driven Layout Testing

Prompt-driven JIT layout changes still need to be validated once the prompt server connection issue is addressed.

Current blocker: submitting layout prompts from the editor's intelligent dock shows a server connection error before the local JIT layout behavior can be manually verified.

Retest prompts after the server connection is working:

- `make the timeline bigger`
- `focus the preview`
- `make the editor less cluttered`

Also retest a normal timeline edit prompt, such as `split this clip`, to confirm timeline edits still work after the JIT layout path is active.
