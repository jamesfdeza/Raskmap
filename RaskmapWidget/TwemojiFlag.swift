//
//  TwemojiFlag.swift
//  Raskmap
//
//  Render country flags using Twitter's Twemoji PNG set.
//  (CC-BY 4.0 — Twitter Inc. / X Corp., now maintained by jdecked/twemoji).
//
//  Three APIs:
//  • `TwemojiFlag(iso2:)`         — render a flag from an ISO-2 code
//  • `FlagLabel(emoji:)`          — drop-in replacement for Text(emoji).font(...);
//                                   parses regional-indicator flag emojis back to
//                                   ISO-2 and renders with Twemoji, or falls
//                                   through to the raw emoji (e.g. "🌐").
//  • `String.flagEmojiToIso2`     — reverse conversion used by FlagLabel
//

import SwiftUI

// MARK: - Primary view (ISO-2 based)

struct TwemojiFlag: View {
    /// ISO-3166-1 alpha-2 code (e.g. "ES", "FR", "US").
    let iso2: String

    /// Target display size in points. Asset is 72px PNG; up to ~24pt @3x looks sharp.
    /// For larger renderings (passport, hero banners) consider SVG/PDF sources.
    var size: CGFloat = 22

    /// Emoji fallback if no Twemoji asset exists (e.g. "-99", disputed territories).
    var fallbackEmoji: String = "🌐"

    var body: some View {
        if let name = Self.assetName(for: iso2),
           UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(Self.accessibilityLabel(for: iso2))
        } else {
            Text(fallbackEmoji)
                .font(.system(size: size))
                .frame(width: size, height: size)
        }
    }

    /// Converts `"ES"` → `"flag_ES"` if the code is a valid 2-letter ISO code.
    static func assetName(for iso2: String) -> String? {
        let trimmed = iso2.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 2,
              trimmed != "-99",
              trimmed.allSatisfy({ $0.isLetter && $0.isASCII })
        else { return nil }
        return "flag_\(trimmed)"
    }

    private static func accessibilityLabel(for iso2: String) -> String {
        Locale(identifier: "es")
            .localizedString(forRegionCode: iso2.uppercased()) ?? iso2.uppercased()
    }
}

// MARK: - Emoji-string → ISO-2 reverse conversion

extension String {
    /// If `self` is a 2-char regional-indicator flag emoji (🇪🇸, 🇫🇷…), returns
    /// its ISO-3166-1 alpha-2 code ("ES", "FR"). Otherwise returns `nil`.
    ///
    /// Not for subdivision flags (🏴󠁧󠁢󠁥󠁮󠁧󠁿 England etc. — tag sequences).
    var flagEmojiToIso2: String? {
        let scalars = Array(self.unicodeScalars)
        guard scalars.count == 2,
              scalars.allSatisfy({ $0.value >= 0x1F1E6 && $0.value <= 0x1F1FF })
        else { return nil }
        let chars: [Character] = scalars.map { s in
            Character(UnicodeScalar(UInt32(0x41) + (s.value - 0x1F1E6))!)
        }
        return String(chars)
    }
}

// MARK: - Drop-in replacement for `Text(emoji).font(.system(size: X))`

/// Renders a flag emoji string with Twemoji if possible, or falls back to the
/// raw emoji as regular text (for "🌐", airplane symbols passed accidentally,
/// subdivision flags not covered, etc.).
///
/// Use this anywhere the app currently does `Text(someFlag).font(.system(size: X))`.
struct FlagLabel: View {
    let emoji: String
    var size: CGFloat = 22

    var body: some View {
        if let iso = emoji.flagEmojiToIso2,
           let asset = TwemojiFlag.assetName(for: iso),
           UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(Locale(identifier: "es")
                    .localizedString(forRegionCode: iso) ?? iso)
        } else {
            // Fallback (🌐, ✈️, banderas no soportadas): mismo bounding box
            // que la versión Twemoji para que las strips de banderas
            // mantengan spacing uniforme entre items.
            Text(emoji)
                .font(.system(size: size))
                .frame(width: size, height: size)
                .minimumScaleFactor(0.5)
        }
    }
}

// MARK: - Multi-flag string renderer

/// Renders a string of concatenated flag emojis (e.g. "🇪🇸🇫🇷🇺🇸") as a horizontal
/// strip of Twemoji images. Individual non-flag characters fall back to raw text.
///
/// Use this anywhere the app currently renders multiple flags as a single
/// `Text(someConcatenatedFlags).font(.system(size:))` — typical in widgets where
/// the data layer encodes upcoming-trip flags as one String.
struct FlagStrip: View {
    let flags: String
    var size: CGFloat = 18
    var spacing: CGFloat = 0

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(flags.enumerated()), id: \.offset) { _, ch in
                FlagLabel(emoji: String(ch), size: size)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            TwemojiFlag(iso2: "ES", size: 32)
            TwemojiFlag(iso2: "XK", size: 32) // Kosovo
            TwemojiFlag(iso2: "TW", size: 32)
            TwemojiFlag(iso2: "FR", size: 32)
            TwemojiFlag(iso2: "NO", size: 32)
        }
        HStack(spacing: 12) {
            FlagLabel(emoji: "🇪🇸", size: 28)
            FlagLabel(emoji: "🇺🇸", size: 28)
            FlagLabel(emoji: "🌐", size: 28)         // fallback: raw emoji
            FlagLabel(emoji: "✈️", size: 28)         // not a flag: raw emoji
        }
    }
    .padding()
}
