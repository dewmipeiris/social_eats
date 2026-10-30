//  AppUser.swift

import Foundation

struct AppUser: Identifiable, Equatable, Codable {
    var id: String
    var displayName: String
    var username: String
    var phoneNumber: String?
    var email: String?

    var karma: Int
    var mealsShared: Int
    var newFriends: Int
    var tablesHosted: Int
    var hostRating: Double

    var dietaryTags: [DietaryTag]
    var ambiences: [Ambience]
    var cuisines: [Cuisine]
    var diningStyle: DiningStyle

    var joinedAt: Date

    static func newMember(id: String, name: String, phone: String?, email: String?,
                          draft: TasteProfileDraft) -> AppUser {
        AppUser(
            id: id,
            displayName: name,
            username: "@" + name.lowercased().replacingOccurrences(of: " ", with: "_"),
            phoneNumber: phone,
            email: email,
            karma: KarmaCalculator.startingKarma,
            mealsShared: 0,
            newFriends: 0,
            tablesHosted: 0,
            hostRating: 5.0,
            dietaryTags: draft.dietaryTags,
            ambiences: draft.ambiences,
            cuisines: draft.cuisines,
            diningStyle: draft.diningStyle,
            joinedAt: Date()
        )
    }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var hostRatingPercent: Int {
        Int((hostRating / 5.0 * 100).rounded())
    }
}

struct TasteProfileDraft: Equatable {
    var ambiences: [Ambience] = []
    var cuisines: [Cuisine] = []
    var diningStyle: DiningStyle = .smallGroup
    var dietaryTags: [DietaryTag] = []
}
