//
//  AppUser.swift
//  SocialEats
//
//  A SocialEats member. Saved in Firestore at  users/{id}
//

import Foundation

struct AppUser: Identifiable, Equatable, Codable {
    var id: String
    var displayName: String
    var username: String
    var phoneNumber: String?
    var email: String?

    // Reputation ("Foodie Karma")
    var karma: Int
    var mealsShared: Int
    var newFriends: Int
    var tablesHosted: Int
    /// 0.0 – 5.0 average rating from tablemates
    var hostRating: Double

    // Taste profile
    var dietaryTags: [DietaryTag]
    var ambiences: [Ambience]
    var cuisines: [Cuisine]
    var diningStyle: DiningStyle

    var joinedAt: Date

    /// A brand-new user with the starting karma score (proposal: Feature 1, step 4).
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

    /// First name only, used for "Hello, Alex 👋"
    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    /// Host rating as a percentage for the Profile screen ("98%")
    var hostRatingPercent: Int {
        Int((hostRating / 5.0 * 100).rounded())
    }
}

/// Taste choices made on the onboarding "What's Your Dining Vibe?" screen,
/// kept in memory until the user finishes signing in.
struct TasteProfileDraft: Equatable {
    var ambiences: [Ambience] = []
    var cuisines: [Cuisine] = []
    var diningStyle: DiningStyle = .smallGroup
    var dietaryTags: [DietaryTag] = []
}
