// EngineManager.swift
// Rôle du fichier : référentiel des moteurs UCI de l'application — ajout,
// suppression et persistance (JSON) dans le répertoire Application Support.

import Foundation
import Combine

/// Gère la liste des moteurs et sa sauvegarde sur disque (engines.json).
class EngineManager: ObservableObject {
    @Published var engines: [Engine] = []

    /// Chemin du fichier de persistance des moteurs (Application Support).
    private let savePath: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("ChessnutAir")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engines.json")
    }()

    init() {
        load()
    }

    /// Ajoute un nouveau moteur et sauvegarde la liste.
    func addEngine(name: String, path: String) {
        let engine = Engine(name: name, path: path)
        engines.append(engine)
        save()
    }

    /// Retire un moteur (arrêt propre) et sauvegarde la liste.
    func removeEngine(_ engine: Engine) {
        engine.stop()
        engines.removeAll { $0.id == engine.id }
        save()
    }

    /// Sauvegarde la liste des moteurs en JSON atomique.
    func save() {
        guard let path = savePath else { return }
        if let data = try? JSONEncoder().encode(engines) {
            try? data.write(to: path, options: .atomic)
        }
    }

    /// Charge la liste des moteurs depuis le disque (si le fichier existe).
    func load() {
        guard let path = savePath,
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([Engine].self, from: data) else { return }
        engines = decoded
    }
}
