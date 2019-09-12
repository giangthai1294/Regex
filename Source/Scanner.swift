// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Scanner {
    // The index of the next character that wasn't read yet.
    private(set) var i = 0

    private(set) var pattern: [Character]

    init(_ pattern: String) {
        self.pattern = Array(pattern)
    }

    /// Returns the next character in the pattern without consuming it.
    func peak() -> Character? {
        guard i < pattern.endIndex else {
            return nil
        }
        return pattern[i]
    }

    func peak(orThrow error: String) throws -> Character {
        guard let character = peak() else {
            throw Regex.Error(error, 0)
        }
        return character
    }

    // TODO: remove this temp workaround
    func undoRead() {
        i -= 1
    }

    /// Reads the next character in the pattern.
    func readCharacter() -> Character? {
        guard i < pattern.endIndex else {
            return nil
        }
        defer { i += 1}
        return pattern[i]
    }

    /// Reads `n` characters from the string and returns a range
    /// of the these characters.
    @discardableResult
    func read(_ count: Int = 1) -> Range<Int> {
        defer { i += count}
        return i..<i+count
    }

    /// Reads the given string from the pattern and throws the given error if
    /// the string is not found.
    func read(_ s: String, orThrow error: String) throws -> Range<Int> {
        guard let range = read(s) else {
            throw Regex.Error(error, i)
        }
        return range
    }

    /// Reads the string if the prefix of the remainder of the pattern fully
    /// matches it. Returns the range if the operation was successfull.
    func read(_ s: String) -> Range<Int>? {
        let s = Array(s)
        var j = i
        var z = 0
        while z < s.endIndex {
            guard j < pattern.endIndex else {
                return nil
            }
            guard pattern[j] == s[z] else {
                return nil
            }
            j += 1
            z += 1
        }

        defer { i = j }
        return i..<j
    }

    /// Reads the string until reaching the given character. If successfull,
    /// consumes all the characters including the given character.
    func read(until c: Character) -> String? {
        var j = i
        while j < pattern.endIndex {
            if pattern[j] == c {
                defer { i = j + 1 }
                return String(pattern[i..<j])
            }
            j += 1
        }
        return nil
    }

    /// Reads characters while the closure returns true.
    func read(while closure: (Character) -> Bool) -> String {
        var string = ""
        while i < pattern.endIndex, closure(pattern[i]) {
            string.append(pattern[i])
            i += 1
        }
        return string
    }

    /// Reads the character from the end of the pattern if it matches the given
    /// character. Returns `true` if the character was read successfully.
    func readFromEnd(_ c: Character) -> Bool {
        guard pattern.last == c else {
            return false
        }
        pattern.removeLast()
        return true
    }

    /// Reads an integer from the pattern and returns an integer along with its
    /// range in the pattern.
    func readInt() -> (Int, Range<Int>)? {
        let startIndex = i
        let digits = CharacterSet.decimalDigits
        let string = read(while: { digits.contains($0) })
        guard !string.isEmpty else {
            return nil
        }
        guard let int = Int(string) else {
            i = startIndex
            return nil
        }
        return (int, startIndex..<i)
    }

    /// Encountered `[`, read a character group, e.g. [abc], [^ab]
    func readCharacterGroup() throws -> (OldCharacterGroup, Range<Int>) {
        let openingBracketIndex = i
        i += 1

        // Check if the pattern is negative.
        let isNegative = read("^") != nil

        // Make sure that the group is not empty
        guard peak() != "]" else {
            throw Regex.Error("Character group is empty", openingBracketIndex)
        }

        // Read the characters until the group is closed.
        var set = CharacterSet()

        while let c = readCharacter() {
            switch c {
            case "]":
                let group = OldCharacterGroup(isNegative: isNegative, kind: .set(set))
                return (group, openingBracketIndex..<i)
            case "\\":
                guard let c = readCharacter() else {
                    throw Regex.Error("Pattern may not end with a trailing backslash", i-1)
                }
                if let specialSet = try readCharacterClassSpecialCharacter(c) {
                    set.formUnion(specialSet)
                } else {
                    set.insert(c)
                }
            case "/":
                throw Regex.Error("An unescaped delimiter must be escaped with a backslash", i-1)
            default:
                // TODO: tidy up
                if let range = try readCharacterRange(startingWith: c) {
                    if peak() == "]", set.isEmpty { // group ended early
                        i += 1
                        let group = OldCharacterGroup(isNegative: isNegative, kind: .range(range))
                        return (group, openingBracketIndex..<i)
                    }
                    set.insert(charactersIn: range)
                } else {
                    if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 {
                        if peak() == "]", set.isEmpty { // group ended early
                            i += 1
                            let group = OldCharacterGroup(isNegative: isNegative, kind: .range(scalar...scalar))
                            return (group, openingBracketIndex..<i)
                        }
                    }
                    set.insert(c)
                }
            }
        }

        throw Regex.Error("Character group missing closing bracket", openingBracketIndex)
    }

    func readCharacterClassSpecialCharacter(_ c: Character) throws -> CharacterSet? {
        switch c {
        case "d": return CharacterSet.decimalDigits
        case "D": return CharacterSet.decimalDigits.inverted
        case "s": return CharacterSet.whitespaces
        case "S": return CharacterSet.whitespaces.inverted
        case "w": return CharacterSet.word
        case "W": return CharacterSet.word.inverted
        case "p": return try readUnicodeCategory()
        case "P": return try readUnicodeCategory().inverted
        default: return nil
        }
    }

    /// Reads unicode category set, e.g. "P" stands for all punctuation characters.
    func readUnicodeCategory() throws -> CharacterSet {
        let pSymbolIndex = i-1
        guard read("{") != nil else {
            throw Regex.Error("Missing unicode category name", pSymbolIndex)
        }
        guard let name = read(until: "}") else {
            throw Regex.Error("Missing closing bracket for unicode category name", pSymbolIndex)
        }
        guard !name.isEmpty else {
            throw Regex.Error("Unicode category name is empty", pSymbolIndex)
        }
        switch name {
        case "P": return .punctuationCharacters
        case "Lt": return .capitalizedLetters
        case "Ll": return .lowercaseLetters
        case "N": return .nonBaseCharacters
        case "S": return .symbols
        default: throw Regex.Error("Unsupported unicode category '\(name)'", pSymbolIndex)
        }
    }

    /// Reads a character range in a form "a-z", "A-Z", etc. Character range must be provided
    /// in a valid order.
    func readCharacterRange(startingWith lowerBound: Character) throws -> ClosedRange<Unicode.Scalar>? {
        let dashIndex = i
        guard read("-") != nil else {
            return nil // Not a range
        }
        if peak() == "]" {
            i -= 1 // Undo reading '-'
            return nil // Just treat as regular characters
        }
        guard let upperBound = readCharacter() else {
            return nil // The character group seems incomplete, let the upper layer handle the issue
        }
        // TODO: this is probably not the best way to convert these
        guard let lb = Unicode.Scalar(String(lowerBound)),
            let ub = Unicode.Scalar(String(upperBound)) else {
                throw Regex.Error("Unsupported characters in character range", dashIndex)
        }

        guard ub >= lb else {
            throw Regex.Error("Character range is out of order", dashIndex)
        }

        return lb...ub
    }
}

struct OldCharacterGroup {
    let isNegative: Bool
    let kind: Kind

    enum Kind {
        /// A range of unicode scalars. Can be compiled into a more efficient
        /// representation than a character set.
        /// TODO: could potentially also compile multiple ranges like that into
        /// a (sorted) array of ranges? Maybe that's what character set does more
        /// efficiently already, not sure.
        case range(ClosedRange<Unicode.Scalar>)

        /// A predefined character set.
        case set(CharacterSet)
    }
}
