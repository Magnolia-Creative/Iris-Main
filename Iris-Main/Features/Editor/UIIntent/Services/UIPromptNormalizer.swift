import Foundation
import NaturalLanguage

enum UIPromptNormalizer {
    static func normalize(_ prompt: String) -> NormalizedEditorUIPrompt {
        let original = prompt
        var working = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        working = expandContractions(in: working)
        working = normalizedPunctuation(in: working)
        working = collapsedWhitespace(in: working)

        let replacementResult = applyCanonicalPhraseReplacements(to: working)
        let normalized = replacementResult.text
        let tokens = EditorUIPromptTokenizer.tokens(in: normalized)
        let numericTokens = tokens.filter { token in
            token.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil
        }

        return NormalizedEditorUIPrompt(
            originalText: original,
            normalizedText: normalized,
            tokens: tokens,
            bigrams: ngrams(tokens: tokens, size: 2),
            trigrams: ngrams(tokens: tokens, size: 3),
            numericTokens: numericTokens,
            canonicalPhraseReplacements: replacementResult.replacements
        )
    }

    private static func expandContractions(in text: String) -> String {
        let replacements: [(String, String)] = [
            ("can't", "can not"),
            ("won't", "will not"),
            ("don't", "do not"),
            ("doesn't", "does not"),
            ("isn't", "is not"),
            ("aren't", "are not"),
            ("it's", "it is"),
            ("that's", "that is"),
            ("there's", "there is"),
            ("i'm", "i am"),
            ("i'd", "i would"),
            ("i'll", "i will"),
            ("you're", "you are")
        ]

        return replacements.reduce(text) { partial, replacement in
            partial.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }

    private static func normalizedPunctuation(in text: String) -> String {
        text
            .replacingOccurrences(of: "[^a-z0-9:%\\. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\d)\.(?!\d)"#, with: " ", options: .regularExpression)
    }

    private static func collapsedWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applyCanonicalPhraseReplacements(
        to text: String
    ) -> (text: String, replacements: [UIIntentPhraseReplacement]) {
        let replacements: [(String, String)] = [
            ("more room", "expanded"),
            ("more space", "expanded"),
            ("bigger", "expanded"),
            ("larger", "expanded"),
            ("less room", "compressed"),
            ("less space", "compressed"),
            ("smaller", "compressed"),
            ("bring back", "show"),
            ("open up", "show"),
            ("close out", "hide"),
            ("get rid of", "hide"),
            ("cleaner workspace", "clean workspace"),
            ("less cluttered", "clean workspace")
        ]

        var result = text
        var applied: [UIIntentPhraseReplacement] = []
        for (source, canonical) in replacements {
            guard result.contains(source) else { continue }
            result = result.replacingOccurrences(of: source, with: canonical)
            applied.append(UIIntentPhraseReplacement(source: source, canonical: canonical))
        }

        return (collapsedWhitespace(in: result), applied)
    }

    private static func ngrams(tokens: [String], size: Int) -> [String] {
        guard size > 1, tokens.count >= size else { return [] }
        return (0...(tokens.count - size)).map { index in
            tokens[index..<(index + size)].joined(separator: " ")
        }
    }
}

enum EditorUIPromptTokenizer {
    static func tokens(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                tokens.append(token)
            }
            return true
        }

        if tokens.isEmpty {
            return text.split(separator: " ").map(String.init)
        }
        return tokens
    }
}
