//
//  FirestoreServices.swift
//  SocialEats
//
//  Cloud Firestore backend (proposal Feature 4 — "API (Firebase Backend)").
//  • Real-time listeners (addSnapshotListener) push seat changes to every phone.
//  • Joining a table uses a TRANSACTION so two people can never grab
//    the same last seat at the same moment (capacity logic, Feature 9).
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Tables

final class FirestoreTableService: TableServicing {
    private let db = Firestore.firestore()
    private var tables: CollectionReference { db.collection(FirestorePath.tables) }
    private var rsvps: CollectionReference { db.collection(FirestorePath.rsvps) }

    /// One RSVP document per person per table: rsvps/{tableId}_{userId}
    private func rsvpReference(tableId: String, userId: String) -> DocumentReference {
        rsvps.document("\(tableId)_\(userId)")
    }

    private func rsvpData(tableId: String, userId: String, seat: Int?, status: RSVPStatus) -> [String: Any] {
        [
            "tableId": tableId,
            "userId": userId,
            "seatNumber": firestoreValue(seat),
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    func listenToActiveTables(onChange: @escaping (Result<[CommunityTable], Error>) -> Void) -> ListenerToken {
        // Only tables starting from 3 hours ago onwards
        let since = Timestamp(date: Date().addingTimeInterval(-3 * 60 * 60))
        let registration = tables
            .whereField("startTime", isGreaterThan: since)
            .order(by: "startTime")
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                let list = snapshot?.documents.compactMap {
                    CommunityTable(id: $0.documentID, data: $0.data())
                } ?? []
                onChange(.success(list))
            }
        return FirestoreListenerToken(registration: registration)
    }

    func listenToTable(id: String, onChange: @escaping (CommunityTable?) -> Void) -> ListenerToken {
        let registration = tables.document(id).addSnapshotListener { snapshot, _ in
            guard let snapshot else { onChange(nil); return }
            onChange(CommunityTable(id: snapshot.documentID, data: snapshot.data()))
        }
        return FirestoreListenerToken(registration: registration)
    }

    func fetchTable(id: String) async throws -> CommunityTable? {
        let snapshot = try await tables.document(id).getDocument()
        return CommunityTable(id: snapshot.documentID, data: snapshot.data())
    }

    func fetchActiveTables() async throws -> [CommunityTable] {
        let since = Timestamp(date: Date().addingTimeInterval(-3 * 60 * 60))
        let snapshot = try await tables
            .whereField("startTime", isGreaterThan: since)
            .order(by: "startTime")
            .limit(to: 100)
            .getDocuments()
        return snapshot.documents.compactMap { CommunityTable(id: $0.documentID, data: $0.data()) }
    }

    func createTable(_ table: CommunityTable) async throws -> String {
        let document = tables.document()           // new auto id
        var newTable = table
        newTable.id = document.documentID

        // Table + the host's own RSVP (Seat #1) are saved together in one batch
        let batch = db.batch()
        batch.setData(newTable.firestoreData, forDocument: document)
        // (Sample tables from the demo button have made-up hosts, so they get no RSVP)
        if newTable.hostId == Auth.auth().currentUser?.uid {
            batch.setData(rsvpData(tableId: newTable.id, userId: newTable.hostId, seat: 1, status: .confirmed),
                          forDocument: rsvpReference(tableId: newTable.id, userId: newTable.hostId))
        }
        try await batch.commit()
        return document.documentID
    }

    func joinTable(id: String, userId: String, userName: String) async throws -> CommunityTable {
        let reference = tables.document(id)

        // runTransaction re-reads the document and retries if someone else
        // changed it at the same time — so seats can never go over capacity.
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(reference)
                guard let table = CommunityTable(id: snapshot.documentID, data: snapshot.data()) else {
                    errorPointer?.pointee = TableJoinError.notFound as NSError
                    return nil
                }
                let updated = try table.adding(userId: userId, name: userName)
                transaction.updateData([
                    "attendeeIds": updated.attendeeIds,
                    "attendeeNames": updated.attendeeNames,
                    "seatsFilled": updated.attendeeIds.count
                ], forDocument: reference)
                // RSVP state saved in the SAME transaction (both happen, or neither)
                transaction.setData(self.rsvpData(tableId: id, userId: userId,
                                                  seat: updated.seatNumber(for: userId), status: .confirmed),
                                    forDocument: self.rsvpReference(tableId: id, userId: userId))
                return updated
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let table = result as? CommunityTable else { throw TableJoinError.notFound }
        return table
    }

    func leaveTable(id: String, userId: String) async throws {
        let reference = tables.document(id)
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(reference)
                guard let table = CommunityTable(id: snapshot.documentID, data: snapshot.data()) else { return nil }
                let updated = try table.removing(userId: userId)
                transaction.updateData([
                    "attendeeIds": updated.attendeeIds,
                    "attendeeNames": updated.attendeeNames,
                    "seatsFilled": updated.attendeeIds.count
                ], forDocument: reference)
                transaction.setData(self.rsvpData(tableId: id, userId: userId, seat: nil, status: .cancelled),
                                    forDocument: self.rsvpReference(tableId: id, userId: userId))
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func submitReceipt(tableId: String, userId: String, result: ReceiptScanResult) async throws {
        let batch = db.batch()
        batch.setData([
            "userId": userId,
            "restaurantName": firestoreValue(result.restaurantName),
            "total": firestoreValue(result.total),
            "currency": result.currencyCode,
            "receiptTime": firestoreValue(result.timestamp.map { Timestamp(date: $0) }),
            "verifiedAt": FieldValue.serverTimestamp()
        ], forDocument: tables.document(tableId).collection(FirestorePath.receipts).document(userId))
        batch.setData(["status": RSVPStatus.completed.rawValue, "updatedAt": FieldValue.serverTimestamp()],
                      forDocument: rsvpReference(tableId: tableId, userId: userId), merge: true)
        try await batch.commit()
    }

    func rateTablemate(tableId: String, raterId: String, rateeId: String, stars: Int) async throws {
        try await tables.document(tableId)
            .collection(FirestorePath.ratings).document("\(raterId)_\(rateeId)")
            .setData([
                "raterId": raterId,
                "rateeId": rateeId,
                "stars": stars,
                "createdAt": FieldValue.serverTimestamp()
            ])
    }
}

// MARK: - Users

final class FirestoreUserService: UserServicing {
    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection(FirestorePath.users) }

    func fetchUser(id: String) async throws -> AppUser? {
        let snapshot = try await users.document(id).getDocument()
        return AppUser(id: id, data: snapshot.data())
    }

    func saveUser(_ user: AppUser) async throws {
        // merge: true keeps any fields we didn't send
        try await users.document(user.id).setData(user.firestoreData, merge: true)
    }

    func listenToUser(id: String, onChange: @escaping (AppUser?) -> Void) -> ListenerToken {
        let registration = users.document(id).addSnapshotListener { snapshot, _ in
            onChange(AppUser(id: id, data: snapshot?.data()))
        }
        return FirestoreListenerToken(registration: registration)
    }

    func addKarma(_ points: Int, to userId: String, mealCompleted: Bool) async throws {
        var update: [String: Any] = ["karma": FieldValue.increment(Int64(points))]
        if mealCompleted {
            update["mealsShared"] = FieldValue.increment(Int64(1))
        }
        try await users.document(userId).updateData(update)
    }

    func addFriends(_ count: Int, to userId: String) async throws {
        guard count > 0 else { return }
        try await users.document(userId).updateData(["newFriends": FieldValue.increment(Int64(count))])
    }

    func listenToActivity(userId: String, onChange: @escaping ([ActivityItem]) -> Void) -> ListenerToken {
        let registration = users.document(userId).collection(FirestorePath.activity)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, _ in
                let items = snapshot?.documents.compactMap { ActivityItem(id: $0.documentID, data: $0.data()) } ?? []
                onChange(items)
            }
        return FirestoreListenerToken(registration: registration)
    }

    func addActivity(_ item: ActivityItem, for userId: String) async throws {
        try await users.document(userId).collection(FirestorePath.activity)
            .document(item.id).setData(item.firestoreData)
    }

    func markActivityRead(userId: String, itemIds: [String]) async throws {
        guard !itemIds.isEmpty else { return }
        let batch = db.batch()
        for id in itemIds {
            let reference = users.document(userId).collection(FirestorePath.activity).document(id)
            batch.updateData(["isRead": true], forDocument: reference)
        }
        try await batch.commit()
    }
}

// MARK: - Chat

final class FirestoreChatService: ChatServicing {
    private let db = Firestore.firestore()

    func listenToMessages(tableId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerToken {
        let registration = db.collection(FirestorePath.tables).document(tableId)
            .collection(FirestorePath.messages)
            .order(by: "sentAt")
            .limit(toLast: 200)
            // includeMetadataChanges: we also get told when a message
            // goes from "waiting to upload" (offline) to "delivered"
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, _ in
                let messages = snapshot?.documents.compactMap { document -> ChatMessage? in
                    var message = ChatMessage(id: document.documentID, data: document.data(with: .estimate))
                    message?.isPending = document.metadata.hasPendingWrites
                    return message
                } ?? []
                onChange(messages)
            }
        return FirestoreListenerToken(registration: registration)
    }

    func sendMessage(_ message: ChatMessage, tableId: String) async throws {
        // Firestore queues this automatically if the phone is offline
        // and sends it when the connection comes back.
        try await db.collection(FirestorePath.tables).document(tableId)
            .collection(FirestorePath.messages).document(message.id)
            .setData(message.firestoreData)
    }
}
