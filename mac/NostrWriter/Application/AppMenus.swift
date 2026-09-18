import AppKit

@MainActor
enum AppMenus {
    static func make() -> NSMenu {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let submenu = NSMenu(title: title); item.submenu = submenu; bar.addItem(item)
            return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command) {
            let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
            value.keyEquivalentModifierMask = modifiers; menu.addItem(value)
        }
        let app = menu("Nostr Writer")
        item(app, "About Nostr Writer", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        item(app, "Settings…", #selector(AppDelegate.showSettings(_:)), ",")
        app.addItem(.separator())
        item(app, "Hide Nostr Writer", #selector(NSApplication.hide(_:)), "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator()); item(app, "Quit Nostr Writer", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        item(file, "Import Text Copy…", #selector(AppDelegate.importTextCopy(_:)))
        file.addItem(.separator())
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save…", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        item(file, "Duplicate", #selector(NSDocument.duplicate(_:)))
        item(file, "Revert to Saved…", #selector(WriterDocument.revertPreservingChanges(_:)))
        item(file, "Reveal in Finder", #selector(WriterDocument.revealInFinder(_:)))
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        item(edit, "Find…", #selector(NSTextView.performFindPanelAction(_:)), "f")
        edit.items.last?.tag = NSTextFinder.Action.showFindInterface.rawValue
        let format = menu("Format")
        item(format, "Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)))
        let view = menu("View")
        item(view, "Toggle Sidebar", #selector(WriterWindowController.toggleSidebar(_:)), "s", [.command, .control])
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        let focus = menu("Focus")
        item(focus, "Focus Session (available in Stage 07)", nil)
        let window = menu("Window"); NSApp.windowsMenu = window
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        let help = menu("Help"); NSApp.helpMenu = help
        item(help, "Nostr Writer Help", #selector(AppDelegate.showWriterHelp(_:)))
        return bar
    }
}
