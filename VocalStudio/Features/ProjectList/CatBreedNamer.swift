import Foundation

/// Generates a fun, memorable default project name instead of a raw filename or the
/// ugly temp-file name Photos exports give videos (e.g. "IMG_4471" or a UUID).
enum CatBreedNamer {
    private static let breeds = [
        "Abyssinian", "American Bobtail", "American Curl", "American Shorthair",
        "American Wirehair", "Balinese", "Bengal", "Birman", "Bombay", "British Longhair",
        "British Shorthair", "Burmese", "Burmilla", "Chartreux", "Chausie", "Cornish Rex",
        "Devon Rex", "Egyptian Mau", "European Burmese", "Exotic Shorthair", "Havana Brown",
        "Himalayan", "Japanese Bobtail", "Javanese", "Khao Manee", "Korat", "LaPerm",
        "Maine Coon", "Manx", "Munchkin", "Nebelung", "Norwegian Forest", "Ocicat",
        "Oriental Longhair", "Oriental Shorthair", "Persian", "Pixiebob", "Ragamuffin",
        "Ragdoll", "Russian Blue", "Savannah", "Scottish Fold", "Selkirk Rex", "Serengeti",
        "Siamese", "Siberian", "Singapura", "Snowshoe", "Somali", "Sphynx", "Tonkinese",
        "Toyger", "Turkish Angora", "Turkish Van",
    ]

    /// Picks a random breed name, appending " 2", " 3", etc. if it collides with an
    /// existing project title.
    static func randomName(avoiding existingTitles: [String]) -> String {
        let existing = Set(existingTitles)
        let base = breeds.randomElement() ?? "Tabby"
        guard existing.contains(base) else { return base }

        var suffix = 2
        while existing.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }
}
