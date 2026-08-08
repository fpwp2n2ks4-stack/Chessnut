// App.swift
// Rôle du fichier : amorçage de l'application — menu, fenêtres (plateau et
// commandes), moteurs et échiquier Chessnut.

import SwiftUI

/// AppDelegate : amorçage de l'application (menu, fenêtres, moteurs,
/// échiquier Chessnut) et ouverture des fenêtres principales.
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var controlsWindow: NSWindow?

    let engineManager = EngineManager()
    let chessnut = ChessnutManager()
    lazy var play = PlayController(chessnut: chessnut, engineManager: engineManager)

    /// Au lancement : configure l'app, charge les moteurs, lit la position
    /// mémorisée du plateau et construit le menu.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange),
            name: LanguageManager.didChange, object: nil
        )

        openBoardWindow()
        openControlsWindow()
        setupMenu()
    }

    /// Réagit au changement de langue : met à jour les titres de fenêtres et le menu.
    @objc private func languageDidChange() {
        window?.title = loc("window.board.title")
        controlsWindow?.title = loc("window.controls.title")
        setupMenu()
    }

    /// L'app reste active même sans fenêtre ouverte.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Windows

    /// Amène la fenêtre Plateau au premier plan (ou la crée si besoin).
    @objc func selectBoardWindow() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        } else {
            if window == nil { openBoardWindow() }
            window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Affiche/masque la fenêtre Commandes.
    @objc func toggleControlsWindow() {
        if let cw = controlsWindow, cw.isVisible {
            cw.orderOut(nil)
        } else if let cw = controlsWindow {
            cw.makeKeyAndOrderFront(nil)
        } else {
            openControlsWindow()
        }
    }

    /// Crée la fenêtre Plateau (carrée, position mémorisée).
    func openBoardWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = loc("window.board.title")
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("ChessnutAirBoard")
        if w.frame.width != w.frame.height {
            var frame = w.frame
            frame.size.height = frame.size.width
            w.setFrame(frame, display: true)
        }
        w.minSize = NSSize(width: 300, height: 300)
        w.aspectRatio = NSSize(width: 1, height: 1)

        let contentView = NSHostingView(rootView: ChessBoardView(game: play.game, play: play))
        w.contentView = contentView
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    /// Crée la fenêtre Commandes (connexion, moteur, cadences, actions).
    func openControlsWindow() {
        let contentView = NSHostingView(rootView: PlayView(play: play))

        let cw = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        cw.title = loc("window.controls.title")
        cw.contentView = contentView
        cw.isReleasedWhenClosed = false
        cw.minSize = NSSize(width: 320, height: 400)
        cw.setFrameAutosaveName("ChessnutAirControls")
        cw.center()
        cw.makeKeyAndOrderFront(nil)
        controlsWindow = cw
    }

    // MARK: - Menu

    /// Construit le menu principal (fichiers, édition, fenêtres).
    func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: loc("menu.app.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: loc("menu.app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = appMenu.addItem(withTitle: loc("menu.app.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: loc("menu.app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: loc("menu.app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: loc("menu.edit"))
        editMenu.addItem(withTitle: loc("menu.edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: loc("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: loc("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: loc("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: loc("menu.window"))
        let boardMenuItem = windowMenu.addItem(withTitle: loc("menu.window.board"), action: #selector(selectBoardWindow), keyEquivalent: "1")
        boardMenuItem.keyEquivalentModifierMask = .command
        let controlsMenuItem = windowMenu.addItem(withTitle: loc("menu.window.controls"), action: #selector(toggleControlsWindow), keyEquivalent: "2")
        controlsMenuItem.keyEquivalentModifierMask = .command
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: loc("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: loc("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: loc("menu.window.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
