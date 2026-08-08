// main.swift
// Rôle du fichier : point d'entrée de l'application — crée le delegate,
// installe l'application NSApplication et lance la boucle d'événements.

import Cocoa

let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.run()
