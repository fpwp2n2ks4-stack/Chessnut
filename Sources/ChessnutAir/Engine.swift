// Engine.swift
// Rôle du fichier : modèle d'un moteur d'échecs UCI — lancement du processus,
// échanges de commandes (uci, isready, ucinewgame, go, stop, quit, setoption),
// lecture de sa sortie, capture des lignes info/bestmove/option et persistance
// de la configuration du moteur (nom, chemin, options, hash, threads).

import Foundation

/// Option UCI déclarée par un moteur (type, valeur par défaut/courante, bornes).
struct UCIOption: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var type: String
    var defaultVal: String
    var currentVal: String
    var min: String?
    var max: String?
    var varVals: [String]?

    enum CodingKeys: String, CodingKey {
        case name, type, defaultVal, currentVal, min, max, varVals
    }
}

/// Moteur d'échecs UCI : encapsule le processus, ses pipes d'entrée/sortie et
/// les callbacks vers l'orchestrateur de partie.
class Engine: Identifiable, ObservableObject, Codable {
    let id = UUID()
    @Published var name: String
    @Published var path: String
    @Published var arguments: String
    @Published var isActive: Bool
    @Published var options: [UCIOption]
    @Published var engineId: String
    @Published var author: String
    @Published var hashSize: Int
    @Published var threads: Int
    @Published var isRunning: Bool

    private var process: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var readSource: DispatchSourceRead?

    private let callbackLock = NSLock()
    private var _onInfo: ((String) -> Void)?
    private var _onBestMove: ((String) -> Void)?
    private var _onReady: (() -> Void)?
    private var _onTerminate: (() -> Void)?

    /// Callback appelé à chaque ligne `info` (analyse en cours).
    var onInfo: ((String) -> Void)? {
        get { callbackLock.withLock { _onInfo } }
        set { callbackLock.withLock { _onInfo = newValue } }
    }
    /// Callback appelé quand le moteur répond `bestmove`.
    var onBestMove: ((String) -> Void)? {
        get { callbackLock.withLock { _onBestMove } }
        set { callbackLock.withLock { _onBestMove = newValue } }
    }
    /// Callback appelé sur `uciok`/`readyok` (moteur prêt).
    var onReady: (() -> Void)? {
        get { callbackLock.withLock { _onReady } }
        set { callbackLock.withLock { _onReady = newValue } }
    }
    /// Callback appelé quand le processus moteur se termine.
    var onTerminate: (() -> Void)? {
        get { callbackLock.withLock { _onTerminate } }
        set { callbackLock.withLock { _onTerminate = newValue } }
    }

    enum CodingKeys: String, CodingKey {
        case name, path, arguments, isActive, options, engineId, author, hashSize, threads, isRunning
    }

    /// Nom d'affichage du moteur (nom ou chemin en repli).
    var displayName: String {
        name.isEmpty ? path : name
    }

    /// Initialise un moteur avec ses réglages par défaut.
    init(name: String = "", path: String = "", arguments: String = "") {
        self.name = name
        self.path = path
        self.arguments = arguments
        self.isActive = true
        self.options = []
        self.engineId = ""
        self.author = ""
        self.hashSize = 128
        self.threads = 1
        self.isRunning = false
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        arguments = try c.decode(String.self, forKey: .arguments)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        options = try c.decode([UCIOption].self, forKey: .options)
        engineId = try c.decode(String.self, forKey: .engineId)
        author = try c.decode(String.self, forKey: .author)
        hashSize = try c.decode(Int.self, forKey: .hashSize)
        threads = try c.decode(Int.self, forKey: .threads)
        isRunning = false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(path, forKey: .path)
        try c.encode(arguments, forKey: .arguments)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(options, forKey: .options)
        try c.encode(engineId, forKey: .engineId)
        try c.encode(author, forKey: .author)
        try c.encode(hashSize, forKey: .hashSize)
        try c.encode(threads, forKey: .threads)
        try c.encode(false, forKey: .isRunning)
    }

    /// Démarre le processus moteur (si le fichier existe), crée les pipes et
    /// lance l'initiation UCI (`uci`).
    func start() {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)

        if !arguments.isEmpty {
            proc.arguments = arguments.components(separatedBy: " ")
        }

        let inp = Pipe()
        let out = Pipe()
        proc.standardInput = inp
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice

        inputPipe = inp
        outputPipe = out
        process = proc

        do {
            try proc.run()
            isRunning = true
            let startedName = name
            Log.engine.info("Started \(startedName) pid=\(proc.processIdentifier)")
            proc.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    Log.engine.info("\(self?.name ?? "?") terminated")
                    self?.isRunning = false
                    self?.onTerminate?()
                    self?.onTerminate = nil
                }
            }
            startReading()
            send("uci")
        } catch {
            isRunning = false
            let errName = name
            let errPath = path
            Log.engine.error("Failed to start \(errName) at \(errPath): \(error.localizedDescription)")
        }
    }

    /// Arrête le moteur : envoie `quit`, coupe la lecture puis tue le processus.
    func stop() {
        send("quit")
        readSource?.cancel()
        process?.terminate()
        process = nil
        isRunning = false
    }

    /// Envoie une commande texte au moteur (ligne UCI + saut de ligne).
    func send(_ command: String) {
        Log.engine.debug("→ \(command)")
        guard let data = (command + "\n").data(using: .utf8) else { return }
        try? inputPipe?.fileHandleForWriting.write(data)
    }

    /// Modifie la valeur d'une option UCI du moteur.
    func setOption(_ name: String, value: String) {
        send("setoption name \(name) value \(value)")
    }

    /// Signale au moteur qu'une nouvelle partie commence (purge des tables de transposition).
    func newGame() {
        send("ucinewgame")
    }

    /// Interroge la disponibilité du moteur (réponse `readyok`).
    func isready() {
        send("isready")
    }

    /// Démarre la lecture asynchrone de la sortie standard du moteur.
    private func startReading() {
        guard let handle = outputPipe?.fileHandleForReading else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                DispatchQueue.main.async {
                    self?.handleLine(trimmed)
                }
            }
        }
        source.setCancelHandler { [weak handle] in
            handle?.closeFile()
        }
        readSource = source
        source.resume()
    }

    /// Aiguille chaque ligne UCI reçue vers le bon callback (id, option,
    /// uciok, readyok, bestmove, info).
    private func handleLine(_ line: String) {
        Log.engine.debug("← \(line)")
        if line.hasPrefix("id name ") {
            engineId = String(line.dropFirst(8))
        } else if line.hasPrefix("id author ") {
            author = String(line.dropFirst(10))
        } else if line == "uciok" {
            onReady?()
            send("isready")
        } else if line == "readyok" {
            onReady?()
        } else if line.hasPrefix("option name ") {
            parseOption(line)
        } else if line.hasPrefix("bestmove ") {
            let move = String(line.dropFirst(9)).components(separatedBy: " ").first ?? ""
            onBestMove?(move)
        } else if line.hasPrefix("info ") {
            onInfo?(line)
        }
    }

    /// Analyse une ligne `option name … type …` et enregistre l'option UCI.
    private func parseOption(_ line: String) {
        var remaining = String(line.dropFirst(12))
        guard let nameRange = remaining.range(of: " type ") else { return }
        let name = String(remaining[remaining.startIndex..<nameRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        remaining = String(remaining[nameRange.upperBound...])

        var type = "", def = "", minV = "", maxV = "", varVals: [String] = []

        if let r = remaining.range(of: " default ") {
            type = String(remaining[remaining.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            remaining = String(remaining[r.upperBound...])

            if type == "check" {
                def = String(remaining.prefix(while: { !$0.isWhitespace }))
            } else if type == "combo" {
                let parts = remaining.components(separatedBy: " var ")
                def = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                varVals = parts.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            } else if type == "spin" {
                let parts = remaining.components(separatedBy: " ")
                def = parts.first ?? ""
                if let minIdx = remaining.range(of: " min ") {
                    minV = String(remaining[minIdx.upperBound...].prefix(while: { !$0.isWhitespace }))
                }
                if let maxIdx = remaining.range(of: " max ") {
                    maxV = String(remaining[maxIdx.upperBound...].prefix(while: { !$0.isWhitespace }))
                }
            } else {
                def = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            type = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let opt = UCIOption(name: name, type: type, defaultVal: def, currentVal: def, min: minV.isEmpty ? nil : minV, max: maxV.isEmpty ? nil : maxV, varVals: varVals.isEmpty ? nil : varVals)
        options.append(opt)
    }
}
