import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "pass"
  ipcTarget: "pass"

  property var entries: []
  property var filteredEntries: []
  property string filterText: ""
  property int selectedIndex: 0
  property string mode: "list"
  property string currentEntry: ""
  property var actions: []
  property bool hasOtp: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color selectionFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.15)
  readonly property string sourceDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  function rebuildList() {
    var q = root.filterText.toLowerCase()
    var out = root.entries.filter(function(name) {
      return q === "" || name.toLowerCase().indexOf(q) !== -1
    })
    root.filteredEntries = out
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (entryList.count > 0) entryList.positionViewAtIndex(0, ListView.Contain)
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.rebuildList()
  }

  function select(delta) {
    if (entryList.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + entryList.count) % entryList.count
    entryList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function openActions(entry) {
    if (!entry) return
    root.currentEntry = entry
    var list = [
      { label: "Copy password", kind: "copy" },
      { label: "Type password", kind: "type" }
    ]
    if (root.hasOtp) list.push({ label: "Copy OTP", kind: "otp" })
    root.actions = list
    root.mode = "actions"
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (entryList.count > 0) entryList.positionViewAtIndex(0, ListView.Contain)
      if (entryList) entryList.forceActiveFocus()
    })
  }

  function performAction() {
    if (root.actions.length === 0) return
    var action = root.actions[root.selectedIndex]
    if (!action) return
    Quickshell.execDetached([
      "bash", root.sourceDir + "/do-action.sh", action.kind, root.currentEntry
    ])
    root.close()
  }

  function backToList() {
    root.mode = "list"
    root.currentEntry = ""
    root.actions = []
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (entryList.count > 0) entryList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      if (searchBox) searchBox.forceActiveFocus()
    })
  }

  onOpenedChanged: if (opened) {
    if (root.entries.length === 0) entryLister.running = true
    root.filterText = ""
    if (searchBox) searchBox.text = ""
    root.mode = "list"
    root.rebuildList()
    Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
  }

  Process {
    id: entryLister
    command: ["bash", root.sourceDir + "/list-entries.sh"]
    stdout: StdioCollector { id: entryListerOut; waitForEnd: true }
    onExited: {
      var raw = entryListerOut.text || ""
      root.entries = raw.split("\n").filter(function(line) { return line.length > 0 })
      root.rebuildList()
    }
  }

  Process {
    id: otpDetector
    command: ["bash", "-c", "pass otp --help >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector { id: otpDetectorOut; waitForEnd: true }
    onExited: {
      root.hasOtp = String(otpDetectorOut.text || "").trim() === "yes"
    }
    Component.onCompleted: running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchBox
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      // ---------- Header: key glyph + "Pass" + subtitle ----------

      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

        Text {
          id: heroIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰌆"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Pass"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.mode === "actions"
              ? root.currentEntry
              : (root.entries.length + " entries")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }

      PanelSeparator {
        foreground: root.foreground
      }

      // ---------- Search box (list mode only) ----------

      TextField {
        id: searchBox
        width: parent.width
        visible: root.mode === "list"
        foreground: root.foreground
        placeholderText: "Search pass..."
        text: root.filterText
        onTextChanged: {
          root.filterText = text
          root.rebuildList()
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) { root.setFilter(""); text = "" }
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.filteredEntries.length > 0) root.openActions(root.filteredEntries[root.selectedIndex])
            event.accepted = true
          }
        }
      }

      PanelSeparator {
        visible: root.mode === "list"
        foreground: root.foreground
      }

      PanelSectionHeader {
        visible: root.mode === "actions"
        text: "ACTIONS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      // ---------- List ----------

      Item {
        width: parent.width
        height: root.mode === "list"
          ? Math.min(Math.max(entryList.contentHeight, Style.space(200)), Style.space(400))
          : Math.min(Math.max(entryList.contentHeight, Style.space(120)), Style.space(280))

        ListView {
          id: entryList
          anchors.fill: parent
          model: root.mode === "list"
            ? root.filteredEntries
            : root.actions.map(function(a) { return a.label })
          clip: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.backToList(); event.accepted = true
            } else if (event.key === Qt.Key_Left) {
              root.backToList(); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.select(-1); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.select(1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.performAction(); event.accepted = true
            }
          }
          delegate: Rectangle {
            required property string modelData
            required property int index
            width: entryList.width
            height: Style.space(32)
            color: index === root.selectedIndex ? root.selectionFill : "transparent"

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: {
                root.selectedIndex = index
                if (root.mode === "list") root.openActions(root.filteredEntries[index])
                else root.performAction()
              }
            }

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.sm
              text: parent.modelData
              color: index === root.selectedIndex ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // No matches for filter
        Column {
          anchors.centerIn: parent
          width: parent.width
          spacing: Style.space(8)
          visible: root.mode === "list" && entryList.count === 0 && root.filterText !== ""

          Text {
            text: "󰈉"
            color: root.foreground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }

          Text {
            text: "No matches for \u201C" + root.filterText + "\u201D"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }
        }

        // Empty password store
        Text {
          anchors.centerIn: parent
          width: parent.width
          visible: root.mode === "list" && root.entries.length === 0 && root.filterText === ""
          text: "No password entries found"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
