// ChessnutBoard.swift
// Rôle du fichier : pilote Bluetooth (Core Bluetooth) de l'échiquier
// électronique Chessnut (Air, Air+, Go, Pro). Gère la connexion BLE, le flux
// FEN en temps réel (position des pièces), les LED de guidage et la batterie.
// Version simplifiée : pas d'import des parties enregistrées (OTB).

import Foundation
import CoreBluetooth
import Combine

/// État de la connexion à l'échiquier Bluetooth.
enum ChessnutConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected

    /// Vrai si l'échiquier est actuellement connecté.
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Échiquier Chessnut découvert lors du scan BLE.
struct ChessnutDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Pilote Bluetooth (BLE) des échiquiers Chessnut (Air, Air+, Go, Pro).
/// Protocole : https://github.com/chessnutech/Chessnut_eBoards
final class ChessnutManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // Services / caractéristiques Chessnut
    private let fenServiceUUID = CBUUID(string: "1b7e8261-2877-41c3-b46e-cf057c562023")
    private let fenCharacteristicUUID = CBUUID(string: "1b7e8262-2877-41c3-b46e-cf057c562023")
    private let commandServiceUUID = CBUUID(string: "1b7e8271-2877-41c3-b46e-cf057c562023")
    private let commandCharacteristicUUID = CBUUID(string: "1b7e8272-2877-41c3-b46e-cf057c562023")
    private let responseCharacteristicUUID = CBUUID(string: "1b7e8273-2877-41c3-b46e-cf057c562023")

    // Codes pièces : index = valeur du nibble (1..12)
    private let pieceByCode: [Character?] = [
        nil, "q", "k", "b", "p", "n", "R", "P", "r", "B", "N", "Q", "K"
    ]

    @Published var state: ChessnutConnectionState = .idle
    @Published var devices: [ChessnutDevice] = []
    @Published var connectedName = ""
    @Published var batteryPercent: Int = -1
    @Published var isCharging = false
    @Published var lastPlacement = ""
    @Published var errorMessage = ""

    var onFENChange: ((String) -> Void)?

    private var centralManager: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var fenCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var pendingFENData = Data()
    private var pendingReconnectID: UUID?

    private static let lastDeviceIDKey = "ChessnutLastDeviceID"

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Actions

    /// Lance un scan des périphériques Bluetooth (sans filtre, les échiquiers
    /// Chessnut sont filtrés à la découverte).
    func startScan() {
        devices = []
        errorMessage = ""
        guard centralManager.state == .poweredOn else {
            errorMessage = loc("chessnut.bluetoothUnavailable")
            return
        }
        state = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// Arrête le scan en cours (et l'éventuelle reconnexion en attente).
    func stopScan() {
        pendingReconnectID = nil
        centralManager.stopScan()
        if !state.isConnected {
            state = .idle
        }
    }

    // Dernier échiquier connecté, mémorisé pour se reconnecter directement.
    var canReconnectLast: Bool {
        UserDefaults.standard.string(forKey: Self.lastDeviceIDKey) != nil
    }

    /// Tente de se reconnecter au dernier échiquier connu : soit via le cache
    /// du système (retrievePeripherals), soit en le recherchant par scan.
    func reconnectLast() -> Bool {
        guard centralManager.state == .poweredOn,
              let idString = UserDefaults.standard.string(forKey: Self.lastDeviceIDKey),
              let uuid = UUID(uuidString: idString) else { return false }
        errorMessage = ""
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first {
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .connecting
            centralManager.connect(peripheral, options: nil)
            return true
        }
        // Inconnu du système : on le retrouve par scan.
        pendingReconnectID = uuid
        state = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        return true
    }

    /// Connecte l'échiquier sélectionné dans la liste des périphériques découverts.
    func connect(to device: ChessnutDevice) {
        guard centralManager.state == .poweredOn else { return }
        stopScan()
        guard let peripheral = discovered[device.id] else {
            errorMessage = loc("chessnut.deviceLost")
            return
        }
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    /// Déconnecte l'échiquier courant (ou remet à zéro l'état si non connecté).
    func disconnect() {
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            resetConnection()
        }
    }

    /// Interroge le niveau de batterie (résultat reçu dans `handleResponse`).
    func requestBattery() {
        guard let char = commandCharacteristic, let peripheral else { return }
        peripheral.writeValue(Data([0x29, 0x01, 0x00]), for: char, type: .withResponse)
    }

    /// Allume les LED des cases données (utilisé pour guider l'utilisateur sur
    /// le plateau physique : coup du moteur, erreur de synchronisation…).
    func lightSquares(_ squares: [Position]) {
        guard let char = commandCharacteristic, let peripheral else { return }
        var command: [UInt8] = [0x0A, 0x08]
        for _ in 0..<8 { command.append(0) }
        // Mapping vérifié en direct : pour allumer e7 (row 6, col 4) le paquet
        // attendu est byte 3, bit 4. Donc byte = 9 - row, bit = col (col 0 = a).
        for square in squares where square.isValid {
            command[9 - square.row] |= UInt8(1 << square.col)
        }
        peripheral.writeValue(Data(command), for: char, type: .withResponse)
    }

    /// Éteint toutes les LED de l'échiquier.
    func clearLEDs() {
        lightSquares([])
    }

    // MARK: - CBCentralManagerDelegate

    /// Rappel Core Bluetooth : mise à jour de l'état du Bluetooth.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Log.app.info("Bluetooth available")
        case .poweredOff:
            errorMessage = loc("chessnut.bluetoothOff")
            state = .idle
        default:
            errorMessage = loc("chessnut.bluetoothUnavailable")
            state = .idle
        }
    }

    /// Rappel Core Bluetooth : un périphérique est découvert. Seuls les
    /// échiquiers dont le nom commence par « Chessnut » sont retenus.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral.name?.hasPrefix("Chessnut") == true else { return }
        discovered[peripheral.identifier] = peripheral

        let device = ChessnutDevice(id: peripheral.identifier, name: peripheral.name ?? loc("chessnut.unknownBoard"), rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }

        // Reconnexion directe : l'échiquier recherché est apparu → on s'y connecte.
        if let pendingReconnectID, pendingReconnectID == peripheral.identifier {
            centralManager.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .connecting
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Rappel Core Bluetooth : connexion établie → mémorise l'identifiant,
    /// passe à l'état « connected » et découvre les services FEN + commandes.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Log.app.info("Connected to \(peripheral.name ?? "?")")
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastDeviceIDKey)
        state = .connected
        connectedName = peripheral.name ?? ""
        peripheral.delegate = self
        peripheral.discoverServices([fenServiceUUID, commandServiceUUID])
    }

    /// Rappel Core Bluetooth : échec de la connexion → message d'erreur.
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        errorMessage = error?.localizedDescription ?? loc("chessnut.connectFailed")
        state = .idle
    }

    /// Rappel Core Bluetooth : déconnexion → remise à zéro de l'état de connexion.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Log.app.info("Disconnected from \(peripheral.name ?? "?")")
        resetConnection()
    }

    /// Remet l'intégralité de l'état de connexion à zéro (déconnexion).
    private func resetConnection() {
        pendingReconnectID = nil
        peripheral = nil
        fenCharacteristic = nil
        commandCharacteristic = nil
        responseCharacteristic = nil
        pendingFENData = Data()
        batteryPercent = -1
        isCharging = false
        connectedName = ""
        state = .idle
    }

    // MARK: - CBPeripheralDelegate

    /// Rappel CBPeripheral : services découverts → demande de découverte des
    /// caractéristiques FEN et commande/réponse.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            errorMessage = error!.localizedDescription
            return
        }
        for service in peripheral.services ?? [] {
            if service.uuid == fenServiceUUID {
                peripheral.discoverCharacteristics([fenCharacteristicUUID], for: service)
            } else if service.uuid == commandServiceUUID {
                peripheral.discoverCharacteristics([commandCharacteristicUUID, responseCharacteristicUUID], for: service)
            }
        }
    }

    /// Rappel CBPeripheral : caractéristiques découvertes → abonnement aux
    /// notifications FEN/réponse, puis activation du flux temps réel + batterie.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            errorMessage = error!.localizedDescription
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == fenCharacteristicUUID {
                fenCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == commandCharacteristicUUID {
                commandCharacteristic = characteristic
            } else if characteristic.uuid == responseCharacteristicUUID {
                responseCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        // Active le flux FEN en temps réel puis interroge la batterie.
        if fenCharacteristic != nil, commandCharacteristic != nil {
            peripheral.writeValue(Data([0x21, 0x01, 0x00]), for: commandCharacteristic!, type: .withResponse)
            requestBattery()
        }
    }

    /// Rappel CBPeripheral : changement de l'état d'abonnement aux notifications.
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Log.app.error("Notify \(characteristic.uuid): \(error.localizedDescription)")
        }
    }

    /// Rappel CBPeripheral : une commande a été écrite (log des erreurs).
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Log.app.error("Write \(characteristic.uuid): \(error.localizedDescription)")
        }
    }

    /// Rappel CBPeripheral : données reçues → paquet FEN ou réponse batterie.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else {
            if let error {
                Log.app.error("Update \(characteristic.uuid): \(error.localizedDescription)")
            }
            return
        }

        if characteristic.uuid == fenCharacteristicUUID {
            handleFENPacket(value)
        } else if characteristic.uuid == responseCharacteristicUUID {
            handleResponse(value)
        }
    }

    // MARK: - Protocole Chessnut

    /// Traite un flux de données FEN temps réel : concatène les octets reçus,
    /// découpe en trames complètes (36 ou 38 octets selon le modèle) et
    /// déclenche `onFENChange` pour chaque nouveau placement détecté.
    private func handleFENPacket(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        Log.app.debug("FEN raw (\(data.count) bytes): \(hex)")
        pendingFENData.append(data)
        // Trames : 38 octets sur les Air+/Go/Pro (entête 0x01 0x24), 36 octets
        // sur les autres modèles (README). Placement dans les octets 2-33.
        while pendingFENData.count >= 36 {
            let frameLen = pendingFENData.count >= 38 && pendingFENData[pendingFENData.startIndex] == 0x01 && pendingFENData[pendingFENData.startIndex + 1] == 0x24
                ? 38
                : 36
            let packet = [UInt8](pendingFENData.prefix(frameLen))
            pendingFENData.removeFirst(frameLen)
            let placement = decodePlacement(packet)
            Log.app.debug("FEN packet decoded: \(placement)")
            guard placement != lastPlacement else { continue }
            lastPlacement = placement
            onFENChange?(placement)
        }
    }

    /// Traite une réponse de l'échiquier : réponse batterie (0x2A 0x02 + niveau/charge).
    private func handleResponse(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0x2A, bytes[1] == 0x02 else { return }
        let raw = bytes[2]
        batteryPercent = Int(raw & 0x7F)
        isCharging = (raw & 0x80) != 0
    }

    /// Décode la position (placement FEN) depuis un paquet FEN.
    /// La rangée 0 du paquet (octets 2-5) = rangée 1 (arrière blanches, a1-h1),
    /// la rangée 7 (octets 30-33) = rangée 8 (arrière noires, a8-h8). Chaque
    /// rangée est stockée a-fichier à gauche : colonne paire = nibble bas,
    /// colonne impaire = haut. On parcourt donc les rangées de 7 à 0.
    func decodePlacement(_ packet: [UInt8]) -> String {
        guard packet.count >= 34 else { return "" }

        var fen = ""
        var empty = 0
        for row in stride(from: 7, through: 0, by: -1) {
            for column in 0..<8 {
                let index = ((row * 8 + column) / 2) + 2
                let code = column.isMultiple(of: 2)
                    ? packet[index] & 0x0F
                    : packet[index] >> 4
                let piece: Character?
                if code < pieceByCode.count {
                    piece = pieceByCode[Int(code)]
                } else {
                    piece = nil
                }
                if let piece {
                    if empty > 0 { fen += String(empty); empty = 0 }
                    fen.append(piece)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { fen += String(empty); empty = 0 }
            if row > 0 { fen += "/" }
        }
        return fen
    }
}
