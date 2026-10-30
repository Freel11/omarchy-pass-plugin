import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
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
  property int passwordLength: 25
  property bool includeSymbols: true
  property string generationError: ""
  property int addSession: 0
  readonly property bool generatingPassword: generator.active

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
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
    list.push({ label: "Delete entry", kind: "delete" })
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
    if (action.kind === "delete") {
      deleteDialog.message = "Delete \u201C" + root.currentEntry + "\u201D? This cannot be undone."
      deleteDialog.entryName = root.currentEntry
      deleteDialog.opened = true
      return
    }
    Quickshell.execDetached([
      "bash", root.sourceDir + "/do-action.sh", action.kind, root.currentEntry
    ])
    root.close()
  }

  function deleteEntry(name) {
    deleter.command = ["bash", root.sourceDir + "/do-action.sh", "delete", name]
    deleter.running = true
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

  function clearAdd() {
    root.addSession++
    if (generator.running) generator.running = false
    root.pendingName = ""
    root.pendingValue = ""
    root.generationError = ""
    if (nameField) nameField.text = ""
    if (valueField) valueField.text = ""
    overwriteDialog.opened = false
    overwriteDialog.entryName = ""
    overwriteDialog.entryValue = ""
  }

  function openAdd() {
    root.clearAdd()
    root.mode = "add"
    Qt.callLater(function() { if (nameField) nameField.forceActiveFocus() })
  }

  function cancelAdd() {
    root.clearAdd()
    root.mode = "list"
    Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
  }

  function generatePassword() {
    if (root.mode !== "add" || root.generatingPassword) return
    root.generationError = ""
    generator.session = root.addSession
    generator.requestedLength = root.passwordLength
    generator.outputReady = false
    generator.exitReady = false
    generator.succeeded = false
    generator.active = true
    generator.command = [
      "bash", root.sourceDir + "/generate-password.sh",
      String(root.passwordLength), root.includeSymbols ? "true" : "false"
    ]
    generator.running = true
    cancelButton.forceActiveFocus()
  }

  function entryExists(name) {
    if (!name || root.entries.length === 0) return false
    for (var i = 0; i < root.entries.length; i++) {
      if (root.entries[i] === name) return true
    }
    return false
  }

  function doSave() {
    if (root.generatingPassword) return
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
    root.clearAdd()
    root.mode = "list"
    root.filterText = name
    if (searchBox) searchBox.text = name
    adder.command = ["bash", root.sourceDir + "/add-entry.sh", name, value]
    adder.running = true
    Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
  }

  onOpenedChanged: {
    if (!opened) {
      root.clearAdd()
      return
    }
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
    id: generator
    property bool active: false
    property int session: 0
    property int requestedLength: 0
    property bool outputReady: false
    property bool exitReady: false
    property bool succeeded: false

    function finish() {
      // Process exit and stream completion can arrive in either order.
      if (!active || !outputReady || !exitReady) return
      var password = String(generatorOut.text || "").replace(/\n$/, "")
      active = false
      if (session !== root.addSession || root.mode !== "add" || !root.opened) return
      if (!succeeded || password.length !== requestedLength) {
        root.generationError = "Could not generate a password. Please try again."
        return
      }
      root.pendingValue = password
      valueField.text = password
      Qt.callLater(function() {
        if (root.opened && root.mode === "add") valueField.forceActiveFocus()
      })
    }

    stdout: StdioCollector {
      id: generatorOut
      waitForEnd: true
      onStreamFinished: {
        generator.outputReady = true
        generator.finish()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      generator.succeeded = exitCode === 0 && exitStatus === 0
      generator.exitReady = true
      generator.finish()
    }
  }

  Process {
    id: deleter
    stdout: StdioCollector { id: deleterOut; waitForEnd: true }
    onExited: {
      root.mode = "list"
      root.currentEntry = ""
      root.actions = []
      root.selectedIndex = 0
      entryLister.running = true
      Qt.callLater(function() { if (searchBox) searchBox.forceActiveFocus() })
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
            if (event.key === Qt.Key_Escape && root.mode === "add") {
              root.cancelAdd(); event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
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

      // ---------- Add mode: name, value, and password generation ----------

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
              if (generateButton.enabled) generateButton.forceActiveFocus()
              else cancelButton.forceActiveFocus()
              event.accepted = true
            }
          }
        }

        TextField {
          id: valueField
          width: parent.width
          foreground: root.foreground
          placeholderText: "Password or secret"
          text: root.pendingValue
          readOnly: root.generatingPassword
          onTextChanged: root.pendingValue = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelAdd(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.doSave(); event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              if (lengthField.enabled) lengthField.field.forceActiveFocus()
              else cancelButton.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
              if (nameField) nameField.forceActiveFocus(); event.accepted = true
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          NumberField {
            id: lengthField
            width: Style.space(120)
            fieldWidth: width
            label: "Password length"
            from: 1
            to: 128
            value: root.passwordLength
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.generatingPassword
            opacity: enabled ? 1 : 0.5
            onModified: function(value) { root.passwordLength = value }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                symbolsToggle.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                valueField.forceActiveFocus(); event.accepted = true
              }
            }
          }

          Toggle {
            id: symbolsToggle
            width: parent.width - lengthField.width - parent.spacing
            height: lengthField.implicitHeight
            label: "Include symbols"
            titleSize: Style.font.body
            checked: root.includeSymbols
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.generatingPassword
            opacity: enabled ? 1 : 0.5
            onClicked: {
              root.includeSymbols = !root.includeSymbols
              symbolsToggle.forceActiveFocus()
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                cancelButton.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                lengthField.field.forceActiveFocus(); event.accepted = true
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.generationError !== ""
          text: root.generationError
          textFormat: Text.PlainText
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Flow {
          width: parent.width
          spacing: Style.space(10)

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
                if (saveButton.enabled) saveButton.forceActiveFocus()
                else if (generateButton.enabled) generateButton.forceActiveFocus()
                else nameField.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                if (symbolsToggle.enabled) symbolsToggle.forceActiveFocus()
                else valueField.forceActiveFocus()
                event.accepted = true
              }
            }
          }

          Button {
            id: saveButton
            text: "Save"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: !root.generatingPassword && root.pendingName.trim() !== "" && root.pendingValue !== ""
            opacity: enabled ? 1 : 0.5
            onClicked: root.doSave()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                generateButton.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                cancelButton.forceActiveFocus(); event.accepted = true
              }
            }
          }

          Button {
            id: generateButton
            text: root.generatingPassword ? "Generating..." : "Generate password"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: !root.generatingPassword
            opacity: enabled ? 1 : 0.5
            onClicked: root.generatePassword()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd(); event.accepted = true
              } else if (event.key === Qt.Key_Tab) {
                if (nameField) nameField.forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Backtab) {
                if (saveButton.enabled) saveButton.forceActiveFocus()
                else cancelButton.forceActiveFocus()
                event.accepted = true
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
        visible: root.mode !== "add"
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
      anchors.fill: parent
      z: 10
      property string entryName: ""
      property string entryValue: ""
      message: ""
      confirmText: "Overwrite"
      foreground: root.foreground
      fontFamily: root.fontFamily
      background: Commons.Color.popups.background
      scrim: Util.alpha(Commons.Color.popups.background, 0.7)
      opened: false
      onConfirmed: {
        root.saveEntry(entryName, entryValue)
        opened = false
      }
      onCanceled: {
        opened = false
        if (nameField) nameField.forceActiveFocus()
      }
      Item {
        anchors.fill: parent
        visible: overwriteDialog.opened
        focus: overwriteDialog.opened
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (overwriteDialog.handleKey(event)) event.accepted = true
        }
      }
    }

    ConfirmDialog {
      id: deleteDialog
      anchors.fill: parent
      z: 10
      property string entryName: ""
      message: ""
      confirmText: "Delete"
      foreground: root.foreground
      fontFamily: root.fontFamily
      background: Commons.Color.popups.background
      scrim: Util.alpha(Commons.Color.popups.background, 0.7)
      opened: false
      onConfirmed: {
        root.deleteEntry(entryName)
        opened = false
      }
      onCanceled: {
        opened = false
        if (entryList) entryList.forceActiveFocus()
      }
      Item {
        anchors.fill: parent
        visible: deleteDialog.opened
        focus: deleteDialog.opened
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (deleteDialog.handleKey(event)) event.accepted = true
        }
      }
    }
  }
}
