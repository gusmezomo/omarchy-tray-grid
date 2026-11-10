import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Tray Grid: stands in for omarchy.tray. Instead of a drawer that slides
// open along the bar on hover, a click on the chevron opens a card under the
// bar holding, as tiles:
//   - the bar widgets in the layout's `tray` section (the bar builds them and
//     hands them to `sectionHost`, as it does for the stock tray; they are
//     moved into tiles here), and
//   - the running apps' status notifier items.
// Tiles reorder by dragging. A widget tile dragged out of the card goes back
// to the bar; a bar widget dropped on the chevron comes into the tray.
BarWidget {
  id: root
  moduleName: "gusmezomo.traygrid"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------------------------------------------------------- state --

  property bool gridOpen: false
  property bool appMenuOpen: false
  property var activeAppItem: null
  property Item activeAppAnchor: null
  // "<group>:<id>" of the tile a dragged tile would land on.
  property string dropTargetKey: ""
  property bool dragOutside: false
  property string draggingGroup: ""

  readonly property color barFg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color fg: Commons.Color.popups.text
  readonly property color cardBg: Commons.Color.popups.background
  readonly property color cardBorder: Commons.Color.popups.border
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property string barPos: bar ? bar.position : "top"

  readonly property int columns: Math.max(2, Math.min(10, Number(setting("columns", 5)) || 5))
  readonly property int tileSize: Math.max(32, Number(setting("tileSize", 46)) || 46)
  readonly property int gap: Style.space(6)
  readonly property int cardPadding: Style.space(12)
  readonly property int gridWidth: columns * tileSize + (columns - 1) * gap
  // The card is only as wide as its widest row: a few tiles make a small
  // card, and rows wrap once they reach `columns` cells.
  function rowWidth(widths) {
    var total = 0
    for (var i = 0; i < widths.length; i++) total += (total > 0 ? gap : 0) + widths[i]
    return Math.min(total, gridWidth)
  }
  readonly property real widgetRowWidth: rowWidth(widgetSlots.map(function(s) {
    return spanWidth(slotAlive(s) ? s.implicitWidth : 0)
  }))
  readonly property real appRowWidth: rowWidth(appItems.map(function() { return tileSize }))
  readonly property bool gridEmpty: widgetSlots.length === 0 && appItems.length === 0
  readonly property real contentWidth: gridEmpty
    ? Math.min(gridWidth, Style.space(220))
    : Math.max(tileSize, widgetRowWidth, appRowWidth)

  // A panel opened by a widget in the tray section. The card steps aside for
  // it, but its window stays mapped: the panel may hang off a tile in it.
  readonly property bool childPanelOpen: !!bar && bar.traySectionPopoutOpen === true

  // --------------------------------------------- bar tray-section contract --
  // Having `sectionHost` makes the bar treat this widget as the tray: it
  // builds the `tray` section's widgets into that item. `sectionShown` is
  // where, on the bar, a dragged widget can be dropped into the section.

  property Item sectionHost: null
  readonly property bool barDragging: !!bar && bar.traySectionDragActive === true
  readonly property string sectionEdge: "start"
  readonly property var sectionShown: barDragging && dropZoneExtent > 1
    ? (vertical ? { x: 0, y: 0, width: barSize, height: dropZoneExtent }
                : { x: 0, y: 0, width: dropZoneExtent, height: barSize })
    : null

  property real dropZoneExtent: barDragging ? Style.bar.iconSlot * 3 : 0
  Behavior on dropZoneExtent {
    NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
  }

  implicitWidth: vertical ? barSize : dropZoneExtent + chevron.implicitWidth
  implicitHeight: vertical ? dropZoneExtent + chevron.implicitHeight : barSize

  // ------------------------------------------------------------ helpers --

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (entry && typeof entry === "object" && entry.id !== undefined && entry.id !== null) return String(entry.id)
    return ""
  }

  readonly property var trayIds: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    var list = layout && Array.isArray(layout.tray) ? layout.tray : []
    return list.map(entryId)
  }

  function layoutHasWidget(id) {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    if (!layout) return false
    var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) if (entryId(list[i]) === id) return true
    }
    return false
  }

  function itemNamed(item, name) {
    function low(v) { return String(v || "").toLowerCase() }
    return low(item.id).indexOf(name) !== -1 || low(item.title).indexOf(name) !== -1
      || low(item.tooltipTitle).indexOf(name) !== -1
  }

  // Same rule as the stock tray: an app whose tray item a bar widget stands
  // in for is not shown twice.
  function ownedByOmarchy(item) {
    if (itemNamed(item, "localsend")) return true
    if (itemNamed(item, "dropbox") && layoutHasWidget("omarchy.dropbox")) return true
    if (itemNamed(item, "superwhisper") && layoutHasWidget("superwhisper.panel")) return true
    return false
  }

  function appTitle(item) {
    if (!item) return ""
    var t = String(item.tooltipTitle || item.title || "").trim()
    if (t) return t
    var id = String(item.id || "")
    var slash = id.lastIndexOf("/")
    return slash !== -1 ? id.substring(slash + 1) : id
  }

  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function run(argv) {
    Quickshell.execDetached(argv)
  }

  // ------------------------------------------------------------- apps --

  readonly property var hiddenApps: settings && Array.isArray(settings.hidden) ? settings.hidden : []
  readonly property var appOrder: settings && Array.isArray(settings.appOrder) ? settings.appOrder : []

  readonly property var appItems: {
    var values = SystemTray.items.values
    var order = appOrder
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (!item || item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (hiddenApps.indexOf(String(item.id || "")) !== -1) continue
      var rank = order.indexOf(String(item.id || ""))
      rows.push({ item: item, rank: rank === -1 ? 100000 + i : rank })
    }
    rows.sort(function(a, b) { return a.rank - b.rank })
    return rows.map(function(r) { return r.item })
  }

  function persistSettings(patch) {
    var next = {}
    var current = settings || {}
    for (var k in current) if (k !== "id") next[k] = current[k]
    for (var p in patch) next[p] = patch[p]
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, next)
  }

  // --------------------------------------------------------- widget slots --
  // The bar parents its tray-section list (a GridLayout of module slots)
  // into sectionHost. Each slot is lifted out of that list into a tile here;
  // the bar keeps owning it, so it still opens its panel, keeps its settings
  // and goes away when its entry leaves the layout.

  property Item sectionGrid: null
  property var knownSlots: []

  function slotAlive(s) {
    try {
      return !!s && typeof s.widgetKey === "string" && s.widgetKey !== ""
    } catch (e) {
      return false
    }
  }

  function isWidgetSlot(item) {
    return !!item && ("widgetKey" in item) && ("widgetHolder" in item) && ("activeItem" in item)
  }

  function slotId(s) {
    return String(s.moduleName || s.widgetKey || "")
  }

  function findGrid() {
    if (!sectionHost) return
    var stack = [sectionHost]
    for (var depth = 0; depth < 3 && stack.length; depth++) {
      var next = []
      for (var i = 0; i < stack.length; i++) {
        var kids = stack[i].children
        for (var j = 0; j < kids.length; j++) {
          var kid = kids[j]
          if (kid && ("listRows" in kid)) {
            if (sectionGrid !== kid) sectionGrid = kid
            adoptSlots()
            return
          }
          next.push(kid)
        }
      }
      stack = next
    }
  }

  function adoptSlots() {
    var list = knownSlots.filter(slotAlive)
    var changed = list.length !== knownSlots.length
    if (sectionGrid) {
      var kids = sectionGrid.children
      for (var i = 0; i < kids.length; i++) {
        if (isWidgetSlot(kids[i]) && list.indexOf(kids[i]) === -1) {
          list.push(kids[i])
          changed = true
        }
      }
    }
    if (changed) knownSlots = list
  }

  readonly property var widgetSlots: {
    var ids = trayIds
    var list = knownSlots.filter(slotAlive)
    list.sort(function(a, b) {
      var ia = ids.indexOf(slotId(a)), ib = ids.indexOf(slotId(b))
      return (ia === -1 ? 9999 : ia) - (ib === -1 ? 9999 : ib)
    })
    return list
  }

  function mountSlot(slot, holder) {
    if (!slotAlive(slot) || !holder) return
    slot.parent = holder
    slot.width = Qt.binding(function() { return slot ? slot.implicitWidth : 0 })
    slot.height = Qt.binding(function() { return slot ? slot.implicitHeight : 0 })
    slot.x = Qt.binding(function() { return holder && slot ? Math.round((holder.width - slot.width) / 2) : 0 })
    slot.y = Qt.binding(function() { return holder && slot ? Math.round((holder.height - slot.height) / 2) : 0 })
    // The slot's own pointer area drags widgets along the bar strip; off the
    // strip that drag would remove the widget. Tiles reorder by their own
    // drag, and the widget's own buttons still take clicks underneath.
    var kids = slot.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (c && ("suppressClick" in c) && ("heldTarget" in c)) c.enabled = false
    }
  }

  // Width of a tile holding something `w` wide: whole grid cells.
  function spanWidth(w) {
    var cells = Math.ceil((w + Style.space(12) + gap) / (tileSize + gap))
    cells = Math.max(1, Math.min(columns, cells))
    return cells * tileSize + (cells - 1) * gap
  }

  // Deferred through timers rather than Qt.callLater, so nothing runs
  // against a widget a plugin reload has already torn down.
  Timer { id: adoptTimer; interval: 0; onTriggered: root.adoptSlots() }
  Timer { id: findTimer; interval: 0; onTriggered: root.findGrid() }

  Timer {
    interval: 400
    repeat: true
    running: !!root.sectionHost && !root.sectionGrid
    onTriggered: root.findGrid()
  }

  Connections {
    target: root.sectionGrid
    ignoreUnknownSignals: true
    function onChildrenChanged() { adoptTimer.restart() }
  }

  // ------------------------------------------------------- open / close --

  function toggle() {
    if (gridOpen) close()
    else gridOpen = true
  }

  function close() {
    appMenuOpen = false
    gridOpen = false
  }

  // The bar asks the open panel to step aside when another one opens.
  // A panel opened from a tile replaces the card; any other closes it.
  function closeForPopoutSwitch() {
    popoutCheckTimer.restart()
  }

  function checkForeignPopout() {
    if (!gridOpen || appMenuOpen) return
    if (childPanelOpen) {
      gridOpen = false
      return
    }
    var active = bar ? bar.activePopout : null
    if (active && active !== root && active !== menuOwner) gridOpen = false
  }

  // IPC: `omarchy-shell gusmezomo.traygrid toggle` (bindable to a key).
  // One handler serves every monitor's bar, so it relays to each instance
  // and only the one on the focused monitor acts.
  function onFocusedMonitor() {
    var mon = Hyprland.focusedMonitor
    var scr = gridWindow.screen
    return !mon || !scr || mon.name === scr.name
  }
  function ipcToggle() { if (onFocusedMonitor()) toggle(); else close() }
  function ipcOpen() { if (onFocusedMonitor()) gridOpen = true }
  function ipcClose() { close() }

  IpcHandler {
    target: "gusmezomo.traygrid"
    function toggle(): void { root.broadcast("ipcToggle") }
    function open(): void { root.broadcast("ipcOpen") }
    function close(): void { root.broadcast("ipcClose") }
  }

  onGridOpenChanged: {
    if (!bar) return
    if (gridOpen) {
      bar.requestPopout(root)
      publishCard()
    } else {
      bar.releasePopout(root)
    }
  }

  // Tell the bar where the card stands. A panel opening from a tile then
  // knows the last card was this one, not some earlier panel's (which it
  // would otherwise animate in from, sliding across the screen).
  function publishCard() {
    if (!gridOpen || !bar || typeof bar.notePopoutCard !== "function") return
    var scr = gridWindow.screen
    if (!scr) return
    bar.notePopoutCard({ screen: scr.name, x: card.x, y: card.y, width: card.width, height: card.height })
  }

  onAppMenuOpenChanged: {
    if (!appMenuOpen && gridOpen) reclaimTimer.restart()
  }

  Timer { id: popoutCheckTimer; interval: 0; onTriggered: root.checkForeignPopout() }
  Timer {
    id: reclaimTimer
    interval: 0
    onTriggered: if (root.gridOpen && !root.appMenuOpen && root.bar && !root.bar.activePopout) root.bar.requestPopout(root)
  }

  // A panel opened from a tile is anchored to the tile, which lives in the
  // card's window. That window must outlast the panel's fade-out too: hidden
  // early, the panel loses its anchor and jumps across the screen as it goes.
  property bool childLinger: false
  Timer {
    id: childLingerTimer
    interval: 600
    onTriggered: root.childLinger = false
  }

  onChildPanelOpenChanged: {
    if (childPanelOpen) {
      childLingerTimer.stop()
      childLinger = true
      if (gridOpen) gridOpen = false
    } else {
      childLingerTimer.restart()
    }
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onActivePopoutChanged() { popoutCheckTimer.restart() }
  }

  // --------------------------------------------------------- tile drag --

  function tileAt(group, scenePos, except) {
    var container = group === "widget" ? widgetFlow : appFlow
    var kids = container.children
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (!k || k === except || !("tileIndex" in k)) continue
      var q = k.mapFromItem(null, scenePos.x, scenePos.y)
      if (q.x >= 0 && q.y >= 0 && q.x <= k.width && q.y <= k.height) return k
    }
    return null
  }

  function pointInCard(scenePos) {
    var p = card.mapFromItem(null, scenePos.x, scenePos.y)
    return p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= card.height
  }

  function trackDrag(tile, scenePos) {
    draggingGroup = tile.group
    var inside = pointInCard(scenePos)
    dragOutside = !inside && tile.group === "widget"
    var target = inside ? tileAt(tile.group, scenePos, tile) : null
    dropTargetKey = target ? target.group + ":" + target.itemId : ""
  }

  function dropTile(tile, scenePos) {
    var inside = pointInCard(scenePos)
    var target = inside ? tileAt(tile.group, scenePos, tile) : null
    dropTargetKey = ""
    dragOutside = false
    draggingGroup = ""

    if (tile.group === "widget") {
      if (!inside) {
        // Back onto the bar, beside the tray.
        run(["omarchy", "bar", "move", tile.itemId, "--before", root.moduleName])
        return
      }
      if (!target || target.itemId === tile.itemId) return
      var to = trayIds.indexOf(target.itemId)
      if (to < 0) return
      run(["omarchy", "bar", "move", tile.itemId, "--section", "tray", "--index", String(to)])
      return
    }

    if (!target) return
    var ids = appItems.map(function(it) { return String(it.id || "") })
    var from = ids.indexOf(tile.itemId)
    var at = ids.indexOf(target.itemId)
    if (from < 0 || at < 0 || from === at) return
    ids.splice(from, 1)
    ids.splice(at, 0, tile.itemId)
    persistSettings({ appOrder: ids })
  }

  // ------------------------------------------------------- bar surface --

  // The chevron glyph points right at 0°. Closed, it points sideways, away
  // from the screen edge the widget is nearer to (toward the middle).
  // Open, it turns a quarter toward the card. Angles are picked so every
  // change is a 90° turn.
  readonly property bool onRightSide: {
    var win = gridWindow.barWindow
    var w = win ? win.width : 0
    return w > 0 ? gridWindow.anchorPos.x + chevron.width / 2 > w / 2 : true
  }
  readonly property bool onLowerHalf: {
    var win = gridWindow.barWindow
    var h = win ? win.height : 0
    return h > 0 ? gridWindow.anchorPos.y + chevron.height / 2 > h / 2 : false
  }
  readonly property real chevronAngle: {
    if (!vertical) {
      var closed = onRightSide ? 180 : 0
      var open = barPos === "bottom" ? (onRightSide ? 270 : -90) : 90
      return gridOpen ? open : closed
    }
    var closedV = onLowerHalf ? 270 : 90
    var openV = barPos === "left" ? (onLowerHalf ? 360 : 0) : 180
    return gridOpen ? openV : closedV
  }
  property real chevronRotation: chevronAngle
  Behavior on chevronRotation {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  // Room to drop a dragged bar widget into the tray, open only while one is
  // being dragged.
  Item {
    id: dropZone
    width: root.vertical ? root.barSize : root.dropZoneExtent
    height: root.vertical ? root.dropZoneExtent : root.barSize
    clip: true
    visible: root.dropZoneExtent > 1

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "+"
      color: root.barFg
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.bar.iconFont
    }
  }

  BarIconButton {
    id: chevron
    bar: root.bar
    x: root.vertical ? 0 : dropZone.width
    y: root.vertical ? dropZone.height : 0
    width: implicitWidth
    height: implicitHeight
    // Same color open or closed: the rotation alone says which it is.
    tooltipText: strings.t("tooltip")
    text: "\uf054"
    textRotation: root.chevronRotation
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.toggle()
    }
  }

  // ------------------------------------------------------------ the card --

  PanelWindow {
    id: gridWindow

    readonly property var barWindow: root.QsWindow.window
    readonly property real thick: root.bar ? root.bar.barSize : 0

    screen: barWindow ? barWindow.screen : null
    visible: root.gridOpen || card.opacity > 0 || root.childPanelOpen || root.childLinger
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-traygrid"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.gridOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Takes input only while open, and never over the bar strip, so the bar
    // (the chevron included) stays clickable.
    mask: Region { item: root.gridOpen ? catcher : null }

    TransformWatcher {
      id: anchorWatcher
      a: gridWindow.barWindow ? gridWindow.barWindow.contentItem : null
      b: chevron
    }

    readonly property point anchorPos: {
      anchorWatcher.transform
      if (!barWindow || !barWindow.contentItem) return Qt.point(0, 0)
      return chevron.mapToItem(barWindow.contentItem, 0, 0)
    }

    Item {
      anchors.fill: parent
      focus: root.gridOpen
      Keys.onEscapePressed: root.close()
    }

    MouseArea {
      id: catcher
      x: root.barPos === "left" ? gridWindow.thick : 0
      y: root.barPos === "top" ? gridWindow.thick : 0
      width: parent.width - (root.vertical ? gridWindow.thick : 0)
      height: parent.height - (root.vertical ? 0 : gridWindow.thick)
      enabled: root.gridOpen
      acceptedButtons: Qt.AllButtons
      onPressed: root.close()
    }

    Rectangle {
      id: card

      readonly property bool shown: root.gridOpen
      readonly property real margin: Style.gapsOut
      readonly property real gapOut: Style.gapsOut

      width: root.contentWidth + root.cardPadding * 2
      height: content.implicitHeight + root.cardPadding * 2

      x: {
        var W = gridWindow.width
        var px
        if (root.barPos === "left") px = gridWindow.thick + gapOut
        else if (root.barPos === "right") px = W - gridWindow.thick - width - gapOut
        else px = gridWindow.anchorPos.x + chevron.width / 2 - width / 2
        return Math.round(Math.max(margin, Math.min(px, W - width - margin)))
      }
      y: {
        var H = gridWindow.height
        var py
        if (root.barPos === "top") py = gridWindow.thick + gapOut
        else if (root.barPos === "bottom") py = H - gridWindow.thick - height - gapOut
        else py = gridWindow.anchorPos.y + chevron.height / 2 - height / 2
        return Math.round(Math.max(margin, Math.min(py, H - height - margin)))
      }

      onXChanged: root.publishCard()
      onYChanged: root.publishCard()
      onWidthChanged: root.publishCard()
      onHeightChanged: root.publishCard()

      color: root.cardBg
      radius: Style.cornerRadius
      border.width: Math.max(1, Style.space(2))
      border.color: root.dragOutside ? root.urgent : root.cardBorder

      opacity: shown ? 1 : 0
      scale: shown ? 1 : 0.97
      transformOrigin: root.barPos === "bottom" ? Item.Bottom
        : root.barPos === "left" ? Item.Left
        : root.barPos === "right" ? Item.Right : Item.Top

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(card.shown ? 180 : 120); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation {
          duration: Style.duration(card.shown ? 180 : 120)
          easing.type: Easing.Bezier
          easing.bezierCurve: Style.easeOut
        }
      }

      // Swallow clicks on the card's empty space so they don't dismiss it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      // Where the bar builds the tray section. Its slots are lifted out into
      // tiles, so it takes no room itself, but it must stay visible: the bar
      // builds no slots into a hidden list.
      Item {
        id: sectionHostItem
        width: 0
        height: 0
        clip: true
        Component.onCompleted: root.sectionHost = sectionHostItem
        Component.onDestruction: if (root && root.sectionHost === sectionHostItem) root.sectionHost = null
        onChildrenChanged: findTimer.restart()
      }

      Column {
        id: content
        x: root.cardPadding
        y: root.cardPadding
        width: root.contentWidth
        spacing: root.gap

        Flow {
          id: widgetFlow
          width: parent.width
          spacing: root.gap
          visible: root.widgetSlots.length > 0

          Repeater {
            model: root.widgetSlots

            delegate: Tile {
              id: widgetTile
              required property var modelData
              required property int index
              group: "widget"
              itemId: root.slotAlive(modelData) ? root.slotId(modelData) : ""
              tileIndex: index
              width: root.spanWidth(root.slotAlive(modelData) ? modelData.implicitWidth : 0)

              Item {
                id: slotHolder
                anchors.fill: parent
                onChildrenChanged: adoptTimer.restart()
              }

              Component.onCompleted: root.mountSlot(modelData, slotHolder)
            }
          }
        }

        Flow {
          id: appFlow
          width: parent.width
          spacing: root.gap
          visible: root.appItems.length > 0

          Repeater {
            model: root.appItems

            delegate: Tile {
              id: appTile
              required property var modelData
              required property int index
              group: "app"
              itemId: String(modelData.id || "")
              tileIndex: index

              TrayIcon {
                anchors.centerIn: parent
                width: Math.round(root.tileSize * 0.44)
                height: width
                icon: appTile.modelData.icon
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  var item = appTile.modelData
                  if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && item.onlyMenu)) {
                    root.openAppMenu(item, appTile)
                  } else if (mouse.button === Qt.MiddleButton) {
                    item.secondaryActivate()
                  } else {
                    item.activate()
                    root.close()
                  }
                }
                onWheel: function(wheel) { appTile.modelData.scroll(wheel.angleDelta.y, false) }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.widgetSlots.length === 0 && root.appItems.length === 0

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: strings.t("empty")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("hint")
            color: Util.alpha(root.fg, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ----------------------------------------------------------- app menus --

  QtObject {
    id: menuOwner
    function close() { root.appMenuOpen = false }
  }

  function openAppMenu(item, anchor) {
    if (!item) return
    if (!item.menu) {
      item.activate()
      return
    }
    resetAppMenu()
    activeAppItem = item
    activeAppAnchor = anchor
    appMenuOpen = true
  }

  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : appMenuOpener.children
  // A level change rebuilds rows under a still pointer; ignore clicks briefly
  // so a double click doesn't fire whatever lands under it.
  property bool menuSettling: false

  Timer {
    id: menuSettleTimer
    interval: 250
    onTriggered: root.menuSettling = false
  }

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  function settleMenu() {
    menuSettling = true
    menuSettleTimer.restart()
  }

  function resetAppMenu() {
    menuSettling = false
    menuSettleTimer.stop()
    menuFlick.contentY = 0
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenu()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenu()
  }

  QsMenuOpener {
    id: appMenuOpener
    menu: root.activeAppItem ? root.activeAppItem.menu : null
  }

  PopupCard {
    id: appMenu
    anchorItem: root.activeAppAnchor || chevron
    owner: menuOwner
    bar: root.bar
    open: root.appMenuOpen
    onVisibleChanged: if (!visible) root.resetAppMenu()
    padding: Style.space(8)
    contentWidth: appMenu.fittedContentWidth(Style.space(232))
    contentHeight: appMenu.fittedContentHeight(headerHeight + menuColumn.implicitHeight, Style.space(420))

    readonly property int headerHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: menuLayout
      anchors.fill: parent
      spacing: 0

      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: menuLayout.width

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.fg, root.fg) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            textFormat: Text.PlainText
            text: (Commons.I18n.rightToLeft ? "›  " : "‹  ") + root.currentTitle
            color: root.fg
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuSettling) return
              menuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Rectangle {
          width: menuHeader.width
          height: 1
          color: Commons.Color.popups.border
          opacity: 0.45
        }
      }

      Flickable {
        id: menuFlick
        width: menuLayout.width
        height: menuLayout.height - appMenu.headerHeight
        contentWidth: width
        contentHeight: menuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: menuColumn
          width: menuFlick.width

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool hiddenRow: atRoot && modelData.isSeparator && index <= 1

              visible: !hiddenRow
              width: menuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Commons.Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.fg, root.fg) : "transparent"
              }

              Text {
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: menuRow.modelData.checkState === Qt.Checked ? "" : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: menuRow.rowText
                color: root.fg
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                textFormat: Text.PlainText
                text: Commons.I18n.rightToLeft ? "‹" : "›"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuSettling) return
                  if (menuRow.modelData.hasChildren) {
                    menuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------- components --

  // One cell of the grid. Drags to reorder; content goes in as children.
  component Tile: Item {
    id: tile

    property string group: "app"
    property string itemId: ""
    property int tileIndex: 0
    property point lastScene: Qt.point(0, 0)
    readonly property bool dragging: tileDrag.active
    readonly property bool isDropTarget: root.dropTargetKey !== "" && root.dropTargetKey === group + ":" + itemId
    default property alias content: tileContent.data

    width: root.tileSize
    height: root.tileSize
    z: dragging ? 100 : 0

    transform: Translate {
      x: tile.dragging ? tileDrag.activeTranslation.x : 0
      y: tile.dragging ? tileDrag.activeTranslation.y : 0
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: tile.dragging || tileHover.hovered ? Style.hoverFillFor(root.fg, root.fg) : "transparent"
      border.width: tile.isDropTarget ? Math.max(1, Style.space(2)) : 1
      border.color: tile.isDropTarget ? root.accent : Util.alpha(root.fg, 0.22)
      opacity: tile.dragging ? 0.85 : 1
    }

    Item {
      id: tileContent
      anchors.fill: parent
    }

    HoverHandler {
      id: tileHover
    }

    // Above the content, so it sees the press first; it only takes over once
    // the pointer moves, leaving clicks to the content underneath.
    Item {
      anchors.fill: parent
      z: 50

      // Passive watcher. Without it, clicks on the tile's content were
      // lost to the DragHandler below (found by testing, not documented).
      PointHandler {
        acceptedButtons: Qt.AllButtons
      }

      DragHandler {
        id: tileDrag
        target: null
        dragThreshold: 3
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onCentroidChanged: {
          if (!active) return
          tile.lastScene = centroid.scenePosition
          root.trackDrag(tile, centroid.scenePosition)
        }
        onActiveChanged: {
          if (active) {
            tile.lastScene = centroid.scenePosition
          } else {
            root.dropTile(tile, tile.lastScene)
          }
        }
      }
    }
  }

  // A tray icon; symbolic icons are painted in the theme's foreground so
  // they stay visible on any theme.
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: String(trayIconRoot.icon || "")
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    Rectangle {
      anchors.fill: trayIconImage
      color: root.fg
      visible: trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: trayIconImage
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
  }
}
