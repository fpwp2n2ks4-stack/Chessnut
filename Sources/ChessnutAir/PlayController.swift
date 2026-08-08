// PlayController.swift
// Rôle du fichier : orchestration d'une partie « Échiquier physique Chessnut »
// contre un moteur UCI. Gère le flux FEN du plateau (détection des coups
// physiques), le guidage par LED du coup du moteur, le contrôle du temps,
// la détection de fin de partie et l'enchaînement des parties d'une série.
// Inspiré du mode « Échiquier vs Moteur » du projet Atelier (Tournament.swift).

import Foundation
import AppKit
import Combine

/// Option de contrôle du temps (nom, temps + incrément).
struct TimeControlOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let timeSeconds: Int
    let incrementSeconds: Int

    static let all: [TimeControlOption] = [
        TimeControlOption(name: "1s fixe", timeSeconds: 1, incrementSeconds: 0),
        TimeControlOption(name: "5s fixe", timeSeconds: 5, incrementSeconds: 0),
        TimeControlOption(name: "10s fixe", timeSeconds: 10, incrementSeconds: 0),
        TimeControlOption(name: "1 min", timeSeconds: 60, incrementSeconds: 0),
        TimeControlOption(name: "1 min + 1s", timeSeconds: 60, incrementSeconds: 1),
        TimeControlOption(name: "3 min", timeSeconds: 180, incrementSeconds: 0),
        TimeControlOption(name: "3 min + 2s", timeSeconds: 180, incrementSeconds: 2),
        TimeControlOption(name: "5 min", timeSeconds: 300, incrementSeconds: 0),
        TimeControlOption(name: "5 min + 3s", timeSeconds: 300, incrementSeconds: 3),
        TimeControlOption(name: "10 min", timeSeconds: 600, incrementSeconds: 0),
        TimeControlOption(name: "10 min + 5s", timeSeconds: 600, incrementSeconds: 5),
        TimeControlOption(name: "30 min", timeSeconds: 1800, incrementSeconds: 0),
        TimeControlOption(name: "60 min", timeSeconds: 3600, incrementSeconds: 0),
    ]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TimeControlOption, rhs: TimeControlOption) -> Bool {
        lhs.id == rhs.id
    }
}

/// Enregistrement d'une partie jouée (numéro, joueurs, coups UCI, résultat).
struct GameRecord: Identifiable {
    let id = UUID()
    let gameNumber: Int
    let whiteName: String
    let blackName: String
    let moves: [String]
    let resultString: String
}

/// Orchestrateur de la partie Chessnut vs Moteur UCI.
final class PlayController: ObservableObject {
    let game = ChessGame()
    let chessnut: ChessnutManager
    let engineManager: EngineManager

    // MARK: - Configuration (choix utilisateur)

    @Published var engineIndex = 0
    @Published var playerName = loc("status.playerName")
    @Published var playerTC = TimeControlOption.all[5]
    @Published var engineTC = TimeControlOption.all[5]
    @Published var humanPlaysWhite = true
    @Published var swapColors = false
    @Published var numberOfGames = 1
    @Published var showLEDs = true
    @Published var showAnalysis = true

    // MARK: - État de la partie

    @Published var isRunning = false
    @Published var isPaused = false
    @Published var currentGameNumber = 1
    @Published var statusMessage = ""
    @Published var checkAlert = ""
    @Published var whiteName = ""
    @Published var blackName = ""
    @Published var whiteTimeMs = 0
    @Published var blackTimeMs = 0
    @Published var analysis = ""
    @Published var humanWins = 0
    @Published var engineWins = 0
    @Published var draws = 0
    @Published var games: [GameRecord] = []

    // MARK: - État interne

    private var engine: Engine?
    private var hveShouldStop = false
    private var baseHumanPlaysWhite = true
    private var startTime: Date?
    private var moves: [String] = []
    private var cancellables = Set<AnyCancellable>()
    private var chessnutNeedsSetup = false
    private var pendingBoardMoveTimer: Timer?
    private var pendingBoardMoveUCI: String?
    private var pendingBoardMovePlacement: String?
    private var pendingSyncTimer: Timer?
    private var pendingSyncPlacement: String?
    private var pendingSyncMessage: String?
    private var pendingSyncUCI: String?
    private var pendingGameEndCheck = false
    private var pendingGameEndStablePlacement: String?
    private var pendingGameEndStableTimer: Timer?
    private var pendingSessionTransition = false

    init(chessnut: ChessnutManager, engineManager: EngineManager) {
        self.chessnut = chessnut
        self.engineManager = engineManager

        // Les vues observent le PlayController : on re-émet les changements de
        // l'échiquier (connexion, scan, batterie…) et des moteurs pour que
        // l'interface se rafraîchisse.
        chessnut.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        engineManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    /// Moteur actuellement sélectionné dans la liste.
    var selectedEngine: Engine? {
        guard engineIndex < engineManager.engines.count else { return nil }
        return engineManager.engines[engineIndex]
    }

    /// Vrai si une partie peut être lancée (échiquier connecté + moteur choisi).
    var canStart: Bool {
        chessnut.state.isConnected && selectedEngine != nil && !isRunning
    }

    // MARK: - Sons et alertes

    /// Joue un son système macOS.
    private func playSound(_ name: String) {
        if let sound = NSSound(named: name) {
            sound.play()
        }
    }

    /// Affiche une alerte (échec, mat, coup interdit…) et joue son son, en
    /// évitant de répéter la même alerte sans arrêt.
    private func announce(_ message: String, sound: String) {
        guard checkAlert != message else { return }
        checkAlert = message
        playSound(sound)
    }

    /// Efface l'alerte en cours (échec résolu, position corrigée…).
    private func clearAlert() {
        checkAlert = ""
    }

    /// Met à jour l'alerte « échec au roi » : son + affichage quand le camp à
    /// jouer est en échec, sinon effacement de l'alerte.
    private func updateCheckAlert() {
        if game.isKingInCheck(game.currentTurn) {
            announce(loc("status.check"), sound: "Hero")
        } else {
            clearAlert()
        }
    }

    // MARK: - Horloges

    private var humanClockMs: Int { humanPlaysWhite ? whiteTimeMs : blackTimeMs }
    private func setHumanClock(_ ms: Int) {
        if humanPlaysWhite { whiteTimeMs = ms } else { blackTimeMs = ms }
    }
    private var engineClockMs: Int { humanPlaysWhite ? blackTimeMs : whiteTimeMs }
    private func setEngineClock(_ ms: Int) {
        if humanPlaysWhite { blackTimeMs = ms } else { whiteTimeMs = ms }
    }

    // MARK: - Contrôles (UI)

    /// Démarre une série de parties sur l'échiquier physique contre le moteur.
    func start() {
        guard let engine = selectedEngine else {
            statusMessage = loc("status.invalidEngineIndex")
            return
        }
        guard chessnut.state.isConnected else {
            statusMessage = loc("chessnut.notConnected")
            return
        }

        self.engine = engine
        hveShouldStop = false
        isPaused = false
        isRunning = true
        currentGameNumber = 1
        humanWins = 0
        engineWins = 0
        draws = 0
        games = []
        baseHumanPlaysWhite = humanPlaysWhite

        if !engine.isRunning {
            engine.start()
        }
        startGameInternal()
    }

    /// Arrête proprement la partie (moteur, LED, flux FEN).
    func stop() {
        chessnut.onFENChange = nil
        chessnut.clearLEDs()
        cancelPendingBoardMove()
        cancelPendingSyncError()
        cancelPendingGameEndStable()
        pendingSessionTransition = false
        pendingGameEndCheck = false
        game.isPhysicalBoard = false
        hveShouldStop = true
        engine?.onBestMove = nil
        engine?.onInfo = nil
        engine?.stop()
        engine = nil
        isPaused = false
        isRunning = false
        game.isHumanVsEngine = false
        game.isEngineThinking = false
        game.boardFlipped = false
        game.onHumanMove = nil
        statusMessage = loc("status.gameStopped")
    }

    /// Met la partie en pause.
    func pause() {
        isPaused = true
        game.isPaused = true
        engine?.send("stop")
        engine?.onBestMove = nil
        engine?.onInfo = nil
        game.isEngineThinking = false
        statusMessage = loc("status.gamePaused")
    }

    /// Reprend la partie après une pause.
    func resume() {
        guard let engine = engine else { return }
        isPaused = false
        game.isPaused = false

        if !engine.isRunning {
            engine.start()
            Task { await waitForReady(engine) }
        }

        let isEngineTurn = game.currentTurn != game.humanColor
        if isEngineTurn {
            game.isEngineThinking = true
            statusMessage = loc("status.engineThinking", engine.displayName)
            Task { await doEngineTurn() }
        } else {
            startTime = Date()
            statusMessage = loc("status.yourTurn")
        }
    }

    /// Exporte les parties jouées en PGN (boîte de dialogue).
    func savePGN() {
        guard !games.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let dateStr = dateFormatter.string(from: Date())

        var pgn = ""
        for record in games {
            pgn += "[Event \"Humain vs Moteur\"]\n"
            pgn += "[Site \"Chessnut Air\"]\n"
            pgn += "[Date \"\(dateStr)\"]\n"
            pgn += "[Round \"\(record.gameNumber)\"]\n"
            pgn += "[White \"\(record.whiteName)\"]\n"
            pgn += "[Black \"\(record.blackName)\"]\n"
            pgn += "[Result \"\(record.resultString)\"]\n"
            pgn += "\n"

            let replayGame = ChessGame()
            var moveText = ""
            for (i, move) in record.moves.enumerated() {
                if i % 2 == 0 {
                    moveText += "\(i / 2 + 1). "
                }
                let san = replayGame.moveToSAN(uci: move)
                replayGame.applyUCIMoveSync(move)
                moveText += "\(san) "
            }
            pgn += moveText + "\(record.resultString)\n\n"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "pgn")!]
        panel.nameFieldStringValue = loc("pgn.filename")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pgn.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Préparation d'une partie

    /// Prépare une partie : réinitialise le plateau, démarre le moteur, branche
    /// le flux FEN et n'autorise le premier coup qu'une fois le plateau réglé
    /// sur la position de départ.
    private func startGameInternal() {
        guard !hveShouldStop, let engine, engine.isRunning else { return }
        guard chessnut.state.isConnected else { return }

        isPaused = false
        analysis = ""
        moves = []
        pendingGameEndCheck = false
        cancelPendingGameEndStable()
        humanPlaysWhite = humanPlaysWhiteInGame(currentGameNumber)
        if numberOfGames > 1 {
            statusMessage = loc("move.gameProgress", currentGameNumber, numberOfGames)
        } else {
            statusMessage = loc("status.starting")
        }
        let humanName = playerName.isEmpty ? loc("status.playerName") : playerName
        if humanPlaysWhite {
            whiteName = humanName
            blackName = engine.displayName
        } else {
            whiteName = engine.displayName
            blackName = humanName
        }
        whiteTimeMs = (humanPlaysWhite ? playerTC : engineTC).timeSeconds * 1000
        blackTimeMs = (humanPlaysWhite ? engineTC : playerTC).timeSeconds * 1000

        game.resetGame()
        game.isHumanVsEngine = true
        game.isPhysicalBoard = true
        game.isEngineThinking = false
        game.humanColor = humanPlaysWhite ? .white : .black
        game.boardFlipped = !humanPlaysWhite

        // On ne démarre que lorsque le plateau physique est en position initiale.
        chessnutNeedsSetup = chessnut.lastPlacement != startPlacement
        if chessnutNeedsSetup {
            statusMessage = loc("chessnut.setup")
        }

        Task { @MainActor in
            if !engine.isRunning {
                engine.start()
            }
            await waitForReady(engine)
            applyOptions(to: engine)
            engine.newGame()
            await waitForReady(engine)
            guard engine.isRunning else {
                statusMessage = loc("status.engineFailed")
                stop()
                return
            }

            chessnut.onFENChange = { [weak self] placement in
                Task { @MainActor in
                    self?.handleBoardPlacement(placement)
                }
            }

            if !chessnutNeedsSetup {
                beginTurn()
            }
        }
    }

    /// Démarre le tour : le moteur réfléchit (LED de guidage) ou l'humain joue.
    private func beginTurn() {
        guard !hveShouldStop, !isPaused else { return }
        let isEngineTurn = game.currentTurn != game.humanColor
        if isEngineTurn {
            game.isEngineThinking = true
            statusMessage = loc("status.enginePlays", engine?.displayName ?? "")
            startTime = Date()
            Task { await doEngineTurn() }
        } else {
            startTime = Date()
            statusMessage = loc("status.yourTurn")
        }
    }

    /// Placement FEN de la position initiale (pour vérifier le réglage du plateau).
    private var startPlacement: String {
        String(ChessGame().toFEN().split(separator: " ")[0])
    }

    // MARK: - Flux FEN du plateau

    /// Point d'entrée du flux FEN de l'échiquier : met à jour le plateau,
    /// détecte le coup joué physiquement et gère l'exécution des coups moteur,
    /// les erreurs de synchronisation et la fin de partie différée.
    private func handleBoardPlacement(_ placement: String) {
        guard let engine, engine.isRunning,
              chessnut.state.isConnected,
              !hveShouldStop else { return }

        // Réglage initial : on suit le plateau jusqu'à la position de départ.
        if chessnutNeedsSetup {
            game.syncPlacement(placement)
            Log.tournament.info("Setup: synced to \(placement) (target \(startPlacement))")
            if placement == startPlacement {
                chessnutNeedsSetup = false
                beginTurn()
            }
            return
        }

        // Pendant que le moteur réfléchit, que la partie est en pause ou qu'une
        // transition de session est en cours, on se contente de suivre l'état
        // physique sans interpréter de coup.
        guard !isPaused, !hveShouldStop, !pendingSessionTransition,
              game.currentTurn == game.humanColor else { return }

        let prev = game.placementString()

        // Le plateau rejoint l'état interne : l'utilisateur a exécuté le coup du
        // moteur physiquement (ou il est revenu à la dernière position) → on
        // éteint les LED de guidage et on efface une éventuelle erreur de sync.
        if placement == prev {
            if showLEDs {
                chessnut.clearLEDs()
            }
            if statusMessage == loc("chessnut.syncError")
                || statusMessage == loc("chessnut.illegalMove")
                || statusMessage == loc("chessnut.illegalCheck") {
                statusMessage = loc("status.yourTurn")
                clearAlert()
            }
            cancelPendingBoardMove()
            cancelPendingSyncError()
            if pendingGameEndCheck {
                // Le coup du moteur vient d'être exécuté sur le plateau et il
                // termine la partie (échec et mat, pat…) → fin maintenant.
                pendingGameEndCheck = false
                cancelPendingGameEndStable()
                checkHumanGameEnd()
            }
            return
        }

        // Fin de partie différée : le coup du moteur doit être exécuté sur le
        // plateau. Si une position stable ne rejoint pas l'état interne, on
        // guide l'utilisateur au lieu d'attendre en silence.
        if pendingGameEndCheck {
            // Pièce en main (compteur de pièces différent) : transition en cours.
            if placement.filter({ $0.isLetter }).count != prev.filter({ $0.isLetter }).count {
                return
            }
            if placement == pendingGameEndStablePlacement { return }
            pendingGameEndStablePlacement = placement
            pendingGameEndStableTimer?.invalidate()
            pendingGameEndStableTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          self.pendingGameEndCheck,
                          self.pendingGameEndStablePlacement == placement,
                          placement != self.game.placementString(),
                          !self.isPaused, !self.hveShouldStop else {
                        self?.cancelPendingGameEndStable()
                        return
                    }
                    self.cancelPendingGameEndStable()
                    if self.showLEDs, let move = self.moves.last, let parsed = parseUCIMove(move) {
                        self.chessnut.lightSquares([parsed.from, parsed.to])
                    }
                    self.statusMessage = loc("chessnut.gameEndPending")
                }
            }
            return
        }

        // Même position que le coup déjà en attente de confirmation (le plateau
        // répète la position en continu) → on laisse le minuteur tourner.
        if placement == pendingBoardMovePlacement {
            return
        }

        let uci = game.detectMove(previousPlacement: prev, currentPlacement: placement)

        // Coup valide : on attend que la position se stabilise avant de
        // l'appliquer, sinon un glissement de pièce détecterait chaque case
        // intermédiaire comme un coup.
        if let uci,
           let parsed = parseUCIMove(uci),
           game.pieceAt(parsed.from) != nil,
           game.calculateValidMoves(for: parsed.from).contains(parsed.to) {
            cancelPendingBoardMove()
            cancelPendingSyncError()
            pendingBoardMovePlacement = placement
            pendingBoardMoveUCI = uci
            pendingBoardMoveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.confirmPendingBoardMove()
                }
            }
            return
        }

        let (froms, tos) = ChessGame.moveCandidates(between: prev, and: placement, color: game.currentTurn)
        if froms.isEmpty || tos.isEmpty {
            // Aucun changement (exécution physique du coup du moteur) ou
            // transition en cours (pièce en main) → on attend.
            cancelPendingBoardMove()
            cancelPendingSyncError()
            return
        }

        // Le placement correspond à un coup possible, mais ce coup est illégal
        // (par exemple le roi reste en échec). On attend que la position se
        // stabilise avant d'afficher l'erreur.
        if let uci,
           let parsed = parseUCIMove(uci),
           game.pieceAt(parsed.from) != nil {
            let message = game.isKingInCheck(game.currentTurn)
                ? loc("chessnut.illegalCheck")
                : loc("chessnut.illegalMove")
            scheduleSyncError(placement: placement, uci: uci, message: message)
            return
        }

        scheduleSyncError(placement: placement, uci: nil, message: loc("chessnut.syncError"))
    }

    /// Annule le coup physique en attente de confirmation (timer de stabilisation).
    private func cancelPendingBoardMove() {
        pendingBoardMoveTimer?.invalidate()
        pendingBoardMoveTimer = nil
        pendingBoardMovePlacement = nil
        pendingBoardMoveUCI = nil
    }

    /// Planifie l'affichage d'une erreur de synchronisation après stabilisation.
    private func scheduleSyncError(placement: String, uci: String?, message: String) {
        pendingSyncPlacement = placement
        pendingSyncMessage = message
        pendingSyncUCI = uci
        pendingSyncTimer?.invalidate()
        pendingSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.pendingSyncPlacement == placement,
                      let message = self.pendingSyncMessage,
                      !self.isPaused, !self.hveShouldStop,
                      self.game.currentTurn == self.game.humanColor,
                      placement != self.game.placementString() else {
                    self?.cancelPendingSyncError()
                    return
                }
                let (froms, tos) = ChessGame.moveCandidates(between: self.game.placementString(), and: placement, color: self.game.currentTurn)
                guard !froms.isEmpty, !tos.isEmpty else {
                    self.cancelPendingSyncError()
                    return
                }
                let uci = self.pendingSyncUCI
                self.pendingSyncTimer = nil
                self.pendingSyncPlacement = nil
                self.pendingSyncMessage = nil
                self.pendingSyncUCI = nil
                if let uci {
                    Log.tournament.error("Illegal board move \(uci):\n  game: \(self.game.placementString())\n  board: \(placement)")
                } else {
                    Log.tournament.error("Physical board out of sync:\n  game: \(self.game.placementString())\n  board: \(placement)")
                }
                self.statusMessage = message
                self.announce(message, sound: "Basso")
            }
        }
    }

    /// Annule une erreur de synchronisation en attente d'affichage.
    private func cancelPendingSyncError() {
        pendingSyncTimer?.invalidate()
        pendingSyncTimer = nil
        pendingSyncPlacement = nil
        pendingSyncMessage = nil
        pendingSyncUCI = nil
    }

    /// Annule le minuteur de vérification de fin de partie sur plateau physique.
    private func cancelPendingGameEndStable() {
        pendingGameEndStableTimer?.invalidate()
        pendingGameEndStableTimer = nil
        pendingGameEndStablePlacement = nil
    }

    /// Valide un coup physique une fois la position stabilisée : l'applique au
    /// jeu, allume les LED si demandé et transmet le coup au moteur.
    private func confirmPendingBoardMove() {
        guard let uci = pendingBoardMoveUCI else { return }
        pendingBoardMoveTimer = nil
        pendingBoardMovePlacement = nil
        pendingBoardMoveUCI = nil

        guard !isPaused, !hveShouldStop,
              let engine, engine.isRunning,
              game.currentTurn == game.humanColor,
              let parsed = parseUCIMove(uci),
              game.pieceAt(parsed.from) != nil,
              game.calculateValidMoves(for: parsed.from).contains(parsed.to) else { return }

        Log.tournament.info("Board move detected: \(uci)")
        game.applyUCIMoveSync(uci)
        if showLEDs {
            chessnut.lightSquares([parsed.from, parsed.to])
        }

        Task { await handleHumanMove(uci) }
    }

    // MARK: - Déroulement des tours

    /// Traite le coup de l'humain : met à jour le temps, vérifie la fin de
    /// partie, sinon lance le tour du moteur.
    private func handleHumanMove(_ uci: String) async {
        guard let engine, engine.isRunning, !isPaused, !hveShouldStop else { return }

        moves.append(uci)

        if let start = startTime {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let inc = playerTC.incrementSeconds * 1000
            setHumanClock(max(0, humanClockMs - elapsed + inc))
        }

        let gameEnded = await MainActor.run { () -> Bool in
            if game.isStalemate() || game.isInsufficientMaterial() ||
               (game.isKingInCheck(game.currentTurn) && !game.hasLegalMoves(game.currentTurn)) {
                checkHumanGameEnd()
                return true
            }
            return false
        }
        if gameEnded { return }

        // Alerte échec (ou effacement) quand le coup de l'humain met le roi du
        // moteur en échec, ou résout l'échec précédent.
        await MainActor.run { updateCheckAlert() }

        await doEngineTurn()
    }

    /// Exécute le tour du moteur : envoie la position, lance `go`, attend le
    /// meilleur coup (avec timeout) et l'applique au plateau (LED si échiquier).
    private func doEngineTurn() async {
        guard let engine, engine.isRunning, !isPaused, !hveShouldStop else { return }

        let enginePlaysWhite = !humanPlaysWhite

        await MainActor.run {
            game.isEngineThinking = true
            statusMessage = loc("status.engineThinking", engine.displayName)
        }

        if showAnalysis {
            engine.onInfo = { [weak self] line in
                let parsed = self?.parseInfoLine(line) ?? line
                DispatchQueue.main.async {
                    self?.analysis = parsed
                }
            }
        } else {
            engine.onInfo = nil
        }

        let fen = await MainActor.run { game.toFEN() }
        engine.send("position fen \(fen)")

        let wtime = enginePlaysWhite ? engineClockMs : humanClockMs
        let btime = enginePlaysWhite ? humanClockMs : engineClockMs
        let winc = (enginePlaysWhite ? engineTC : playerTC).incrementSeconds * 1000
        let binc = (enginePlaysWhite ? playerTC : engineTC).incrementSeconds * 1000
        engine.send("go wtime \(wtime) btime \(btime) winc \(winc) binc \(binc)")

        let engineStart = Date()
        let bestMove = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let lock = NSLock()
            var resumed = false

            engine.onBestMove = { move in
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                engine.onBestMove = nil
                engine.onInfo = nil
                cont.resume(returning: move)
            }

            let maxTime = max(engineClockMs / 1000 + 2, 3)
            let timeoutSec = min(maxTime, 60)
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSec)) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                engine.onBestMove = nil
                engine.onInfo = nil
                engine.send("stop")
                cont.resume(returning: nil)
            }
        }

        if isPaused || hveShouldStop { return }

        let elapsed = Int(Date().timeIntervalSince(engineStart) * 1000)
        let inc = engineTC.incrementSeconds * 1000
        await MainActor.run {
            setEngineClock(max(0, engineClockMs - elapsed + inc))
        }

        await MainActor.run {
            if let move = bestMove, !move.isEmpty, move != "0000" {
                game.applyUCIMoveSync(move)
                moves.append(move)
                if showLEDs, let parsed = parseUCIMove(move) {
                    chessnut.lightSquares([parsed.from, parsed.to])
                }
                checkHumanGameEnd(deferToBoardExecution: true)
            } else {
                statusMessage = loc("status.timeoutLoss", engine.displayName)
                endGame(humanWon: true)
            }
        }
    }

    // MARK: - Fin de partie

    /// Vérifie si la partie est finie (mat, pat, matériel insuffisant). En mode
    /// échiquier physique, la fin peut être différée tant que le coup du moteur
    /// n'a pas été exécuté sur le plateau.
    private func checkHumanGameEnd(deferToBoardExecution: Bool = false) {
        let result: (humanWon: Bool?, status: String)?
        if game.isStalemate() {
            result = (nil, loc("status.stalemate"))
        } else if game.isInsufficientMaterial() {
            result = (nil, loc("status.insufficientMaterial"))
        } else if game.isKingInCheck(game.currentTurn) && !game.hasLegalMoves(game.currentTurn) {
            let won = game.currentTurn != game.humanColor
            let winnerName = game.currentTurn == .white ? blackName : whiteName
            result = (won, won ? loc("status.checkmateWin") : loc("status.checkmateLoss", winnerName))
        } else {
            result = nil
        }

        guard let result else {
            startTime = Date()
            statusMessage = loc("status.yourTurn")
            game.isEngineThinking = false
            // Alerte sonore + visuelle quand le roi du camp à jouer est en échec.
            updateCheckAlert()
            return
        }

        // Mat / pat / matériel insuffisant : son et alerte affichés.
        switch result.status {
        case loc("status.checkmateWin"), loc("status.checkmateLoss"):
            announce(result.status, sound: "Glass")
        case loc("status.stalemate"), loc("status.insufficientMaterial"):
            announce(result.status, sound: "Pop")
        default:
            announce(result.status, sound: "Pop")
        }

        // En mode échiquier physique, quand le coup du moteur termine la partie
        // (échec et mat, pat…), on attend que l'utilisateur l'exécute sur le
        // plateau avant de déclarer la fin et d'enchaîner la suivante.
        if deferToBoardExecution {
            pendingGameEndCheck = true
            game.isEngineThinking = false
            statusMessage = result.status
            return
        }

        pendingGameEndCheck = false
        cancelPendingGameEndStable()
        game.isEngineThinking = false
        statusMessage = result.status
        endGame(humanWon: result.humanWon)
    }

    /// Couleur effectivement jouée par l'humain lors de la partie `n`.
    /// Avec l'interversion des couleurs activée et plusieurs parties, la couleur
    /// alterne à chaque partie à partir de la couleur choisie.
    private func humanPlaysWhiteInGame(_ n: Int) -> Bool {
        guard swapColors, numberOfGames > 1 else { return humanPlaysWhite }
        return n.isMultiple(of: 2) ? !baseHumanPlaysWhite : baseHumanPlaysWhite
    }

    /// Termine la partie, enregistre le résultat, incrémente les scores et
    /// enchaîne la partie suivante (ou arrête la série).
    private func endGame(humanWon: Bool?) {
        game.isEngineThinking = false
        engine?.onBestMove = nil
        engine?.onInfo = nil

        let resultString: String
        if let won = humanWon {
            if won {
                humanWins += 1
                resultString = humanPlaysWhite ? "1-0" : "0-1"
            } else {
                engineWins += 1
                resultString = humanPlaysWhite ? "0-1" : "1-0"
            }
        } else {
            draws += 1
            resultString = "1/2-1/2"
        }

        let record = GameRecord(
            gameNumber: currentGameNumber,
            whiteName: whiteName,
            blackName: blackName,
            moves: moves,
            resultString: resultString
        )
        games.append(record)

        if currentGameNumber >= numberOfGames || hveShouldStop {
            // Fin de série : on prépare le message de résultat avant l'arrêt.
            let resultMsg: String
            if humanWins > engineWins {
                resultMsg = loc("status.seriesWin")
            } else if engineWins > humanWins {
                let engineName = humanPlaysWhite ? blackName : whiteName
                resultMsg = loc("status.seriesLoss", engineName)
            } else {
                resultMsg = loc("status.seriesDraw")
            }
            finishGameSession(resultMessage: loc("status.gameOver", resultMsg), startNextGame: false)
        } else {
            currentGameNumber += 1
            finishGameSession(resultMessage: nil, startNextGame: true)
        }
    }

    /// Transition entre deux parties d'une série : laisse le message de fin
    /// visible quelques secondes avant de continuer/arrêter (mode échiquier).
    private func finishGameSession(resultMessage: String?, startNextGame: Bool) {
        pendingSessionTransition = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !self.hveShouldStop else { return }
            self.pendingSessionTransition = false
            if startNextGame {
                self.startGameInternal()
            } else {
                self.stop()
                if let resultMessage {
                    self.statusMessage = resultMessage
                }
            }
        }
    }

    // MARK: - Communication moteur

    /// Attend la réponse `readyok`/`uciok` du moteur (avec un délai max de 10 s).
    private func waitForReady(_ engine: Engine) async {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            engine.onReady = {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                engine.onReady = nil
                continuation.resume()
            }

            engine.isready()

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                engine.onReady = nil
                continuation.resume()
            }
        }
    }

    /// Applique au moteur les options UCI (Hash, Threads et options personnalisées).
    private func applyOptions(to engine: Engine) {
        if engine.hashSize != 128 {
            engine.setOption("Hash", value: "\(engine.hashSize)")
        }
        if engine.threads != 1 {
            engine.setOption("Threads", value: "\(engine.threads)")
        }
        for opt in engine.options {
            if opt.type == "check" || opt.type == "spin" || opt.type == "combo" {
                engine.setOption(opt.name, value: opt.currentVal)
            }
        }
    }

    /// Extrait profondeur/score/temps/nœuds/nps/PV depuis une ligne `info` UCI.
    private func parseInfoLine(_ line: String) -> String {
        let parts = line.split(separator: " ")
        var depth = ""
        var score = ""
        var time = ""
        var nodes = ""
        var nps = ""
        var pvMoves: [String] = []
        var inPV = false

        var i = 0
        while i < parts.count {
            let p = String(parts[i])
            if inPV {
                pvMoves.append(p)
                i += 1
            } else if p == "depth" && i + 1 < parts.count {
                depth = String(parts[i + 1])
                i += 2
            } else if p == "score" && i + 1 < parts.count {
                let type = String(parts[i + 1])
                if type == "cp" && i + 2 < parts.count {
                    let val = Int(parts[i + 2]) ?? 0
                    score = val >= 0 ? "+\(val)" : "\(val)"
                    i += 3
                } else if type == "mate" && i + 2 < parts.count {
                    let val = Int(parts[i + 2]) ?? 0
                    score = "M\(val)"
                    i += 3
                } else {
                    i += 2
                }
            } else if p == "time" && i + 1 < parts.count {
                time = String(parts[i + 1])
                i += 2
            } else if p == "nodes" && i + 1 < parts.count {
                nodes = String(parts[i + 1])
                i += 2
            } else if p == "nps" && i + 1 < parts.count {
                nps = String(parts[i + 1])
                i += 2
            } else if p == "pv" {
                inPV = true
                i += 1
            } else {
                i += 1
            }
        }

        var result = ""
        if !depth.isEmpty { result += "d\(depth)" }
        if !score.isEmpty { result += " \(score)" }
        if !time.isEmpty { result += " \(time)ms" }
        if !nodes.isEmpty { result += " \(nodes)n" }
        if !nps.isEmpty { result += " \(nps)nps" }
        if !pvMoves.isEmpty { result += "  \(pvMoves.joined(separator: " "))" }
        return result
    }
}
