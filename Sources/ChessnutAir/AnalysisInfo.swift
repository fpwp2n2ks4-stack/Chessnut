// AnalysisInfo.swift
// Rôle du fichier : modèle d'analyse UCI extrait des lignes `info` du moteur
// (profondeur, score, temps, nœuds, nps, variante principale).

import Foundation

/// Statistiques d'analyse parsées depuis une ligne `info` UCI.
struct AnalysisInfo {
    var depth = ""
    var score = ""
    var timeMs = ""
    var nodes = ""
    var nps = ""
    var pv = ""

    /// Vrai si aucune statistique n'a été capturée.
    var isEmpty: Bool {
        depth.isEmpty && score.isEmpty && pv.isEmpty
    }

    /// Analyse une ligne `info` UCI et en extrait profondeur/score/temps/nœuds.
    static func parse(_ text: String) -> AnalysisInfo {
        var info = AnalysisInfo()
        guard !text.isEmpty else { return info }

        let statsStr: String
        if let range = text.range(of: "  ") {
            info.pv = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            statsStr = String(text[..<range.lowerBound])
        } else {
            statsStr = text
        }

        let tokens = statsStr.split(separator: " ")
        var i = 0
        while i < tokens.count {
            let t = String(tokens[i])
            if t == "d" && i + 1 < tokens.count { info.depth = String(tokens[i + 1]); i += 2 }
            else if t.hasPrefix("d") && info.depth.isEmpty { info.depth = String(t.dropFirst()); i += 1 }
            else if t == "cp" && i + 1 < tokens.count { let v = Int(tokens[i + 1]) ?? 0; info.score = v >= 0 ? "+\(v)" : "\(v)"; i += 2 }
            else if t == "mate" && i + 1 < tokens.count { info.score = "M\(tokens[i + 1])"; i += 2 }
            else if (t.hasPrefix("+") || t.hasPrefix("-")), info.score.isEmpty { info.score = t; i += 1 }
            else if t == "M" && i + 1 < tokens.count { info.score = "M\(tokens[i + 1])"; i += 2 }
            else if t.hasSuffix("ms") { info.timeMs = String(t.dropLast(2)); i += 1 }
            else if t.hasSuffix("nps") { info.nps = String(t.dropLast(3)); i += 1 }
            else if t.hasSuffix("n") { info.nodes = String(t.dropLast(1)); i += 1 }
            else { i += 1 }
        }
        return info
    }
}
