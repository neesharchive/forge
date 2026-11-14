# ui: the contract

An initial GUI prototype has been implemented using Adi2 for the
25% progress demonstration. The GUI communicates with Forge through
its public interface and currently supports command execution,
solid listing, command history, geometry status, and STL export.

The following three rules describe the intended design of the
completed interface. The current prototype does not yet implement
all requirements, including 3D mesh rendering.

1. **Nothing in `ui/` withs anything below `Forge.Session`.** The GUI
   sees `Forge.Session` (Execute, Mesh_Of, History_*) and `Forge`
   (Vec3, Name). It never sees `Forge.Mesh` operations, `Forge.CSG`,
   `Forge.Primitives`.
2. **Every button builds a line and calls `Execute`.** The line is
   shown in a command bar at the bottom of the window before it runs.
   A user who watches the bar for an hour can write `.forge` files.
3. **Rendering reads `Mesh_Of (S, name)` after every `Execute`** and
   uploads it to the GPU. It never mutates a mesh. Selection, camera,
   colours and highlighting are UI state, not session state, and are
   not saved in the document.

## Suggested stack

- Window and input: [adi2](https://github.com/ovenpasta/adi2), with
  the command bar as a text field and the solid list as a list widget.
- Viewport: OpenGLAda into adi2's texture-view widget. One VBO per
  solid, rebuilt when `Mesh_Of` changes (compare `NT` and a hash, or
  just rebuild; parts are small).
- Camera: orbit, pan, zoom on the mouse; nothing fancy.

## Milestone 5 acceptance

Open `examples/bracket.forge`, see three solids, type
`difference cut base hole` in the bar (milestone 2 done), see the cut
part, click Export, open the STL in another tool, it is watertight.
Then do the same by clicking, and read the bar: same four lines.

## Building and Running the GUI

The Forge GUI is an example application built using Adi2.
It uses the Forge library for command execution and STL export.

The GUI has its own Alire configuration in `ui/alire.toml`,
which manages its dependencies separately from the main library.

From the Forge repository, navigate to the UI directory:

```powershell
cd ui
```

Build the application:

```powershell
alr build
```

Run the application on Windows:

```powershell
alr exec -- .\bin\forge_gui.exe
```

## Current GUI Features

The GUI currently supports:

- Entering and executing Forge commands.
- Pressing Enter or clicking Execute to run commands.
- Displaying the solids currently in the model.
- Displaying command history and the total solid count.
- Exporting solids to STL using a dedicated button.
- A two-panel layout for model information and geometry status.

The CSG tree display is awaiting integration with the model
tree implementation. A 3D geometry viewer is not currently
implemented.

## Example Usage

To create a box, enter the following in the main command field:

```text
box b 1 2 3
```

Press Enter or click Execute.

The box should appear in the Solids list.

To export the box, enter `b` in the Solid to export field
and press Enter or click Export STL.

This generates `b.stl` in the application's working directory.
