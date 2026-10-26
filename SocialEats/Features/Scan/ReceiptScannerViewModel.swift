//
//  ReceiptScannerViewModel.swift
//  SocialEats
//
//  Proposal Advanced Feature 1 — On-Device Vision AI Receipt Scanner.
//   1. Live camera frames -> Vision OCR (fast) -> fields auto-detected
//   2. Capture / pick photo -> Vision OCR (accurate) -> ReceiptParser
//   3. Validate against the user's active reservation (venue + time)
//   4. Verified -> Firestore receipt + karma points + pass marked complete
//

import Foundation
import UIKit
import Combine

@MainActor
final class ReceiptScannerViewModel: ObservableObject {

    enum Phase: Equatable {
        case scanning
        case processing
        case reviewed            // fields found, waiting for "Verify & Claim"
        case claiming
        case success(points: Int)
    }

    @Published private(set) var phase: Phase = .scanning
    @Published private(set) var scanResult: ReceiptScanResult?
    @Published private(set) var validation: ReceiptValidation?
    /// Fields detected from the LIVE camera (before capture)
    @Published private(set) var liveResult: ReceiptScanResult?
    @Published var selectedTableId: String?
    @Published var errorMessage: String?
    @Published private(set) var ratedTablemates: [String: Int] = [:]

    let camera = CameraController()

    private let scanner: ReceiptScanning
    private let tablesStore: TablesStore
    private let reservations: ReservationManager
    private let session: SessionStore
    private var cancellables = Set<AnyCancellable>()

    init(scanner: ReceiptScanning, tablesStore: TablesStore,
         reservations: ReservationManager, session: SessionStore) {
        self.scanner = scanner
        self.tablesStore = tablesStore
        self.reservations = reservations
        self.session = session

        // Parse every live OCR result so the card fills in as you aim
        camera.$liveLines
            .filter { !$0.isEmpty }
            .map { ReceiptParser.parse(lines: $0) }
            .sink { [weak self] result in self?.liveResult = result }
            .store(in: &cancellables)

        // The camera is its own ObservableObject — pass its changes on
        // so the view refreshes when the camera starts / is denied
        camera.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        selectedTableId = eligibleTables.first?.id
    }

    convenience init(container: AppContainer) {
        self.init(scanner: container.receiptScanner, tablesStore: container.tablesStore,
                  reservations: container.reservations, session: container.session)
    }

    // MARK: - Which meal are we verifying?

    /// Tables the user joined that are happening around now and not yet verified.
    var eligibleTables: [CommunityTable] {
        guard let uid = session.userId else { return [] }
        let verifiedIds = Set(reservations.savedPasses(for: uid).filter(\.isVerified).map(\.tableId))
        let now = Date()
        return tablesStore.joinedTables(userId: uid).filter { table in
            !verifiedIds.contains(table.id)
                && table.startTime < now.addingTimeInterval(3 * 3600)     // starts within 3 h
                && table.startTime > now.addingTimeInterval(-8 * 3600)    // or started < 8 h ago
        }
    }

    var selectedTable: CommunityTable? {
        guard let selectedTableId else { return eligibleTables.first }
        return tablesStore.table(id: selectedTableId)
    }

    /// "Vision AI: Artisan Pizza (+200 pts)" chip on the camera view
    var liveChipText: String? {
        guard let live = liveResult, let name = live.restaurantName else { return nil }
        let points = KarmaCalculator.pointsForVerifiedMeal(isHost: selectedTable?.isHost(session.userId) ?? false)
        return "Vision AI: \(name) (+\(points) pts)"
    }

    /// Venue match % for the "99.4% Match" badge
    var matchPercent: Int? {
        if case .verified(let score)? = validation { return Int(score * 100) }
        return nil
    }

    var pointsPreview: Int {
        KarmaCalculator.pointsForVerifiedMeal(isHost: selectedTable?.isHost(session.userId) ?? false)
    }

    // MARK: - Camera

    func startCamera() { camera.start() }
    func stopCamera() { camera.stop() }

    /// Shutter button: accurate OCR on the current frame.
    func captureFromCamera() async {
        guard let image = camera.captureCurrentFrame() else {
            errorMessage = "Camera isn't ready yet. Try again in a second."
            return
        }
        await analyse(image)
    }

    /// Photo library (also how you test on the Simulator).
    func analyse(_ image: UIImage) async {
        phase = .processing
        errorMessage = nil
        do {
            let lines = try await scanner.recognizeLines(in: image)
            let result = ReceiptParser.parse(lines: lines)
            scanResult = result
            validate(result)
            phase = .reviewed
            Haptics.impact(.medium)
        } catch {
            errorMessage = error.localizedDescription
            phase = .scanning
            Haptics.error()
        }
    }

    /// Simulator only (no camera): prints a test receipt for the selected
    /// table and sends it through the same Vision OCR as a real photo.
    func scanTestReceipt() async {
        guard let table = selectedTable else {
            errorMessage = "Join a table first — receipts are matched to your reservation."
            return
        }
        let image = TestReceiptRenderer.image(venueName: table.venueName)
        await analyse(image)
    }

    /// Re-check when the user picks another table.
    func revalidate() {
        if let scanResult { validate(scanResult) }
    }

    private func validate(_ result: ReceiptScanResult) {
        guard let table = selectedTable else {
            validation = nil
            errorMessage = "Join a table first — receipts are matched to your reservation."
            return
        }
        validation = ReceiptParser.validate(result, venueName: table.venueName, meetupStart: table.startTime)
    }

    /// "Edit" next to TIMESTAMP (prototype Figure 14): fixes a time the
    /// OCR misread. Only the time can be edited — the restaurant name and
    /// total always come from the receipt, so the check can't be faked.
    func updateTimestamp(_ date: Date) {
        guard var result = scanResult else { return }
        result.timestamp = date
        scanResult = result
        validate(result)
    }

    func retake() {
        scanResult = nil
        validation = nil
        errorMessage = nil
        phase = .scanning
    }

    // MARK: - Claim karma

    func verifyAndClaim() async {
        guard let table = selectedTable, let uid = session.userId,
              let scanResult, validation?.isVerified == true else { return }
        phase = .claiming
        do {
            let points = try await reservations.completeMeal(table: table, userId: uid, receipt: scanResult)
            Haptics.success()
            phase = .success(points: points)
        } catch {
            errorMessage = error.localizedDescription
            phase = .reviewed
        }
    }

    /// "Rate Your Tablemates" stars (+15 karma each)
    func rate(tablemateId: String, stars: Int) async {
        guard let table = selectedTable, let uid = session.userId,
              ratedTablemates[tablemateId] == nil else { return }
        ratedTablemates[tablemateId] = stars
        try? await reservations.rate(tablemateId: tablemateId, stars: stars, table: table, raterId: uid)
    }

    /// Everyone at the table except me (for the rating list)
    var tablemates: [(id: String, name: String)] {
        guard let table = selectedTable else { return [] }
        return zip(table.attendeeIds, table.attendeeNames)
            .filter { $0.0 != session.userId }
            .map { (id: $0.0, name: $0.1) }
    }

    func reset() {
        retake()
        ratedTablemates = [:]
        selectedTableId = eligibleTables.first?.id
    }
}
