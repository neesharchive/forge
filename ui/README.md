# Front-end contract

`cli/bin/forge_cli --inspect` provides the implemented terminal tree/status/command
demonstration. After each command it prints each named expression tree and the
current evaluated geometry status. Failed geometry remains an inspectable model.

A graphical viewport is an optional next front end. It must send mutations through
`Forge.Session.Execute` and use read-only session views for rendering. Every button
must correspond to a printable command. Mesh views can be null on evaluation
failure and expire after a session mutation; reacquire them before GPU upload.
Camera, selection and display colors remain front-end state.

Acceptance example: load `examples/bracket.forge`, evaluate `cut`, inspect its tree,
export `cut` to `bracket.obj`, undo/redo and export the same geometry again. The
independent OBJ reader in `tests/integration.py` checks the file's connectivity,
volume and bounds. No graphical window or OpenGL renderer is included in this
implementation.
