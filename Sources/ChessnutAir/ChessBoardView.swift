// ChessBoardView.swift
// Rôle du fichier : l'interface SwiftUI de l'échiquier — rendu des cases et
// des pièces (sprite sheet incluse), sélection/coups, animation des pièces qui
// bougent, flip du plateau et bandeau d'analyse en direct.

import SwiftUI
import AppKit
import Combine

/// Gestionnaire de la sprite sheet des pièces : découpe l'image incluse
/// (6 colonnes × 2 rangées) et fournit l'image d'une pièce donnée.
final class PieceSpriteSheet {
    static let shared = PieceSpriteSheet()

    private var sheetImage: NSImage?
    private let columns = 6
    private let rows = 2

    private init() {
        sheetImage = Bundle.module.image(forResource: "Cburnett")
    }

    /// Retourne l'image d'une pièce (découpée dans la sprite sheet).
    func image(for piece: ChessPiece) -> NSImage? {
        guard let sheet = sheetImage else { return nil }

        let col: Int
        switch piece.type {
        case .rook:   col = 0
        case .knight: col = 1
        case .bishop: col = 2
        case .queen:  col = 3
        case .king:   col = 4
        case .pawn:   col = 5
        }

        let row = piece.color == .white ? 1 : 0

        guard let tiff = sheet.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let cellW = bitmap.pixelsWide / columns
        let cellH = bitmap.pixelsHigh / rows
        let x = col * cellW
        let yCG = bitmap.pixelsHigh - (row + 1) * cellH

        guard let cgImage = bitmap.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: NSRect(x: x, y: yCG, width: cellW, height: cellH)) else { return nil }

        return NSImage(cgImage: cropped, size: NSSize(width: cellW, height: cellH))
    }
}

/// Vue principale de l'échiquier : dessine les 64 cases, les pièces, la
/// sélection, les coups légaux, l'animation et le bandeau d'analyse.
struct ChessBoardView: View {
    @ObservedObject var game: ChessGame
    @ObservedObject var play: PlayController
    var onSelect: ((Position) -> Void)?

    init(game: ChessGame, play: PlayController, onSelect: ((Position) -> Void)? = nil) {
        self.game = game
        self.play = play
        self.onSelect = onSelect
    }

    /// Vrai si le bandeau d'analyse est affiché (partie en cours).
    private var showAnalysis: Bool {
        (play.showAnalysis && play.isRunning) || !play.checkAlert.isEmpty
    }

    /// Temps restant formaté (m:ss ou ss) pour le joueur donné.
    private func timeText(_ ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        let min = totalSec / 60
        let sec = totalSec % 60
        if min > 0 { return "\(min):\(String(format: "%02d", sec))" }
        return "\(sec)s"
    }

    /// Lignes à dessiner (inversées si le plateau est retourné).
    private var rows: [Int] {
        game.boardFlipped ? (0..<8).reversed() : Array(0..<8)
    }

    /// Colonnes à dessiner (inversées si le plateau est retourné).
    private var cols: [Int] {
        game.boardFlipped ? (0..<8).reversed() : Array(0..<8)
    }

    /// Corps de la vue : grille de cases, animation, bandeau d'analyse.
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let margin = max(8, side * 0.03)
            let bandHeight: CGFloat = 46
            let showBand = showAnalysis
            let boardSize = showBand ? side - margin * 2 - bandHeight : side - margin * 2
            let squareSize = boardSize / 8
            let boardY = showBand ? margin + boardSize / 2 : side / 2

            MenuBarMaterial()
                .ignoresSafeArea()

            ZStack {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(cols, id: \.self) { col in
                                let pos = Position(row: row, col: col)
                                SquareView(
                                    pos: pos,
                                    piece: game.pieceAtForDisplay(pos),
                                    isSelected: game.selectedPosition == pos,
                                    isValidMove: game.validMoves.contains(pos),
                                    squareSize: squareSize,
                                    onTap: { onSelect?(pos) ?? game.selectPosition(pos) }
                                )
                            }
                        }
                    }
                }
                .frame(width: boardSize, height: boardSize)

                if let mp = game.movingPiece {
                    MovingPieceView(piece: mp.piece, from: mp.from, to: mp.to, squareSize: squareSize)
                        .id(mp.piece.id)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: boardSize, height: boardSize)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(boardBorderColor, lineWidth: 3)
            )
            .position(x: geo.size.width / 2, y: boardY)

            if showBand {
                let analysis = AnalysisInfo.parse(play.analysis)
                VStack(alignment: .leading, spacing: 2) {
                    if !play.checkAlert.isEmpty {
                        Text(play.checkAlert)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(alertColor))
                    }
                    HStack(spacing: 10) {
                        Text("♔ \(timeText(play.whiteTimeMs))")
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Text("♚ \(timeText(play.blackTimeMs))")
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Spacer()
                        if !analysis.depth.isEmpty {
                            Text("d\(analysis.depth)")
                        }
                        if !analysis.score.isEmpty {
                            Text("score \(analysis.score)")
                        }
                        if !analysis.nodes.isEmpty {
                            Text("\(analysis.nodes)n")
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
                    if !analysis.pv.isEmpty {
                        Text(analysis.pv)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(width: boardSize, alignment: .leading)
                .background(analysisBackground)
                .position(x: geo.size.width / 2, y: side - bandHeight / 2)
                .onReceive(play.$analysis) { _ in }
            }
        }
    }

    private var boardBorderColor: Color {
        Color(hex: "#3D5A80")
    }

    private var analysisBackground: Color {
        Color(hex: "#1B2A3A")
    }

    /// Couleur du bandeau d'alerte : rouge pour échec/mat, orange pour coup interdit.
    private var alertColor: Color {
        let a = play.checkAlert
        if a == loc("status.check")
            || a == loc("status.checkmateWin")
            || a == loc("status.checkmateLoss") {
            return Color(hex: "#D64545")
        }
        return Color(hex: "#E09B3D")
    }
}

/// Matériau de fond du menu (effet d'arrière-plan de la barre système).
struct MenuBarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Vue d'une pièce en déplacement : anime son glissement de `from` vers `to`.
struct MovingPieceView: View {
    let piece: ChessPiece
    let from: Position
    let to: Position
    let squareSize: CGFloat

    @State private var progress: CGFloat = 0

    /// Position X interpolée (animation du déplacement).
    private var currentX: CGFloat {
        CGFloat(from.col) * squareSize + squareSize / 2 + CGFloat(to.col - from.col) * squareSize * progress
    }

    /// Position Y interpolée (animation du déplacement).
    private var currentY: CGFloat {
        CGFloat(from.row) * squareSize + squareSize / 2 + CGFloat(to.row - from.row) * squareSize * progress
    }

    var body: some View {
        Group {
            if let pieceImage = PieceSpriteSheet.shared.image(for: piece) {
                Image(nsImage: pieceImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: squareSize * 0.85, height: squareSize * 0.85)
            } else {
                Text(piece.symbol)
                    .font(.system(size: squareSize * 0.7))
            }
        }
        .frame(width: squareSize, height: squareSize)
        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0)
        .position(x: currentX, y: currentY)
        .animation(.easeInOut(duration: 0.15), value: progress)
        .onAppear {
            progress = 1
        }
    }
}

/// Vue d'une case de l'échiquier : couleur, pièce, indicateurs de sélection et
/// de coup légal, et étiquettes de colonne/rangée sur les bords.
struct SquareView: View {
    let pos: Position
    let piece: ChessPiece?
    let isSelected: Bool
    let isValidMove: Bool
    let squareSize: CGFloat
    let onTap: () -> Void

    /// Vrai si la case est une case sombre (motif damier).
    private var isDark: Bool {
        (pos.row + pos.col) % 2 != 0
    }

    /// Couleur de fond de la case (claire ou sombre).
    private var baseColor: Color {
        isDark ? Color(hex: "#8CADD6") : Color(hex: "#D9EBFA")
    }

    private var labelColor: Color {
        Color(hex: "#4D73A6")
    }

    /// Lettre de la colonne (étiquette en bas du plateau).
    private var columnLetter: String {
        Character(UnicodeScalar(65 + pos.col)!).uppercased()
    }

    /// Numéro de la rangée (étiquette à gauche du plateau).
    private var rowNumber: String {
        "\(8 - pos.row)"
    }

    /// Corps de la case.
    var body: some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? Color.yellow.opacity(0.6) : baseColor)
                .frame(width: squareSize, height: squareSize)

            if isValidMove {
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: squareSize * 0.3, height: squareSize * 0.3)
            }

            if let piece = piece {
                if let pieceImage = PieceSpriteSheet.shared.image(for: piece) {
                    Image(nsImage: pieceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: squareSize * 0.85, height: squareSize * 0.85)
                } else {
                    Text(piece.symbol)
                        .font(.system(size: squareSize * 0.7))
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 1, y: 1)
                }
            }

            if pos.row == 7 {
                Text(columnLetter)
                    .font(.system(size: squareSize * 0.2, weight: .bold))
                    .foregroundColor(labelColor)
                    .position(x: squareSize * 0.85, y: squareSize * 0.85)
            }

            if pos.col == 0 {
                Text(rowNumber)
                    .font(.system(size: squareSize * 0.2, weight: .bold))
                    .foregroundColor(labelColor)
                    .position(x: squareSize * 0.15, y: squareSize * 0.15)
            }
        }
        .frame(width: squareSize, height: squareSize)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

/// Conversion hexadécimale (« #RRGGBB ») vers une couleur SwiftUI.
extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
