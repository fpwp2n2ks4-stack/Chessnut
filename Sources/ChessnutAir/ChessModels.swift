// ChessModels.swift
// Rôle du fichier : définir les modèles de données de base du jeu d'échecs —
// couleur et type des pièces, pièce, case (Position), pièce en déplacement et
// les utilitaires de conversion de coups au format UCI (notation échiquier).

import Foundation

/// Couleur d'une pièce ou d'un joueur.
enum PieceColor: CaseIterable {
    case white, black

    /// Retourne la couleur adverse.
    var opposite: PieceColor {
        self == .white ? .black : .white
    }
}

/// Type d'une pièce (Roi, Dame, Tour, Fou, Cavalier, Pion).
enum PieceType: CaseIterable {
    case king, queen, rook, bishop, knight, pawn

    /// Symbole Unicode du type, côté noir (pièces sombres).
    var symbol: String {
        switch self {
        case .king:   return "♚"
        case .queen:  return "♛"
        case .rook:   return "♜"
        case .bishop: return "♝"
        case .knight: return "♞"
        case .pawn:   return "♟"
        }
    }

    /// Symbole Unicode du type, côté blanc (pièces claires).
    var whiteSymbol: String {
        switch self {
        case .king:   return "♔"
        case .queen:  return "♕"
        case .rook:   return "♖"
        case .bishop: return "♗"
        case .knight: return "♘"
        case .pawn:   return "♙"
        }
    }
}

/// Une pièce d'échecs : son type, sa couleur et l'état « a déjà bougé »
/// (indispensable pour le roque, la prise en passant et la génération des coups).
struct ChessPiece: Identifiable, Equatable {
    let id = UUID()
    let type: PieceType
    let color: PieceColor
    var hasMoved: Bool = false

    /// Symbole Unicode de la pièce selon sa couleur.
    var symbol: String {
        color == .white ? type.whiteSymbol : type.symbol
    }
}

/// Case de l'échiquier, repérée par ligne (0 = rangée 8, arrière noires)
/// et colonne (0 = colonne a). `row`/`col` sont internes ; `notation` renvoie
/// la notation algébrique (ex. "e4").
struct Position: Hashable, Equatable {
    let row: Int
    let col: Int

    /// Vrai si la case est sur l'échiquier (0...7 dans les deux axes).
    var isValid: Bool {
        row >= 0 && row < 8 && col >= 0 && col < 8
    }

    /// Notation algébrique de la case, ex. "a1", "e4".
    var notation: String {
        let file = Character(UnicodeScalar(97 + col)!)
        return "\(file)\(row + 1)"
    }
}

/// Une pièce en cours de déplacement (utilisé pour l'animation).
struct MovingPiece: Equatable {
    let piece: ChessPiece
    let from: Position
    let to: Position
}

/// Erreur de décodage d'un coup UCI.
enum UCIParseError: Error {
    case invalidLength
    case invalidCharacter
}

/// Décode une case « a1 » → (row, col) à partir d'un tableau de caractères,
/// à l'offset donné. row = 7 correspond à la rangée 1 (retournement 8 - rang).
func parseUCISquare(_ chars: [Character], offset: Int) -> (row: Int, col: Int)? {
    guard chars.count > offset + 1 else { return nil }
    guard let fileVal = chars[offset].asciiValue,
          let rankVal = chars[offset + 1].asciiValue else { return nil }
    let col = Int(fileVal - UInt8(ascii: "a"))
    let row = 7 - Int(rankVal - UInt8(ascii: "1"))
    guard col >= 0, col < 8, row >= 0, row < 8 else { return nil }
    return (row, col)
}

/// Décode un coup UCI complet (« e2e4 », « e7e8q »…) en cases de départ,
/// d'arrivée et, éventuellement, la promotion choisie.
func parseUCIMove(_ move: String) -> (from: Position, to: Position, promotion: PieceType?)? {
    let chars = Array(move)
    guard chars.count >= 4 else { return nil }
    guard let from = parseUCISquare(chars, offset: 0),
          let to = parseUCISquare(chars, offset: 2) else { return nil }
    var promotion: PieceType? = nil
    if chars.count == 5 {
        switch chars[4] {
        case "q": promotion = .queen
        case "r": promotion = .rook
        case "b": promotion = .bishop
        case "n": promotion = .knight
        default: break
        }
    }
    return (Position(row: from.row, col: from.col), Position(row: to.row, col: to.col), promotion)
}
