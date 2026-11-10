# Tray Grid for Omarchy

The Omarchy bar's system tray is a drawer that slides open along the bar when you hover over it.
Tray Grid replaces that drawer with a click-to-open popup under the bar. Your tray plugins and the tray icons of your running apps are laid out in it as a grid of tiles.

## Features

- **A popup grid instead of a hover drawer.** Click the arrow in the bar to open the grid, and click anywhere else to close it. The tiles never take up room on the bar.
- **Plugins and apps together.** Bar widgets in the tray section (for example the Omarchy menu, Superwhisper or Screen Time) appear as tiles, followed by the tray icons of your running apps. Plugin tiles open their panels as they would on the bar. App tiles work as tray icons do: left-click activates the app, right-click opens its menu (submenus included), middle-click does the app's secondary action, and scrolling sends a scroll to the app.
- **Drag to arrange.** Drag a widget from the bar onto the arrow to move it into the grid. Drag a plugin tile out of the popup to put it back on the bar. Drag a tile onto another tile to reorder them.
- **Sized to fit.** The popup is only as wide as its tiles. Rows wrap after five tiles, and wider widgets take two cells.
- **Follows your theme.** The colors come from the active Omarchy theme's popup colors and update live when you switch themes.
- **An arrow that tells you the state.** When the grid is closed, the arrow points toward the middle of the screen. When it is open, the arrow turns to point at the popup.

## Install

Requires a recent Omarchy (one with the Quickshell-based shell and `omarchy plugin` commands).

```bash
omarchy plugin add https://github.com/gusmezomo/omarchy-tray-grid --enable
omarchy plugin disable omarchy.tray
omarchy restart shell
```

1. The first command installs Tray Grid and puts it on the right side of the bar.
2. The second command removes the stock tray, so the bar doesn't show two trays.
3. Restarting the shell registers the plugin's keyboard commands.

> Plugins run unsandboxed inside the Omarchy shell. As with any plugin, read the code before you install it.

## Use

- Click the arrow, or run `omarchy-shell gusmezomo.traygrid toggle` (you can bind it to a key). `open` and `close` also work.
- To add a widget to the grid, drag it from the bar onto the arrow. A `+` area opens beside the arrow while you drag. You can also run:

  ```bash
  omarchy bar move omarchy.menu --section tray
  ```

- To take a widget out of the grid, drag its tile out of the popup. It lands on the bar just before the arrow.

## Configure

The settings live in Tray Grid's entry in `~/.config/omarchy/shell.json`. You can set them with `omarchy bar set`:

```bash
omarchy bar set gusmezomo.traygrid columns 4     # tiles per row (default 5)
omarchy bar set gusmezomo.traygrid tileSize 52   # tile size in px (default 46)
```

| key        | default | meaning                                                  |
|------------|---------|----------------------------------------------------------|
| `columns`  | `5`     | Tiles per row before the grid wraps                      |
| `tileSize` | `46`    | Tile size in pixels                                      |
| `appOrder` | `[]`    | Order of the app tiles. Saved for you when you drag them |
| `hidden`   | `[]`    | Tray item ids to leave out of the grid                   |

## Update

```bash
omarchy plugin update gusmezomo.traygrid
omarchy restart shell
```

## Uninstall

```bash
omarchy plugin enable omarchy.tray --before gusmezomo.traygrid
omarchy plugin disable gusmezomo.traygrid
omarchy plugin remove gusmezomo.traygrid
```

The first command puts the stock tray back where Tray Grid was. Widgets you had in the grid return to its drawer.

## How it works

Tray Grid uses the same contract with the bar as the stock tray (`omarchy.tray`): a widget that exposes a `sectionHost` item is treated as the tray, and the bar builds the widgets of its `tray` section into that item. The bar keeps owning those widgets. They keep their settings and panels, and they go away when their entry leaves the layout. Tray Grid moves each one into a tile of its own popup.

Other details:

- The bar's own drag handling is turned off for widgets inside the popup, because off the bar strip it would remove them. Tiles use their own drag instead, and reorder by calling `omarchy bar move`.
- App tiles read the system tray (StatusNotifierItem) directly and save their order in the plugin's settings.
- The popup tells the bar where it is, and its window stays open until a panel opened from a tile has finished closing. This keeps those panels from jumping across the screen when they open or close.

## Credits

The app menu and tray icon handling are adapted from the stock system tray in [Omarchy](https://github.com/omacom/omarchy) (MIT).

## License

[MIT](LICENSE)
