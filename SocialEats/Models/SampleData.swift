//
//  SampleData.swift
//  SocialEats
//
//  Example tables and users around Colombo 07 (NIBM).
//  Used by: Demo mode (no Firebase), SwiftUI previews, unit tests,
//  and the "Add sample tables" button in Settings to fill Firestore.
//

import Foundation
import CoreLocation

enum SampleData {

    /// Centre point used when location permission is not given (Colombo 07)
    static let defaultCenter = CLLocationCoordinate2D(latitude: 6.9061, longitude: 79.8700)

    static let demoUser = AppUser(
        id: "demo-user",
        displayName: "Alex Morgan",
        username: "@alex_eats",
        phoneNumber: "+94771234567",
        email: "alex@example.com",
        karma: 1040,
        mealsShared: 18,
        newFriends: 14,
        tablesHosted: 3,
        hostRating: 4.9,
        dietaryTags: [.halal],
        ambiences: [.chillCozy, .techFounders],
        cuisines: [.neapolitanPizza, .ramenNoodles],
        diningStyle: .smallGroup,
        joinedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 400)
    )

    /// Profiles for some of the sample hosts/guests, so tablemate profiles
    /// (Community Hub) have something to show in Demo mode.
    static let sampleMembers: [AppUser] = [
        member("h-sarah", "Sarah Jenkins", karma: 2150, meals: 31, ambiences: [.techFounders, .quickLively],
               cuisines: [.streetTacos, .neapolitanPizza], diet: [.halal]),
        member("u-marcus", "Marcus Chen", karma: 640, meals: 9, ambiences: [.chillCozy, .techFounders],
               cuisines: [.ramenNoodles, .neapolitanPizza], diet: []),
        member("u-elena", "Elena Rossi", karma: 180, meals: 1, ambiences: [.quietIntrovert],
               cuisines: [.healthyBowls, .neapolitanPizza], diet: [.vegetarian]),
        member("h-kenji", "Kenji Mori", karma: 1320, meals: 22, ambiences: [.casualWine],
               cuisines: [.ramenNoodles], diet: [.pescatarian]),
        member("u-ana", "Ana Silva", karma: 930, meals: 15, ambiences: [.chillCozy],
               cuisines: [.ramenNoodles, .bakeryCoffee], diet: [])
    ]

    private static func member(_ id: String, _ name: String, karma: Int, meals: Int, ambiences: [Ambience],
                               cuisines: [Cuisine], diet: [DietaryTag]) -> AppUser {
        AppUser(id: id, displayName: name,
                username: "@" + name.lowercased().replacingOccurrences(of: " ", with: "_"),
                phoneNumber: "+9477000\(UInt(bitPattern: id.hashValueStable) % 10000)", email: nil,
                karma: karma, mealsShared: meals, newFriends: meals * 2, tablesHosted: id.hasPrefix("h-") ? 8 : 0,
                hostRating: 4.8, dietaryTags: diet, ambiences: ambiences, cuisines: cuisines,
                diningStyle: .smallGroup, joinedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 200))
    }

    /// Builds sample tables relative to a centre point and "now",
    /// so the demo always shows upcoming meetups nearby.
    static func tables(around center: CLLocationCoordinate2D = defaultCenter,
                       now: Date = Date()) -> [CommunityTable] {

        /// Moves the centre point by metres north/east
        func offset(_ north: Double, _ east: Double) -> (Double, Double) {
            let lat = center.latitude + north / 111_000
            let lon = center.longitude + east / (111_000 * cos(center.latitude * .pi / 180))
            return (lat, lon)
        }

        func make(_ id: String, _ title: String, _ about: String, venue: String, address: String,
                  category: TableCategory, host: (String, String, Double, Int),
                  inMinutes: Double, north: Double, east: Double, capacity: Int,
                  guests: [(String, String)], diet: [DietaryTag], price: Double,
                  perk: String?, number: Int) -> CommunityTable {
            let (lat, lon) = offset(north, east)
            return CommunityTable(
                id: id, title: title, about: about, venueName: venue, venueAddress: address,
                category: category,
                hostId: host.0, hostName: host.1, hostRating: host.2, hostTablesHosted: host.3,
                startTime: now.addingTimeInterval(inMinutes * 60),
                latitude: lat, longitude: lon,
                capacity: capacity,
                attendeeIds: [host.0] + guests.map { $0.0 },
                attendeeNames: [host.1] + guests.map { $0.1 },
                dietaryTags: diet, pricePerPerson: price, perk: perk,
                tableNumber: number, createdAt: now.addingTimeInterval(-3 * 3600)
            )
        }

        return [
            make("t-taco", "Taco Tuesday & Startup Chat",
                 "Let's talk zero-to-one product ideas over crispy birria and fresh guacamole! Open to founders, tech enthusiasts and foodies looking for inspiring casual banter. No pitch decks, just delicious food and great people.",
                 venue: "Chili's Cafe", address: "Ward Place, Colombo 07",
                 category: .tacos, host: ("h-sarah", "Sarah Jenkins", 4.9, 14),
                 inMinutes: 90, north: 250, east: 300, capacity: 4,
                 guests: [("u-marcus", "Marcus Chen"), ("u-elena", "Elena Rossi")],
                 diet: [.halal, .glutenFree, .vegan], price: 2500, perk: nil, number: 4),

            make("t-sushi", "Sushi Lovers Hangout",
                 "Omakase-style sharing platters and good conversation. Beginners welcome — we'll teach you the etiquette!",
                 venue: "Matsuya Kitchen", address: "Flower Road, Colombo 07",
                 category: .sushi, host: ("h-kenji", "Kenji Mori", 4.8, 9),
                 inMinutes: 170, north: -500, east: 550, capacity: 4,
                 guests: [("u-ana", "Ana Silva")],
                 diet: [.pescatarian], price: 4200, perk: nil, number: 112),

            make("t-coffee", "Coffee & Deep Work Sprint",
                 "Pomodoro focus sprints with pour-overs in between. Bring a laptop and a goal for the afternoon.",
                 venue: "The Daily Roast", address: "Horton Place, Colombo 07",
                 category: .coWork, host: ("h-elena", "Elena K.", 5.0, 21),
                 inMinutes: 45, north: 900, east: -500, capacity: 6,
                 guests: [("u-1", "Priya N."), ("u-2", "Tom W."), ("u-3", "Ishan P.")],
                 diet: [.vegetarian, .vegan], price: 1200, perk: "Fast Wi-Fi • Quiet", number: 27),

            make("t-pizza", "Friday Slice & Chat",
                 "First-year students and anyone new to Colombo — come make friends over wood-fired pizza.",
                 venue: "Luigi's Brick Oven", address: "Dharmapala Mawatha, Colombo 07",
                 category: .student, host: ("h-marcus", "Marcus Chen", 4.7, 6),
                 inMinutes: 300, north: -1200, east: -700, capacity: 4,
                 guests: [],
                 diet: [.vegetarian, .halal], price: 1800, perk: "20% Student Discount", number: 402),

            make("t-ramen", "Spicy Tonkotsu Ramen Club",
                 "Rating every ramen bowl in Colombo, one slurp at a time. Counter seats — cosy and lively!",
                 venue: "Menya Ramen Bar", address: "Duplication Road, Colombo 03",
                 category: .ramen, host: ("h-ana", "Ana Silva", 4.9, 11),
                 inMinutes: 120, north: 400, east: 1100, capacity: 4,
                 guests: [("u-4", "Dinuka R."), ("u-5", "Kavya S.")],
                 diet: [], price: 2900, perk: nil, number: 88),

            make("t-napoli", "Artisan Pizza & Neapolitan Wine Night",
                 "Wood-fired pizza tasting with Italian sodas and mocktails. Let's compare crusts!",
                 venue: "Bella Napoli Trattoria", address: "Rosmead Place, Colombo 07",
                 category: .pizza, host: ("h-marcus2", "Marcus D.", 4.8, 14),
                 inMinutes: 150, north: 280, east: -50, capacity: 4,
                 guests: [("u-6", "Jaya D."), ("u-7", "Sam K.")],
                 diet: [.vegetarian], price: 3500, perk: nil, number: 12)
        ]
    }

    static let sampleMessages: [ChatMessage] = [
        ChatMessage(id: "m1", senderId: "h-sarah", senderName: "Sarah Jenkins",
                    text: "Hey everyone! I just arrived and got a table by the warm patio under the lights. See you all soon! 🌮",
                    sentAt: Date().addingTimeInterval(-900), isFromHost: true),
        ChatMessage(id: "m2", senderId: "u-marcus", senderName: "Marcus Chen",
                    text: "Awesome! Parking right now, will be there in 5 mins.",
                    sentAt: Date().addingTimeInterval(-700), isFromHost: false),
        ChatMessage(id: "m3", senderId: "u-elena", senderName: "Elena Rossi",
                    text: "Can't wait! Are we trying the birria tacos?",
                    sentAt: Date().addingTimeInterval(-500), isFromHost: false)
    ]

    static let sampleActivity: [ActivityItem] = [
        ActivityItem(id: "a1", kind: .seatConfirmed, title: "Marcus confirmed your seat!",
                     body: "Dinner at Bella Napoli • Tonight", createdAt: Date().addingTimeInterval(-300),
                     tableId: "t-napoli"),
        ActivityItem(id: "a2", kind: .karmaUnlocked, title: "Dining Karma Unlocked!",
                     body: "Your receipt from Menya Ramen Bar was verified. You reached Silver Gourmet tier.",
                     createdAt: Date().addingTimeInterval(-7200), points: 250, isRead: true),
        ActivityItem(id: "a3", kind: .tableInvite, title: "Table invite from Elena",
                     body: "Elena invited you to Coffee & Deep Work Sprint (3 seats left)",
                     createdAt: Date().addingTimeInterval(-14400), tableId: "t-coffee", isRead: true)
    ]
}
