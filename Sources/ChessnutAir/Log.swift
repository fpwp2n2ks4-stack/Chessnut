// Log.swift
// Rôle du fichier : journalisation minimale — écriture horodatée sur la sortie
// standard, par catégorie (App, Chess, Engine, Tournament). Garde l'API de la
// version complète pour que les fichiers réutilisés (Engine, Chessnut) ne
// changent pas.

import Foundation

/// API de journalisation : niveaux debug/info/notice/error.
enum Log {
    static func debug(_ category: String, _ message: @autoclosure () -> String) {
        write(category, "DEBUG", message())
    }
    static func info(_ category: String, _ message: @autoclosure () -> String) {
        write(category, "INFO", message())
    }
    static func notice(_ category: String, _ message: @autoclosure () -> String) {
        write(category, "NOTICE", message())
    }
    static func error(_ category: String, _ message: @autoclosure () -> String) {
        write(category, "ERROR", message())
    }

    private static func write(_ category: String, _ level: String, _ message: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        print("[\(df.string(from: Date()))] [\(category)/\(level)] \(message)")
    }

    /// Raccourcis pour la catégorie Moteur.
    struct engine {
        static func debug(_ message: @autoclosure () -> String) { Log.debug("Engine", message()) }
        static func info(_ message: @autoclosure () -> String) { Log.info("Engine", message()) }
        static func notice(_ message: @autoclosure () -> String) { Log.notice("Engine", message()) }
        static func error(_ message: @autoclosure () -> String) { Log.error("Engine", message()) }
    }

    /// Raccourcis pour la catégorie Tournoi/Partie.
    struct tournament {
        static func debug(_ message: @autoclosure () -> String) { Log.debug("Tournament", message()) }
        static func info(_ message: @autoclosure () -> String) { Log.info("Tournament", message()) }
        static func notice(_ message: @autoclosure () -> String) { Log.notice("Tournament", message()) }
        static func error(_ message: @autoclosure () -> String) { Log.error("Tournament", message()) }
    }

    /// Raccourcis pour la catégorie Échecs/plateau.
    struct chess {
        static func debug(_ message: @autoclosure () -> String) { Log.debug("Chess", message()) }
        static func info(_ message: @autoclosure () -> String) { Log.info("Chess", message()) }
        static func notice(_ message: @autoclosure () -> String) { Log.notice("Chess", message()) }
        static func error(_ message: @autoclosure () -> String) { Log.error("Chess", message()) }
    }

    /// Raccourcis pour la catégorie Application.
    struct app {
        static func debug(_ message: @autoclosure () -> String) { Log.debug("App", message()) }
        static func info(_ message: @autoclosure () -> String) { Log.info("App", message()) }
        static func notice(_ message: @autoclosure () -> String) { Log.notice("App", message()) }
        static func error(_ message: @autoclosure () -> String) { Log.error("App", message()) }
    }
}
