//
//  DiningOptions.swift
//  SocialEats
//
//  Small enums for the choices a user can make:
//  food categories, dietary tags, ambience, cuisines and dining style.
//  `String` raw values are what we save in Firestore.
//

import Foundation

/// Category chips on the Dashboard and Map ("Pizza", "Sushi", "Cafe"...).
enum TableCategory: String, CaseIterable, Identifiable, Codable {
    case pizza, sushi, cafe, student, tacos, ramen, burgers, asian, coWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pizza: return "Pizza"
        case .sushi: return "Sushi"
        case .cafe: return "Cafe"
        case .student: return "Student Eats"
        case .tacos: return "Tacos"
        case .ramen: return "Ramen"
        case .burgers: return "Burgers"
        case .asian: return "Asian"
        case .coWork: return "Co-Work"
        }
    }

    /// Name of the food photo in Assets.xcassets (Dashboard, Search, Map, Shake).
    /// Some categories share a photo (Student Eats uses the pizza photo, like the design).
    var photoName: String {
        switch self {
        case .pizza, .student: return "food_pizza"
        case .sushi, .asian: return "food_sushi"
        case .tacos: return "food_tacos"
        case .cafe: return "food_cafe"
        case .coWork: return "food_cowork"
        case .ramen: return "food_ramen"
        case .burgers: return "food_burgers"   // no photo yet -> emoji tile
        }
    }

    /// The bigger photos used on the Guest feed (prototype Figure 5).
    /// If a category has no guest photo, the normal food photo is used.
    var guestPhotoName: String {
        switch self {
        case .pizza, .student: return "guest_pizza"
        case .tacos: return "guest_tacos"
        case .cafe, .coWork: return "guest_cafe"
        default: return photoName
        }
    }

    /// Emoji used on chips (and as the picture when there is no photo)
    var emoji: String {
        switch self {
        case .pizza: return "🍕"
        case .sushi: return "🍣"
        case .cafe: return "☕️"
        case .student: return "🎓"
        case .tacos: return "🌮"
        case .ramen: return "🍜"
        case .burgers: return "🍔"
        case .asian: return "🥢"
        case .coWork: return "💻"
        }
    }
}

/// Dietary preference chips in Settings ("Vegetarian", "Halal"...).
enum DietaryTag: String, CaseIterable, Identifiable, Codable {
    case vegetarian, vegan, halal, glutenFree, pescatarian, nutAllergy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .halal: return "Halal"
        case .glutenFree: return "Gluten-Free"
        case .pescatarian: return "Pescatarian"
        case .nutAllergy: return "Nut Allergy"
        }
    }

    var emoji: String {
        switch self {
        case .vegetarian: return "🥦"
        case .vegan: return "🌱"
        case .halal: return "✅"
        case .glutenFree: return "🌾"
        case .pescatarian: return "🐟"
        case .nutAllergy: return "🥜"
        }
    }

    /// An allergy is a "must avoid" rather than a preference.
    var isAllergy: Bool { self == .nutAllergy }
}

/// "Dining Ambience" options on the Taste Profile screen.
enum Ambience: String, CaseIterable, Identifiable, Codable {
    case chillCozy, techFounders, casualWine, quickLively, quietIntrovert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chillCozy: return "Chill & Cozy"
        case .techFounders: return "Tech & Founders"
        case .casualWine: return "Casual Wine & Dine"
        case .quickLively: return "Quick & Lively"
        case .quietIntrovert: return "Quiet & Introvert-Friendly"
        }
    }

    var emoji: String {
        switch self {
        case .chillCozy: return "🛋️"
        case .techFounders: return "🚀"
        case .casualWine: return "🍷"
        case .quickLively: return "⚡️"
        case .quietIntrovert: return "🌿"
        }
    }
}

/// "Favorite Cuisines" list on the Taste Profile screen.
enum Cuisine: String, CaseIterable, Identifiable, Codable {
    case neapolitanPizza, ramenNoodles, streetTacos, healthyBowls, bakeryCoffee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neapolitanPizza: return "Neapolitan Pizza"
        case .ramenNoodles: return "Ramen & Noodles"
        case .streetTacos: return "Street Tacos"
        case .healthyBowls: return "Healthy Bowls"
        case .bakeryCoffee: return "Bakery & Coffee"
        }
    }

    var subtitle: String {
        switch self {
        case .neapolitanPizza: return "Wood-fired, naturally leavened"
        case .ramenNoodles: return "Rich tonkotsu, handmade udon"
        case .streetTacos: return "Birria, authentic salsas"
        case .healthyBowls: return "Organic greens, poke, grains"
        case .bakeryCoffee: return "Specialty pour-overs, pastries"
        }
    }

    var systemImage: String {
        switch self {
        case .neapolitanPizza: return "triangle.fill"
        case .ramenNoodles: return "takeoutbag.and.cup.and.straw"
        case .streetTacos: return "flame"
        case .healthyBowls: return "leaf"
        case .bakeryCoffee: return "cup.and.saucer"
        }
    }

    /// Which table categories match this cuisine (used for recommendations)
    var matchingCategories: [TableCategory] {
        switch self {
        case .neapolitanPizza: return [.pizza]
        case .ramenNoodles: return [.ramen, .asian, .sushi]
        case .streetTacos: return [.tacos]
        case .healthyBowls: return [.cafe, .student]
        case .bakeryCoffee: return [.cafe, .coWork]
        }
    }
}

/// "Dining Style" segmented control on the Taste Profile screen.
enum DiningStyle: String, CaseIterable, Identifiable, Codable {
    case soloExplorer, socialButterfly, smallGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soloExplorer: return "Solo Explorer"
        case .socialButterfly: return "Social Butterfly"
        case .smallGroup: return "Small Group (3–4)"
        }
    }
}
