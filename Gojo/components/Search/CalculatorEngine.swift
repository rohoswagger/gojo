import Foundation

/// Hand-rolled recursive-descent calculator evaluated on every keystroke of
/// the search field. Every entry point is designed to never crash or throw
/// uncaught — malformed input (`"2*"`, `"("`, `"hello"`, `"2/0"`, ...) simply
/// yields `nil`.
enum CalculatorEngine {
    /// Evaluates a math expression. Supports `+ - * /`, parentheses, unary
    /// minus, right-associative `^` power, trailing `%` (divide by 100),
    /// decimal numbers, whitespace, and `x`/`×` as multiplication aliases.
    static func evaluate(_ input: String) -> Double? {
        guard input.count <= maxInputLength else { return nil }

        let normalized = normalize(input)
        guard !normalized.isEmpty else { return nil }

        var parser = Parser(characters: Array(normalized))
        guard let value = parser.parseExpression() else { return nil }
        guard parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil }
        return value
    }

    /// Cheap gate for whether `query` is worth handing to `evaluate`: it
    /// must contain at least one digit AND (an operator character or start
    /// with `(`). Plain words never pass this gate.
    static func looksLikeMath(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains(where: { $0.isNumber }) else { return false }
        if trimmed.hasPrefix("(") { return true }

        let operatorChars: Set<Character> = ["+", "-", "*", "/", "^", "%", "x", "X", "×"]
        return trimmed.contains { operatorChars.contains($0) }
    }

    /// Cheap first gate against pathological input before the parser ever
    /// runs; the recursion-depth counter in `Parser` is the real guard.
    private static let maxInputLength = 256

    private static func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "X", with: "*")
            .replacingOccurrences(of: "x", with: "*")
    }

    /// Recursive-descent parser over `Double`. Grammar:
    /// ```
    /// expression := term (('+' | '-') term)*
    /// term       := unary (('*' | '/') unary)*
    /// unary      := ('-' | '+') unary | power
    /// power      := postfix ('^' unary)?             // right-associative;
    ///                                                 // exponent parsed as
    ///                                                 // unary so `2^-3`
    ///                                                 // still works, while
    ///                                                 // `^` binds tighter
    ///                                                 // than a leading `-`
    ///                                                 // (`-2^2 == -4`)
    /// postfix    := primary '%'*                    // trailing percent(s)
    /// primary    := number | '(' expression ')'
    /// ```
    /// Every parse function returns `nil` on malformed input rather than
    /// crashing; `peek`/`advance` are bounds-checked so out-of-range access
    /// is impossible. `depth` bounds the total recursion depth across all
    /// mutually-recursive entry points (parentheses nesting via
    /// `parseExpression`, unary chains via `parseUnary`) so pathological
    /// input (e.g. thousands of nested parens) returns `nil` instead of
    /// overflowing the stack.
    private struct Parser {
        let characters: [Character]
        var index = 0
        var depth = 0

        private static let maxDepth = 64

        var isAtEnd: Bool {
            mutating get {
                skipWhitespace()
                return index >= characters.count
            }
        }

        mutating func parseExpression() -> Double? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else { return nil }

            guard var value = parseTerm() else { return nil }
            while true {
                skipWhitespace()
                guard let op = peek(), op == "+" || op == "-" else { break }
                advance()
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while true {
                skipWhitespace()
                guard let op = peek(), op == "*" || op == "/" else { break }
                advance()
                guard let rhs = parseUnary() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parsePower() -> Double? {
            guard let base = parsePostfix() else { return nil }
            skipWhitespace()
            guard peek() == "^" else { return base }
            advance()
            guard let exponent = parseUnary() else { return nil }
            return pow(base, exponent)
        }

        mutating func parseUnary() -> Double? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else { return nil }

            skipWhitespace()
            if peek() == "-" {
                advance()
                guard let value = parseUnary() else { return nil }
                return -value
            }
            if peek() == "+" {
                advance()
                return parseUnary()
            }
            return parsePower()
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while true {
                skipWhitespace()
                guard peek() == "%" else { break }
                advance()
                value /= 100
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            skipWhitespace()
            guard let c = peek() else { return nil }
            if c == "(" {
                advance()
                guard let value = parseExpression() else { return nil }
                skipWhitespace()
                guard peek() == ")" else { return nil }
                advance()
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skipWhitespace()
            let start = index
            var sawDigit = false
            var sawDot = false
            while let c = peek() {
                if c.isNumber {
                    sawDigit = true
                    advance()
                } else if c == "." && !sawDot {
                    sawDot = true
                    advance()
                } else {
                    break
                }
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return Double(String(characters[start..<index]))
        }

        func peek() -> Character? {
            guard index >= 0, index < characters.count else { return nil }
            return characters[index]
        }

        mutating func advance() {
            guard index < characters.count else { return }
            index += 1
        }

        mutating func skipWhitespace() {
            while let c = peek(), c.isWhitespace {
                advance()
            }
        }
    }
}
