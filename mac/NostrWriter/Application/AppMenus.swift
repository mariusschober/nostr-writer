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
        // macOS hosts Services - including translation of the selected passage -
        // in the application menu, but AppKit only populates that submenu if the
        // app supplies the item. This menu bar is built programmatically, so
        // without this the whole Services menu is unreachable and ordinary
        // writing loses it. The submenu is intentionally empty here: the system
        // fills it from the registered service providers.
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let services = NSMenu(title: "Services")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        app.addItem(servicesItem)
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
        item(file, "Duplicate", #selector(WriterDocument.duplicateWriting(_:)))
        item(file, "Revert to Saved…", #selector(WriterDocument.revertPreservingChanges(_:)))
        item(file, "Rename…", Selector(("renameDocument:")))
        item(file, "Move To…", Selector(("moveDocument:")))
        item(file, "Move to Trash…", #selector(WriterDocument.moveSourceToTrash(_:)))
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
        // AppKit does not add a Spelling submenu to a programmatically built
        // menu bar. Continuous spelling and grammar indications are on by
        // default; these are the standard native routes to act on them.
        edit.addItem(.separator())
        let spelling = NSMenu(title: "Spelling and Grammar")
        let spellingItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        spellingItem.submenu = spelling
        item(spelling, "Show Spelling and Grammar", #selector(AppDelegate.showSpellingAndGrammar(_:)), ":")
        item(spelling, "Check Document Now", #selector(NSText.checkSpelling(_:)), ";")
        spelling.addItem(.separator())
        item(spelling, "Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)))
        item(spelling, "Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)))
        item(spelling, "Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))
        edit.addItem(spellingItem)
        let format = menu("Format")
        for formatting in EditorCommands.Formatting.allCases {
            let value = NSMenuItem(title: formatting.title, action: #selector(WriterWindowController.applyFormatting(_:)), keyEquivalent: "")
            value.representedObject = formatting.rawValue
            format.addItem(value)
        }
        format.addItem(.separator())
        item(format, "Insert Image…", #selector(WriterDocument.insertImage(_:)))
        item(format, "Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)))
        format.addItem(.separator())
        item(format, "Dictate On This Mac", #selector(WriterWindowController.toggleDictation(_:)))
        let view = menu("View")
        item(view, "Toggle Sidebar", #selector(WriterWindowController.toggleSidebar(_:)), "s", [.command, .control])
        item(view, "Toggle Inspector", #selector(WriterWindowController.toggleInspector(_:)), "i", [.command, .option])
        item(view, "Focus Writing", #selector(WriterWindowController.toggleFocusWriting(_:)), "f", [.command, .shift])
        item(view, "Typewriter Scrolling", #selector(WriterWindowController.toggleTypewriterScrolling(_:)))
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        let focus = menu("Focus")
        item(focus, "Focus Session (available in Stage 07)", nil)
        let passage = menu("Passage")
        item(passage, "Show Inspector", #selector(WriterWindowController.showPassageInspector(_:)))
        let window = menu("Window"); NSApp.windowsMenu = window
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        let help = menu("Help"); NSApp.helpMenu = help
        item(help, "Nostr Writer Help", #selector(AppDelegate.showWriterHelp(_:)))
        return bar
    }
}
