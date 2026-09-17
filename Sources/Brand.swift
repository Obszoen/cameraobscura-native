import SwiftUI

/// The app's three accent colors — carried over from the very first version of the app
/// and asked for again by Daniel after the darker single-accent direction from the design
/// canvas: rose is the primary accent, mint the secondary, sky blue a small third note.
/// Used sparingly as accents on the dark viewfinder chrome, not as a full pastel wash.
enum Brand {
    static let rose = Color(red: 0xD9 / 255, green: 0x8A / 255, blue: 0x93 / 255)
    static let mint = Color(red: 0xA6 / 255, green: 0xEB / 255, blue: 0xD1 / 255)
    static let skyBlue = Color(red: 0xAE / 255, green: 0xD0 / 255, blue: 0xFA / 255)
    static let ground = Color(red: 0x13 / 255, green: 0x11 / 255, blue: 0x13 / 255)
    static let paper = Color(red: 0xF5 / 255, green: 0xF1 / 255, blue: 0xEC / 255)
}
