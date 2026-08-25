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
  property string pendingName: ""
  property string pendingValue: ""

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

  function openAdd() {
    root.mode = "add"
    root.pendingName = ""
    root.pendingValue = ""
    if (nameField) nameField.text = ""
    if (valueField) valueField.text = ""
    Qt.callLater(function() { if (nameField) nameField.forceActiveFocus() })
  }

  function cancelAdd() {
    root.pendingName = ""
    root.pendingValue = ""
    root.mode = "list"
    Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
  }

  function entryExists(name) {
    if (!name || root.entries.length === 0) return false
    for (var i = 0; i < root.entries.length; i++) {
      if (root.entries[i] === name) return true
    }
    return false
  }

  function doSave() {
    var name = root.pendingName.trim()
    var value = root.pendingValue
    if (name === "" || value === "") return
    if (root.entryExists(name)) {
      overwriteDialog.message = "An entry named \u201C" + name + "\u201D already exists. Overwrite it?"
      overwriteDialog.entryName = name
      overwriteDialog.entryValue = value
      overwriteDialog.opened = true
      return
    }
    root.saveEntry(name, value)
  }

  function saveEntry(name, value) {
    root.pendingName = ""
    root.pendingValue = ""
    root.mode = "list"
    root.filterText = name
    if (searchBox) searchBox.text = name
    adder.command = ["bash", root.sourceDir + "/add-entry.sh", name, value]
    adder.running = true
    Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
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
    id: adder
    stdout: StdioCollector { id: adderOut; waitForEnd: true }
    onExited: {
      entryLister.running = true
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

      // ---------- Header: key glyph + "Pass" + subtitle + action icon ----------

      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, addButton.implicitHeight)

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
          anchors.right: addButton.left
          anchors.rightMargin: addButton.visible ? Style.space(12) : 0
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
            text: {
              if (root.mode === "add") return "Add entry"
              if (root.mode === "actions") return root.currentEntry
              return root.entries.length + " entries"
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
          }
        }

        PanelActionButton {
          id: addButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.mode === "add" ? "󰅖" : "󰐕"
          tooltipText: root.mode === "add" ? "Cancel" : "Add entry"
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: true
          onClicked: {
            if (root.mode === "add") root.cancelAdd()
            else root.openAdd()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              if (searchBox && searchBox.visible) { searchBox.forceActiveFocus(); event.accepted = true }
              else if (nameField && nameField.visible) { nameField.forceActiveFocus(); event.accepted = true }
            }
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
          } else if (event.key === Qt.Key_Tab) {
            addButton.forceActiveFocus(); event.accepted = true
          }
        }
      }

      PanelSeparator {
        visible: root.mode === "list"
        foreground: root.foreground
      }

      // ---------- Add mode: name + value fields ----------

      Column {
        id: addForm
        visible: root.mode === "add"
        width: parent.width
        spacing: Style.space(10)

        TextField {
          id: nameField
          width: parent.width
          foreground: root.foreground
          placeholderText: "Entry name (e.g., work/github)"
          text: root.pendingName
          onTextChanged: root.pendingName = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelAdd(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (valueField) valueField.forceActiveFocus(); event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              if (valueField) valueField.forceActiveFocus(); event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
              cancelButton.forceActiveFocus(); event.accepted = true
            }
          }
        }

        TextField {
          id: valueField
          width: parent.width
          foreground: root.foreground
          placeholderText: "Password or secret"
          text: root.pendingValue
          onTextChanged: root.pendingValue = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelAdd(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.doSave(); event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              saveButton.forceActiveFocus(); event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
              if (nameField) nameField.forceActiveFocus(); event.accepted = true
            }
          }
        }

        Row {
          width: parent.width
          layoutDirection: Qt.RightToLeft
          spacing: Style.space(10)

          Button {
            id: saveButton
            text: "Save"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: root.pendingName.trim() !== "" && root.pendingValue !== ""
            onClicked: root.doSave()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                cancelButton.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                if (valueField) valueField.forceActiveFocus(); event.accepted = true
              }
            }
          }

          Button {
            id: cancelButton
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.cancelAdd()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                if (nameField) nameField.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                saveButton.forceActiveFocus(); event.accepted = true
              }
            }
          }
        }
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

    ConfirmDialog {
      id: overwriteDialog
      property string entryName: ""
      property string entryValue: ""
      message: ""
      confirmText: "Overwrite"
      foreground: root.foreground
      fontFamily: root.fontFamily
      background: Color.popups.background
      scrim: Util.alpha(Color.popups.background, 0.7)
      opened: false
      onConfirmed: {
        root.saveEntry(entryName, entryValue)
        opened = false
      }
      onCanceled: {
        opened = false
        if (nameField) nameField.forceActiveFocus()
      }
      Connections {
        target: panel
        ignoreUnknownSignals: true
        function onActiveFocusChanged() {}
      }
      Item {
        anchors.fill: parent
        focus: overwriteDialog.opened
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (overwriteDialog.handleKey(event)) event.accepted = true
        }
        visible: false
      }
    }
  }
}
