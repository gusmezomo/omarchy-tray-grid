# Tray Grid (`gusmezomo.traygrid`)

Replaces Omarchy's system tray drawer (`omarchy.tray`) with a popup grid under the bar.

- **Open it:** click the chevron in the bar, or run `omarchy-shell gusmezomo.traygrid toggle` (you can bind this to a key).
- **Plugins:** the widgets in the bar's `tray` section show up as tiles.
  - To add one, drag it from the bar onto the chevron (a `+` area opens while you drag), or run `omarchy bar move <id> --section tray`.
  - To send one back, drag its tile out of the card. It lands on the bar just before the chevron.
- **Apps:** running apps' tray icons. Left-click activates the app, right-click opens its menu, middle-click does the app's secondary action, and scrolling sends a scroll to the app.
- **Reorder:** drag a tile onto another tile of the same kind.
- **Theme:** colors come from the theme's `popups.*` tokens and follow theme switches live.

## Settings (`shell.json`, in this widget's bar entry)

| key        | default | meaning                                   |
|------------|---------|-------------------------------------------|
| `columns`  | `5`     | tiles per row                             |
| `tileSize` | `46`    | tile size in px                           |
| `appOrder` | `[]`    | app tile order (written when you drag)    |
| `hidden`   | `[]`    | tray item ids to leave out of the grid    |

Example: `omarchy bar set gusmezomo.traygrid columns 4`

## Going back to the stock tray

```
omarchy plugin enable omarchy.tray --before gusmezomo.traygrid
omarchy plugin disable gusmezomo.traygrid
```
