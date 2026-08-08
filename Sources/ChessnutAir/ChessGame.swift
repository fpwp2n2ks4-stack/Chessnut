// ChessGame.swift
// Rôle du fichier : la logique centrale d'une partie d'échecs — état du
// plateau, génération des coups légaux, détection échec/pat/mat, notation
// FEN/SAN et synchronisation avec l'échiquier physique Bluetooth (Chessnut).

import Foundation

/// Moteur de jeu d'échecs (ObservableObject) : contient le plateau, le tour,
/// la sélection, l'historique et toutes les règles. Il est partagé par la vue
/// échiquier et l'orchestrateur des parties (PlayController).
class ChessGame: ObservableObject {
    @Published var board: [[ChessPiece?]]
    @Published var selectedPosition: Position?
    @Published var currentTurn: PieceColor = .white
    @Published var validMoves: [Position] = []
    @Published var moveHistory: [String] = []
    @Published var movingPiece: MovingPiece?
    @Published var isTournamentActive: Bool = false
    @Published var isHumanVsEngine = false
    @Published var isEngineThinking = false
    @Published var isPaused = false
    @Published var boardFlipped = false
    @Published var isPhysicalBoard = false
    var humanColor: PieceColor = .white
    var onHumanMove: ((String) -> Void)?

    /// Dernier coup joué (origine → destination), pour la prise en passant
    /// et la génération du FEN.
    var lastMove: (from: Position, to: Position)?
    private var generation: Int = 0

    /// Crée une partie avec le plateau initial standard.
    init() {
        board = Self.createInitialBoard()
    }

    /// Construit le plateau de départ : rangées 0/1 = noires, rangées 6/7 = blanches.
    static func createInitialBoard() -> [[ChessPiece?]] {
        var board = Array(repeating: Array(repeating: nil as ChessPiece?, count: 8), count: 8)

        let backRow: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]

        for col in 0..<8 {
            board[0][col] = ChessPiece(type: backRow[col], color: .black)
            board[1][col] = ChessPiece(type: .pawn, color: .black)
            board[6][col] = ChessPiece(type: .pawn, color: .white)
            board[7][col] = ChessPiece(type: backRow[col], color: .white)
        }

        return board
    }

    /// Réinitialise complètement la partie (position de départ, historique, sélection).
    func resetGame() {
        generation += 1
        board = Self.createInitialBoard()
        selectedPosition = nil
        currentTurn = .white
        validMoves = []
        moveHistory = []
        lastMove = nil
        movingPiece = nil
        isEngineThinking = false
    }

    /// Convertit l'état courant en chaîne FEN complète (placement, tour,
    /// droits de roque, prise en passant, horloges de demi-coups et numéro).
    func toFEN(halfmoveClock: Int = 0, fullmoveNumber: Int = 1) -> String {
        var fenParts: [String] = []

        for row in 0..<8 {
            var empty = 0
            var rowStr = ""
            for col in 0..<8 {
                if let piece = board[row][col] {
                    if empty > 0 { rowStr += "\(empty)"; empty = 0 }
                    let ch: Character
                    switch piece.type {
                    case .king:   ch = "K"
                    case .queen:  ch = "Q"
                    case .rook:   ch = "R"
                    case .bishop: ch = "B"
                    case .knight: ch = "N"
                    case .pawn:   ch = "P"
                    }
                    rowStr += piece.color == .white ? String(ch) : String(ch).lowercased()
                } else {
                    empty += 1
                }
            }
            if empty > 0 { rowStr += "\(empty)" }
            fenParts.append(rowStr)
        }

        let turnStr = currentTurn == .white ? "w" : "b"

        var castling = ""
        if let bk = board[0][4], bk.type == .king, bk.color == .black, !bk.hasMoved {
            if let rook = board[0][7], rook.type == .rook, rook.color == .black, !rook.hasMoved { castling += "k" }
            if let rook = board[0][0], rook.type == .rook, rook.color == .black, !rook.hasMoved { castling += "q" }
        }
        if let wk = board[7][4], wk.type == .king, wk.color == .white, !wk.hasMoved {
            if let rook = board[7][7], rook.type == .rook, rook.color == .white, !rook.hasMoved { castling += "K" }
            if let rook = board[7][0], rook.type == .rook, rook.color == .white, !rook.hasMoved { castling += "Q" }
        }
        if castling.isEmpty { castling = "-" }

        var ep = "-"
        if let last = lastMove,
           let piece = board[last.to.row][last.to.col],
           piece.type == .pawn,
           abs(last.to.row - last.from.row) == 2 {
            let epRow = (last.from.row + last.to.row) / 2
            ep = "\(Character(UnicodeScalar(97 + last.to.col)!))\(8 - epRow)"
        }

        return "\(fenParts.joined(separator: "/")) \(turnStr) \(castling) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Charge une position depuis un FEN (au moins la partie « placement »).
    func fromFEN(_ fen: String) {
        let parts = fen.split(separator: " ", maxSplits: 5).map(String.init)
        guard parts.count >= 1 else { return }
        let placement = parts[0]

        var newBoard = Array(repeating: Array(repeating: nil as ChessPiece?, count: 8), count: 8)
        let rows = placement.split(separator: "/")
        for (ri, rowStr) in rows.enumerated() {
            guard ri < 8 else { break }
            var col = 0
            for ch in rowStr {
                guard col < 8 else { break }
                if let num = ch.wholeNumberValue {
                    col += num
                } else {
                    let color: PieceColor = ch.isUppercase ? .white : .black
                    let type: PieceType
                    switch ch.lowercased() {
                    case "k": type = .king
                    case "q": type = .queen
                    case "r": type = .rook
                    case "b": type = .bishop
                    case "n": type = .knight
                    case "p": type = .pawn
                    default: type = .pawn
                    }
                    newBoard[ri][col] = ChessPiece(type: type, color: color, hasMoved: true)
                    col += 1
                }
            }
        }

        board = newBoard

        if parts.count >= 2 {
            currentTurn = parts[1] == "w" ? .white : .black
        }

        selectedPosition = nil
        validMoves = []
        moveHistory = []
        lastMove = nil
        movingPiece = nil
        isTournamentActive = false
        isHumanVsEngine = false
        isEngineThinking = false
        isPaused = false
        boardFlipped = false
        humanColor = .white
        onHumanMove = nil
    }

    /// Retourne la pièce présente sur une case (nil si vide ou hors plateau).
    func pieceAt(_ pos: Position) -> ChessPiece? {
        guard pos.isValid else { return nil }
        return board[pos.row][pos.col]
    }

    // MARK: - Plateau physique (échiquier Bluetooth)

    /// Placement FEN seul (la 1ʳᵉ partie du FEN), tel que renvoyé par l'échiquier.
    func placementString() -> String {
        String(toFEN().split(separator: " ")[0])
    }

    /// Synchronise l'état interne avec le placement renvoyé par l'échiquier.
    func syncPlacement(_ placement: String) {
        board = Self.board(fromPlacement: placement)
        selectedPosition = nil
        validMoves = []
        movingPiece = nil
    }

    /// Cases d'origine et de destination candidates pour une couleur entre deux
    /// placements (cases dont la pièce a changé).
    static func moveCandidates(between prevPlacement: String, and currPlacement: String, color: PieceColor) -> (from: [Position], to: [Position]) {
        let prev = board(fromPlacement: prevPlacement)
        let curr = board(fromPlacement: currPlacement)
        var froms: [Position] = []
        var tos: [Position] = []
        for r in 0..<8 {
            for c in 0..<8 {
                let prevPiece = prev[r][c]
                let currPiece = curr[r][c]
                let samePiece = prevPiece.map { prev in
                    currPiece.map { $0.type == prev.type && $0.color == prev.color } ?? false
                } ?? false
                if let piece = prevPiece, piece.color == color, !samePiece {
                    froms.append(Position(row: r, col: c))
                }
                if let piece = currPiece, piece.color == color, !samePiece {
                    tos.append(Position(row: r, col: c))
                }
            }
        }
        return (froms, tos)
    }

    /// Détecte le coup UCI joué entre deux placements successifs du plateau physique.
    func detectMove(previousPlacement: String, currentPlacement: String) -> String? {
        let color = currentTurn
        let candidates = Self.moveCandidates(between: previousPlacement, and: currentPlacement, color: color)
        let fromCandidates = candidates.from
        let toCandidates = candidates.to
        let prev = Self.board(fromPlacement: previousPlacement)

        for from in fromCandidates {
            guard let piece = prev[from.row][from.col], piece.color == color else { continue }
            for to in toCandidates {
                if Self.placementString(from: simulateMove(on: prev, from: from, to: to, promotion: nil)) == currentPlacement {
                    return uciSquaresString(from: from, to: to)
                }
                if piece.type == .pawn && (to.row == 0 || to.row == 7) {
                    for promo in [PieceType.rook, .knight, .bishop] {
                        if Self.placementString(from: simulateMove(on: prev, from: from, to: to, promotion: promo)) == currentPlacement {
                            let promoChar: String
                            switch promo {
                            case .rook: promoChar = "r"
                            case .knight: promoChar = "n"
                            default: promoChar = "b"
                            }
                            return uciSquaresString(from: from, to: to) + promoChar
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Placement FEN d'un plateau, insensible à `hasMoved` (utile pour comparer avec un placement d'échiquier).
    static func placementString(from board: [[ChessPiece?]]) -> String {
        func fenLetter(_ type: PieceType) -> String {
            switch type {
            case .king:   return "K"
            case .queen:  return "Q"
            case .rook:   return "R"
            case .bishop: return "B"
            case .knight: return "N"
            case .pawn:   return "P"
            }
        }
        var rows: [String] = []
        for row in 0..<8 {
            var empty = 0
            var rowStr = ""
            for col in 0..<8 {
                if let piece = board[row][col] {
                    if empty > 0 { rowStr += "\(empty)"; empty = 0 }
                    let letter = fenLetter(piece.type)
                    rowStr += piece.color == .white ? letter : letter.lowercased()
                } else {
                    empty += 1
                }
            }
            if empty > 0 { rowStr += "\(empty)" }
            rows.append(rowStr)
        }
        return rows.joined(separator: "/")
    }

    /// Convertit deux cases en chaîne UCI de base (« e2e4 »), sans la promotion.
    private func uciSquaresString(from: Position, to: Position) -> String {
        let fromFile = Character(UnicodeScalar(97 + from.col)!)
        let fromRank = 8 - from.row
        let toFile = Character(UnicodeScalar(97 + to.col)!)
        let toRank = 8 - to.row
        return "\(fromFile)\(fromRank)\(toFile)\(toRank)"
    }

    /// Construit un plateau depuis un placement FEN (pièces posées sans état « a bougé »).
    static func board(fromPlacement placement: String) -> [[ChessPiece?]] {
        var newBoard = Array(repeating: Array(repeating: nil as ChessPiece?, count: 8), count: 8)
        let rows = placement.split(separator: "/")
        for (ri, rowStr) in rows.enumerated() {
            guard ri < 8 else { break }
            var col = 0
            for ch in rowStr {
                guard col < 8 else { break }
                if let num = ch.wholeNumberValue {
                    col += num
                } else {
                    let color: PieceColor = ch.isUppercase ? .white : .black
                    let type: PieceType
                    switch ch.lowercased() {
                    case "k": type = .king
                    case "q": type = .queen
                    case "r": type = .rook
                    case "b": type = .bishop
                    case "n": type = .knight
                    default: type = .pawn
                    }
                    newBoard[ri][col] = ChessPiece(type: type, color: color)
                    col += 1
                }
            }
        }
        return newBoard
    }

    /// Simule un coup (y compris prise en passant, roque et promotion) sur une
    /// copie du plateau, pour comparer le résultat avec un placement d'échiquier.
    private func simulateMove(on sourceBoard: [[ChessPiece?]], from: Position, to: Position, promotion: PieceType?) -> [[ChessPiece?]] {
        guard var piece = sourceBoard[from.row][from.col] else { return sourceBoard }
        var newBoard = sourceBoard

        if piece.type == .pawn, from.col != to.col, newBoard[to.row][to.col] == nil {
            newBoard[from.row][to.col] = nil
            piece.hasMoved = true
            newBoard[to.row][to.col] = piece
            newBoard[from.row][from.col] = nil
        } else if piece.type == .king, to.row == from.row, to.col - from.col == 2, var rook = newBoard[from.row][7] {
            piece.hasMoved = true
            rook.hasMoved = true
            newBoard[from.row][from.col] = nil
            newBoard[from.row][6] = piece
            newBoard[from.row][7] = nil
            newBoard[from.row][5] = rook
        } else if piece.type == .king, to.row == from.row, from.col - to.col == 2, var rook = newBoard[from.row][0] {
            piece.hasMoved = true
            rook.hasMoved = true
            newBoard[from.row][from.col] = nil
            newBoard[from.row][2] = piece
            newBoard[from.row][0] = nil
            newBoard[from.row][3] = rook
        } else {
            piece.hasMoved = true
            newBoard[to.row][to.col] = piece
            newBoard[from.row][from.col] = nil
            if piece.type == .pawn && (to.row == 0 || to.row == 7) {
                newBoard[to.row][to.col] = ChessPiece(type: promotion ?? .queen, color: piece.color, hasMoved: true)
            }
        }
        return newBoard
    }

    /// Pièce à afficher sur une case : masquée si elle est en cours d'animation.
    func pieceAtForDisplay(_ pos: Position) -> ChessPiece? {
        if let mp = movingPiece, mp.from == pos || mp.to == pos {
            return nil
        }
        return pieceAt(pos)
    }

    /// Gère un clic sur une case : sélectionne une pièce ou joue un coup légal.
    /// Bloqué pendant un tour moteur, une pause ou en mode plateau physique
    /// (les coups viennent alors de l'échiquier Bluetooth).
    func selectPosition(_ pos: Position) {
        guard !isTournamentActive, !isEngineThinking, !isPaused, !isPhysicalBoard, pos.isValid else { return }
        guard !isHumanVsEngine || currentTurn == humanColor else { return }

        if let selected = selectedPosition {
            if validMoves.contains(pos) {
                let piece = board[selected.row][selected.col]
                movePiece(from: selected, to: pos)
                selectedPosition = nil
                validMoves = []

                if isHumanVsEngine, let piece, currentTurn != humanColor {
                    let uci = uciString(from: selected, to: pos, piece: piece)
                    onHumanMove?(uci)
                }
            } else if let piece = pieceAt(pos), piece.color == currentTurn {
                selectedPosition = pos
                validMoves = calculateValidMoves(for: pos)
            } else {
                selectedPosition = nil
                validMoves = []
            }
        } else if let piece = pieceAt(pos), piece.color == currentTurn {
            selectedPosition = pos
            validMoves = calculateValidMoves(for: pos)
        }
    }

    /// Construit la chaîne UCI d'un coup joué par l'humain (promotion en Dame par défaut).
    private func uciString(from: Position, to: Position, piece: ChessPiece) -> String {
        let fromFile = Character(UnicodeScalar(97 + from.col)!)
        let fromRank = 8 - from.row
        let toFile = Character(UnicodeScalar(97 + to.col)!)
        let toRank = 8 - to.row
        var uci = "\(fromFile)\(fromRank)\(toFile)\(toRank)"
        if piece.type == .pawn && (to.row == 0 || to.row == 7) {
            uci += "q"
        }
        return uci
    }

    /// Applique un coup UCI avec animation : la pièce glisse pendant ~0,15 s,
    /// puis le coup est joué et `completion` est appelée.
    func applyUCIMove(_ move: String, completion: @escaping () -> Void) {
        guard let parsed = parseUCIMove(move) else { completion(); return }

        let from = parsed.from
        let to = parsed.to
        let promotion = parsed.promotion

        guard let piece = pieceAt(from) else { completion(); return }

        let gen = generation
        movingPiece = MovingPiece(piece: piece, from: from, to: to)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.generation == gen else { completion(); return }
            self.movePiece(from: from, to: to, promotion: promotion)
            self.movingPiece = nil
            completion()
        }
    }

    /// Applique un coup UCI immédiatement, sans animation.
    func applyUCIMoveSync(_ move: String) {
        guard let parsed = parseUCIMove(move) else { return }
        movePiece(from: parsed.from, to: parsed.to, promotion: parsed.promotion)
    }

    /// Joue un coup sur le plateau (prise en passant, roque, promotion gérés),
    /// met à jour l'historique, le dernier coup et le trait.
    func movePiece(from: Position, to: Position, promotion: PieceType? = nil) {
        guard var piece = board[from.row][from.col] else { return }

        var newBoard = board

        if piece.type == .pawn, let last = lastMove,
           last.from.col == to.col,
           last.to.row - last.from.row == (piece.color == .white ? 2 : -2),
           from.row == last.to.row,
           abs(to.col - from.col) == 1,
           pieceAt(to) == nil {
            newBoard[last.to.row][last.to.col] = nil
            piece.hasMoved = true
            newBoard[to.row][to.col] = piece
            newBoard[from.row][from.col] = nil
            moveHistory.append("\(piece.symbol) \(from.notation) → \(to.notation) e.p.")
        } else if piece.type == .king, to.col - from.col == 2, var rook = newBoard[from.row][7] {
            piece.hasMoved = true
            newBoard[from.row][from.col] = nil
            newBoard[from.row][6] = piece
            rook.hasMoved = true
            newBoard[from.row][7] = nil
            newBoard[from.row][5] = rook
            moveHistory.append("O-O")
        } else if piece.type == .king, from.col - to.col == 2, var rook = newBoard[from.row][0] {
            piece.hasMoved = true
            newBoard[from.row][from.col] = nil
            newBoard[from.row][2] = piece
            rook.hasMoved = true
            newBoard[from.row][0] = nil
            newBoard[from.row][3] = rook
            moveHistory.append("O-O-O")
        } else {
            piece.hasMoved = true
            newBoard[to.row][to.col] = piece
            newBoard[from.row][from.col] = nil

            if piece.type == .pawn && (to.row == 0 || to.row == 7) {
                let promoType = promotion ?? .queen
                newBoard[to.row][to.col] = ChessPiece(type: promoType, color: piece.color, hasMoved: true)
                moveHistory.append("\(piece.symbol) \(from.notation) → \(to.notation) = \(promoType.whiteSymbol)")
            } else {
                moveHistory.append("\(piece.symbol) \(from.notation) → \(to.notation)")
            }
        }

        board = newBoard
        lastMove = (from, to)
        currentTurn = currentTurn.opposite
    }

    /// Calcule tous les coups légaux d'une pièce (coups pseudo-légaux filtrés
    /// par ceux qui ne laissent pas son roi en échec).
    func calculateValidMoves(for pos: Position) -> [Position] {
        guard let piece = pieceAt(pos) else { return [] }

        let pseudoMoves: [Position]
        switch piece.type {
        case .pawn:   pseudoMoves = validPawnMoves(for: pos, color: piece.color)
        case .rook:   pseudoMoves = slidingMoves(for: pos, directions: [(-1,0),(1,0),(0,-1),(0,1)], color: piece.color)
        case .bishop: pseudoMoves = slidingMoves(for: pos, directions: [(-1,-1),(-1,1),(1,-1),(1,1)], color: piece.color)
        case .queen:  pseudoMoves = slidingMoves(for: pos, directions: [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)], color: piece.color)
        case .knight: pseudoMoves = knightMoves(for: pos, color: piece.color)
        case .king:   pseudoMoves = kingMoves(for: pos, color: piece.color)
        }

        return pseudoMoves.filter { !moveLeavesKingInCheck(from: pos, to: $0, color: piece.color) }
    }

    /// Coups pseudo-légaux du pion : avance d'une/deux cases, captures
    /// diagonales et prise en passant.
    private func validPawnMoves(for pos: Position, color: PieceColor) -> [Position] {
        var moves: [Position] = []
        let direction = color == .white ? -1 : 1
        let startRow = color == .white ? 6 : 1

        let oneForward = Position(row: pos.row + direction, col: pos.col)
        if oneForward.isValid && pieceAt(oneForward) == nil {
            moves.append(oneForward)

            let twoForward = Position(row: pos.row + 2 * direction, col: pos.col)
            if pos.row == startRow && twoForward.isValid && pieceAt(twoForward) == nil {
                moves.append(twoForward)
            }
        }

        for dc in [-1, 1] {
            let capture = Position(row: pos.row + direction, col: pos.col + dc)
            if capture.isValid, let target = pieceAt(capture), target.color != color {
                moves.append(capture)
            }
        }

        if let last = lastMove, let lastPiece = board[last.to.row][last.to.col],
           lastPiece.type == .pawn,
           lastPiece.color != color,
           last.from.row == (color == .white ? 1 : 6),
           last.to.row == pos.row,
           abs(last.to.row - last.from.row) == 2 {
            for dc in [-1, 1] {
                let epTarget = Position(row: pos.row + direction, col: last.to.col)
                if epTarget.col == pos.col + dc && epTarget.isValid {
                    moves.append(epTarget)
                }
            }
        }

        return moves
    }

    /// Coups d'une pièce à longue portée (tour, fou, dame) le long des
    /// directions données, en s'arrêtant au premier obstacle.
    private func slidingMoves(for pos: Position, directions: [(Int, Int)], color: PieceColor) -> [Position] {
        var moves: [Position] = []
        for (dr, dc) in directions {
            var r = pos.row + dr
            var c = pos.col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                let target = Position(row: r, col: c)
                if let piece = pieceAt(target) {
                    if piece.color != color { moves.append(target) }
                    break
                }
                moves.append(target)
                r += dr
                c += dc
            }
        }
        return moves
    }

    /// Coups possibles du cavalier (8 sauts en « L »).
    private func knightMoves(for pos: Position, color: PieceColor) -> [Position] {
        let offsets = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)]
        return offsets.compactMap { dr, dc in
            let target = Position(row: pos.row + dr, col: pos.col + dc)
            guard target.isValid else { return nil }
            if let piece = pieceAt(target), piece.color == color { return nil }
            return target
        }
    }

    /// Coups possibles du roi (8 déplacements adjacents) et roque si les
    /// conditions sont réunies (roi et tour n'ont pas bougé, cases libres).
    private func kingMoves(for pos: Position, color: PieceColor) -> [Position] {
        var moves: [Position] = []
        let offsets = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

        for (dr, dc) in offsets {
            let target = Position(row: pos.row + dr, col: pos.col + dc)
            guard target.isValid else { continue }
            if let piece = pieceAt(target), piece.color == color { continue }
            moves.append(target)
        }

        if let king = pieceAt(pos), !king.hasMoved {
            let backRow = color == .white ? 7 : 0

            if pos.row == backRow && pos.col == 4 {
                if let rook = pieceAt(Position(row: backRow, col: 7)), rook.type == .rook, !rook.hasMoved {
                    if pieceAt(Position(row: backRow, col: 5)) == nil,
                       pieceAt(Position(row: backRow, col: 6)) == nil {
                        moves.append(Position(row: backRow, col: 6))
                    }
                }

                if let rook = pieceAt(Position(row: backRow, col: 0)), rook.type == .rook, !rook.hasMoved {
                    if pieceAt(Position(row: backRow, col: 1)) == nil,
                       pieceAt(Position(row: backRow, col: 2)) == nil,
                       pieceAt(Position(row: backRow, col: 3)) == nil {
                        moves.append(Position(row: backRow, col: 2))
                    }
                }
            }
        }

        return moves
    }

    // MARK: - Attack / Check Detection

    /// Vérifie si une case est attaquée par une pièce de la couleur donnée
    /// (sur l'état interne ou un plateau fourni en paramètre).
    func isSquareAttacked(_ pos: Position, by color: PieceColor, on boardState: [[ChessPiece?]]? = nil) -> Bool {
        let b = boardState ?? board
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = b[r][c], piece.color == color else { continue }
                let from = Position(row: r, col: c)
                switch piece.type {
                case .pawn:
                    let dir = color == .white ? -1 : 1
                    for dc in [-1, 1] {
                        if from.row + dir == pos.row && from.col + dc == pos.col { return true }
                    }
                case .knight:
                    let offsets = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)]
                    for (dr, dc) in offsets {
                        if from.row + dr == pos.row && from.col + dc == pos.col { return true }
                    }
                case .bishop:
                    if slidingAttack(from: from, to: pos, directions: [(-1,-1),(-1,1),(1,-1),(1,1)], boardState: b) { return true }
                case .rook:
                    if slidingAttack(from: from, to: pos, directions: [(-1,0),(1,0),(0,-1),(0,1)], boardState: b) { return true }
                case .queen:
                    if slidingAttack(from: from, to: pos, directions: [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)], boardState: b) { return true }
                case .king:
                    let dr = pos.row - from.row
                    let dc = pos.col - from.col
                    if abs(dr) <= 1 && abs(dc) <= 1 && (dr != 0 || dc != 0) { return true }
                }
            }
        }
        return false
    }

    /// Détecte si une pièce à longue portée (fou/tour/dame) attaque `to`
    /// depuis `from` sur la ligne droite définie par `directions`.
    private func slidingAttack(from: Position, to: Position, directions: [(Int, Int)], boardState: [[ChessPiece?]]? = nil) -> Bool {
        let b = boardState ?? board
        for (dr, dc) in directions {
            var r = from.row + dr
            var c = from.col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if r == to.row && c == to.col { return true }
                if b[r][c] != nil { break }
                r += dr
                c += dc
            }
        }
        return false
    }

    /// Indique si le roi de la couleur donnée est en échec.
    func isKingInCheck(_ color: PieceColor, on boardState: [[ChessPiece?]]? = nil) -> Bool {
        let b = boardState ?? board
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = b[r][c], piece.type == .king, piece.color == color {
                    return isSquareAttacked(Position(row: r, col: c), by: color.opposite, on: b)
                }
            }
        }
        return false
    }

    /// Vrai si la couleur a au moins un coup légal (pour détecter mat/pat).
    func hasLegalMoves(_ color: PieceColor) -> Bool {
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = board[r][c], piece.color == color else { continue }
                let from = Position(row: r, col: c)
                for target in calculateValidMoves(for: from) {
                    if !moveLeavesKingInCheck(from: from, to: target, color: color) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Vrai si jouer `from → to` laisse le roi de `color` en échec.
    func moveLeavesKingInCheck(from: Position, to: Position, color: PieceColor) -> Bool {
        guard let piece = board[from.row][from.col] else { return true }

        var testBoard = board
        if piece.type == .pawn, from.col != to.col, testBoard[to.row][to.col] == nil {
            testBoard[from.row][to.col] = nil
        }
        testBoard[to.row][to.col] = piece
        testBoard[from.row][from.col] = nil

        if piece.type == .king {
            return isSquareAttacked(to, by: color.opposite, on: testBoard)
        } else {
            return isKingInCheck(color, on: testBoard)
        }
    }

    // MARK: - Draw Detection

    /// Vrai si la position est un match nul par matériel insuffisant.
    func isInsufficientMaterial() -> Bool {
        var whitePieces: [PieceType] = []
        var blackPieces: [PieceType] = []
        var whiteBishops: [Position] = []
        var blackBishops: [Position] = []

        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c] {
                    if piece.color == .white {
                        whitePieces.append(piece.type)
                        if piece.type == .bishop { whiteBishops.append(Position(row: r, col: c)) }
                    } else {
                        blackPieces.append(piece.type)
                        if piece.type == .bishop { blackBishops.append(Position(row: r, col: c)) }
                    }
                }
            }
        }

        let wSet = Set(whitePieces)
        let bSet = Set(blackPieces)

        if wSet == [.king] && bSet == [.king] { return true }
        if wSet == [.king] && bSet == [.king, .bishop] { return true }
        if bSet == [.king] && wSet == [.king, .bishop] { return true }
        if wSet == [.king] && bSet == [.king, .knight] { return true }
        if bSet == [.king] && wSet == [.king, .knight] { return true }

        if wSet == [.king, .bishop] && bSet == [.king, .bishop],
           whiteBishops.count == 1, blackBishops.count == 1 {
            let wbSquare = (whiteBishops[0].row + whiteBishops[0].col) % 2
            let bbSquare = (blackBishops[0].row + blackBishops[0].col) % 2
            if wbSquare == bbSquare { return true }
        }

        return false
    }

    /// Vrai si le joueur au trait n'est pas en échec mais n'a aucun coup légal (pat).
    func isStalemate() -> Bool {
        return !isKingInCheck(currentTurn) && !hasLegalMoves(currentTurn)
    }

    // MARK: - SAN Conversion

    /// Convertit un coup UCI en notation algébrique (SAN).
    func moveToSAN(uci: String) -> String {
        guard let parsed = parseUCIMove(uci) else { return uci }

        let from = parsed.from
        let to = parsed.to

        guard let piece = pieceAt(from) else { return uci }

        let isCapture = pieceAt(to) != nil || (piece.type == .pawn && from.col != to.col && pieceAt(to) == nil)

        var san = ""

        if piece.type == .king {
            if to.col - from.col == 2 { return "O-O" }
            if from.col - to.col == 2 { return "O-O-O" }
            san = "K"
        } else if piece.type == .pawn {
            if isCapture {
                san = "\(Character(UnicodeScalar(97 + from.col)!))"
            }
        } else {
            let letter: String
            switch piece.type {
            case .queen:  letter = "Q"
            case .rook:   letter = "R"
            case .bishop: letter = "B"
            case .knight: letter = "N"
            default:      letter = ""
            }
            san = letter

            for r in 0..<8 {
                for c in 0..<8 {
                    guard r != from.row || c != from.col else { continue }
                    guard let other = board[r][c], other.type == piece.type, other.color == piece.color else { continue }
                    let otherFrom = Position(row: r, col: c)
                    let otherMoves = calculateValidMoves(for: otherFrom)
                    if otherMoves.contains(to) {
                        if c != from.col {
                            san += "\(Character(UnicodeScalar(97 + from.col)!))"
                        } else if r != from.row {
                            san += "\(8 - from.row)"
                        } else {
                            san += "\(Character(UnicodeScalar(97 + from.col)!))\(8 - from.row)"
                        }
                        break
                    }
                }
            }
        }

        if isCapture { san += "x" }

        san += "\(Character(UnicodeScalar(97 + to.col)!))\(8 - to.row)"

        if piece.type == .pawn && (to.row == 0 || to.row == 7) {
            let promoChar = String(Array(uci).count == 5 ? Array(uci)[4] : "Q").uppercased()
            san += "=\(promoChar)"
        }

        var testBoard = board
        testBoard[to.row][to.col] = piece
        testBoard[from.row][from.col] = nil
        let opponentColor = piece.color.opposite
        let givesCheck = isKingInCheck(opponentColor, on: testBoard)

        if givesCheck {
            if !hasLegalMoves(opponentColor) {
                san += "#"
            } else {
                san += "+"
            }
        }

        return san
    }
}
