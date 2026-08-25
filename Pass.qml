import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var entries: []
  property var filteredEntries: []
  property string filterText: ""
  property int selectedIndex: 0
  property string mode: "list"
  property string currentEntry: ""
  property var actions: []
  property bool hasOtp: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    if (root.entries.length === 0) entryLister.running = true
    root.rebuildList()
    root.mode = "list"
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    root.mode = "list"
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "pass")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

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
    if (root.hasOtp) list.push({label: "Copy OTP", kind: "otp" })
    root.actions = list
    root.mode = "actions"
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (entryList.count > 0) entryList.positionViewAtIndex(0, ListView.Contain)
    })
  }

  function performAction() {
    if (root.actions.length === 0) return
    var action = root.actions[root.selectedIndex]
    if (!action) return
    Quickshell.execDetached([
      "bash", root.manifest.__sourceDir + "/do-action.sh", action.kind, root.currentEntry
    ])
    root.dismiss()
  }

  function backToList() {
    root.mode = "list"
    root.currentEntry = ""
    root.actions = []
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (entryList.count > 0) entryList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  Process {
    id: entryLister
    command: ["bash", root.manifest.__sourceDir + "/list-entries.sh"]
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "pass"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.sm

        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"
          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "actions"
              ? root.currentEntry
              : (root.filterText || "Search pass...")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - parent.spacing

          ListView {
            id: entryList
            anchors.fill: parent
            model: root.mode === "list"
              ? root.filteredEntries
              : root.actions.map(function(a) { return a.label })
            clip: true
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.mode === "actions") root.backToList()
                else if (root.filterText) root.setFilter("")
                else root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Left && root.mode === "actions") {
                root.backToList(); event.accepted = true
              } else if (Util.editsFilter(event, root.filterText) && root.mode === "list") {
                root.setFilter(Util.editedFilter(event, root.filterText)); event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.select(-1); event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.select(1); event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.mode === "list") {
                  if (root.filteredEntries.length > 0) root.openActions(root.filteredEntries[root.selectedIndex])
                } else root.performAction()
                event.accepted = true
              } else if (root.mode === "list" && event.text && event.text.length === 1
                        && event.text.charCodeAt(0) >= 32
                        && event.text.charCodeAt(0) !== 127) {
                root.setFilter(root.filterText + event.text); event.accepted = true
              }
            }
            delegate: Rectangle {
              required property string modelData
              required property int index
              width: entryList.width
              height: Style.space(32)
              color: index === root.selectedIndex ? Color.menu.selectedBackground : "transparent"
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Style.spacing.sm
                text: parent.modelData
                color: index === root.selectedIndex ? Color.menu.selectedText : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(8)
            visible: entryList.count === 0 && root.filterText !== "" && root.mode === "list"

            Text {
              text: "󰈉"
              color: Color.menu.selectedText
              opacity: 0.8
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
