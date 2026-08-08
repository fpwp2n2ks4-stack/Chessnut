// EngineOptionsView.swift
// Rôle du fichier : affichage et modification des paramètres UCI déclarés par
// le moteur (check, spin, combo, string, button) — « Récupérer » démarre le
// moteur pour obtenir sa liste d'options, chaque changement est envoyé via
// `setoption`.

import SwiftUI

/// Fenêtre d'édition des options UCI d'un moteur.
struct EngineOptionsView: View {
    @ObservedObject var engine: Engine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(loc("engine.options.title"))
                .font(.headline)

            Divider()

            if engine.options.isEmpty {
                Text(loc("engine.options.none"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(engine.options) { option in
                            OptionRow(engine: engine, option: option)
                        }
                    }
                    .padding(4)
                }
            }

            Divider()

            HStack {
                Button(loc("engine.options.refresh")) {
                    if !engine.isRunning { engine.start() }
                }
                Spacer()
                Button(loc("engine.options.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 420)
    }
}

/// Ligne d'édition d'une option UCI, adaptée à son type.
private struct OptionRow: View {
    @ObservedObject var engine: Engine
    let option: UCIOption

    /// Applique une nouvelle valeur : l'envoie au moteur et met à jour l'affichage.
    private func setValue(_ value: String) {
        engine.setOption(option.name, value: value)
        if let idx = engine.options.firstIndex(where: { $0.id == option.id }) {
            engine.options[idx].currentVal = value
        }
    }

    /// Réinitialise l'option à sa valeur par défaut.
    private func reset() {
        setValue(option.defaultVal)
    }

    /// Contrôle d'édition selon le type d'option.
    @ViewBuilder
    private var control: some View {
        switch option.type {
        case "check":
            Toggle("", isOn: Binding(
                get: { option.currentVal == "true" },
                set: { setValue($0 ? "true" : "false") }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

        case "spin":
            if let minS = option.min, let maxS = option.max,
               let minI = Int(minS), let maxI = Int(maxS),
               let val = Int(option.currentVal) {
                Stepper("\(val)", value: Binding(
                    get: { val },
                    set: { setValue("\($0)") }
                ), in: minI...maxI)
            } else {
                TextField("", text: Binding(
                    get: { option.currentVal },
                    set: { setValue($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
            }

        case "combo":
            if let vars = option.varVals {
                Picker("", selection: Binding(
                    get: { option.currentVal },
                    set: { setValue($0) }
                )) {
                    ForEach(vars, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }
                .labelsHidden()
            }

        case "button":
            Button(loc("engine.options.apply")) { setValue("") }

        default:
            TextField("", text: Binding(
                get: { option.currentVal },
                set: { setValue($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.callout)
                    .fontWeight(.medium)
                Text("\(option.type) · \(loc("engine.options.default")) : \(option.defaultVal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            control
            if option.type != "button" && option.currentVal != option.defaultVal {
                Button(loc("engine.options.reset")) { reset() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
