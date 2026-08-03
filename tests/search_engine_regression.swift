//
//  search_engine_regression.swift
//  Regression checks for the search feature's pure engines: the calculator
//  parser and the fuzzy matcher.
//
//  Run via: make test-search (compiles against the sources directly)
//

import CoreGraphics
import Foundation

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fputs("Assertion failed: \(message) — expected nil, got \(String(describing: value))\n", stderr)
        exit(1)
    }
}

func assertClose(_ actual: Double?, _ expected: Double, tolerance: Double, _ message: String) {
    guard let actual else {
        fputs("Assertion failed: \(message) — expected \(expected), got nil\n", stderr)
        exit(1)
    }
    if abs(actual - expected) > tolerance {
        fputs("Assertion failed: \(message) — expected \(expected) ± \(tolerance), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct SearchEngineRegressionRunner {
    static func main() {
        testCalculatorEngine()
        testFuzzyMatcher()
        testFrecencyMath()
        testSearchHotkeyMatch()
        print("search-engine-regression-pass")
    }

    // MARK: - CalculatorEngine

    static func testCalculatorEngine() {
        assertClose(CalculatorEngine.evaluate("2*19"), 38, tolerance: 0.0001, "2*19 = 38")
        assertClose(CalculatorEngine.evaluate("2^10"), 1024, tolerance: 0.0001, "2^10 = 1024")
        assertClose(CalculatorEngine.evaluate("(2+3)*4"), 20, tolerance: 0.0001, "(2+3)*4 = 20")
        assertClose(CalculatorEngine.evaluate("50%"), 0.5, tolerance: 0.0001, "50% = 0.5")
        assertClose(CalculatorEngine.evaluate("2 x 3"), 6, tolerance: 0.0001, "2 x 3 = 6 (x alias)")
        assertClose(CalculatorEngine.evaluate("2 × 3"), 6, tolerance: 0.0001, "2 × 3 = 6 (× alias)")
        assertClose(CalculatorEngine.evaluate("-4 + 10"), 6, tolerance: 0.0001, "unary minus")
        assertClose(CalculatorEngine.evaluate("2^3^2"), 512, tolerance: 0.0001, "right-associative power")
        assertClose(CalculatorEngine.evaluate("  2 + 3  "), 5, tolerance: 0.0001, "whitespace tolerant")
        assertClose(CalculatorEngine.evaluate("2.5 + 2.5"), 5, tolerance: 0.0001, "decimal numbers")

        assertNil(CalculatorEngine.evaluate("2*"), "2* is incomplete")
        assertNil(CalculatorEngine.evaluate("("), "( alone is incomplete")
        assertNil(CalculatorEngine.evaluate("hello"), "hello is not math")
        assertNil(CalculatorEngine.evaluate("2/0"), "division by zero")
        assertNil(CalculatorEngine.evaluate("2 2"), "two numbers with no operator")
        assertNil(CalculatorEngine.evaluate("2)"), "unbalanced closing paren")
        assertNil(CalculatorEngine.evaluate(""), "empty input")
        assertNil(CalculatorEngine.evaluate("   "), "whitespace-only input")

        // Unary-minus precedence: `^` binds tighter than a leading `-`.
        assertClose(CalculatorEngine.evaluate("-2^2"), -4, tolerance: 0.0001, "-2^2 = -4")
        assertClose(CalculatorEngine.evaluate("-3^2"), -9, tolerance: 0.0001, "-3^2 = -9")
        assertClose(CalculatorEngine.evaluate("(-2)^2"), 4, tolerance: 0.0001, "(-2)^2 = 4")
        assertClose(CalculatorEngine.evaluate("2^-2"), 0.25, tolerance: 0.0001, "2^-2 = 0.25")
        assertClose(CalculatorEngine.evaluate("2^3^2"), 512, tolerance: 0.0001, "2^3^2 = 512 (right-associative)")
        assertClose(CalculatorEngine.evaluate("-2*-3"), 6, tolerance: 0.0001, "-2*-3 = 6")
        assertClose(CalculatorEngine.evaluate("2+3*4"), 14, tolerance: 0.0001, "2+3*4 = 14")

        // Pathological input must return nil, never crash.
        let deepParens = String(repeating: "(", count: 5000) + "1" + String(repeating: ")", count: 5000)
        assertNil(CalculatorEngine.evaluate(deepParens), "5000 nested parens returns nil without crashing")
        let tooLong = String(repeating: "1+", count: 200) + "1"
        assertTrue(tooLong.count > 256, "sanity check that the garbage string exceeds the length cap")
        assertNil(CalculatorEngine.evaluate(tooLong), "input over 256 chars returns nil")

        // Exactly-at-cap / cap+1 boundary. The cap is 256 (mirrored here since
        // `maxInputLength` is private to CalculatorEngine.swift); a run of
        // "1"s is a single valid number of any length, so it pins the
        // boundary exactly without needing a well-formed operator chain.
        let inputLengthCap = 256
        let atCap = String(repeating: "1", count: inputLengthCap)
        assertTrue(atCap.count == inputLengthCap, "sanity check: exactly-at-cap string has cap length")
        assertTrue(CalculatorEngine.evaluate(atCap) != nil, "exactly-at-cap input evaluates non-nil")
        let overCap = String(repeating: "1", count: inputLengthCap + 1)
        assertNil(CalculatorEngine.evaluate(overCap), "cap+1 input returns nil")

        // Multiple trailing percents chain: `50%%` == (50 / 100) / 100.
        assertClose(CalculatorEngine.evaluate("50%%"), 0.005, tolerance: 0.0001, "50%% = 0.005 (chained percent)")

        assertNil(CalculatorEngine.evaluate("(2/0)"), "parenthesized division by zero returns nil")
        assertClose(CalculatorEngine.evaluate("10-2-3"), 5, tolerance: 0.0001, "10-2-3 = 5 (left-associative)")
        assertClose(CalculatorEngine.evaluate("100/10/2"), 5, tolerance: 0.0001, "100/10/2 = 5 (left-associative)")

        assertTrue(CalculatorEngine.looksLikeMath("2*19"), "2*19 looks like math")
        assertTrue(CalculatorEngine.looksLikeMath("(2+3)"), "(2+3) looks like math")
        assertTrue(CalculatorEngine.looksLikeMath("50%"), "50% looks like math")
        assertTrue(!CalculatorEngine.looksLikeMath("hello"), "hello does not look like math")
        assertTrue(!CalculatorEngine.looksLikeMath("box"), "box does not look like math")
        assertTrue(!CalculatorEngine.looksLikeMath(""), "empty does not look like math")
    }

    // MARK: - FuzzyMatcher

    static func testFuzzyMatcher() {
        assertTrue(FuzzyMatcher.score(query: "vsc", in: "Visual Studio Code") != nil,
                   "vsc matches Visual Studio Code")
        assertNil(FuzzyMatcher.score(query: "vsc", in: "Terminal"),
                  "vsc does not match Terminal")

        assertNil(FuzzyMatcher.score(query: "zzz", in: "Safari"), "non-subsequence does not match")
        assertNil(FuzzyMatcher.score(query: "abc", in: ""), "empty candidate never matches")
        assertNil(FuzzyMatcher.score(query: "", in: "Safari"), "empty query never matches")

        // Prefix matches should outrank scattered matches of the same query.
        let prefixScore = FuzzyMatcher.score(query: "saf", in: "Safari")
        let scatteredScore = FuzzyMatcher.score(query: "saf", in: "Some App Folder")
        assertTrue(prefixScore != nil && scatteredScore != nil, "both are valid subsequence matches")
        assertTrue(prefixScore! > scatteredScore!, "prefix run beats scattered subsequence")

        // Exact-prefix bonus is large and only applies to real prefixes.
        assertTrue(FuzzyMatcher.exactPrefixBonus(query: "saf", candidate: "Safari") > 0,
                   "case-insensitive exact prefix gets a bonus")
        assertTrue(FuzzyMatcher.exactPrefixBonus(query: "SAF", candidate: "safari") > 0,
                   "prefix bonus is case-insensitive")
        assertTrue(FuzzyMatcher.exactPrefixBonus(query: "afa", candidate: "Safari") == 0,
                   "non-prefix match gets no bonus")
    }

    // MARK: - FrecencyMath

    static func testFrecencyMath() {
        let halfLifeDays = 14.0
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let oneHalfLifeLater = base.addingTimeInterval(halfLifeDays * 86_400)
        let twoHalfLivesLater = base.addingTimeInterval(2 * halfLifeDays * 86_400)

        // Halves at exactly one half-life.
        let atZero = FrecencyMath.frecency(launchCount: 10, lastLaunchedAt: base, now: base, halfLifeDays: halfLifeDays)
        assertClose(atZero, 10, tolerance: 0.0001, "frecency at elapsed=0 equals raw count")
        let atOneHalfLife = FrecencyMath.frecency(
            launchCount: 10, lastLaunchedAt: base, now: oneHalfLifeLater, halfLifeDays: halfLifeDays
        )
        assertClose(atOneHalfLife, 5, tolerance: 0.0001, "frecency halves at exactly one half-life")
        let atTwoHalfLives = FrecencyMath.frecency(
            launchCount: 10, lastLaunchedAt: base, now: twoHalfLivesLater, halfLifeDays: halfLifeDays
        )
        assertClose(atTwoHalfLives, 2.5, tolerance: 0.0001, "frecency quarters at two half-lives")

        // launchCount 0 -> 0.
        let zeroCount = FrecencyMath.frecency(launchCount: 0, lastLaunchedAt: base, now: base, halfLifeDays: halfLifeDays)
        assertClose(zeroCount, 0, tolerance: 0.0001, "launchCount 0 yields frecency 0")

        // lastLaunchedAt distantPast -> ~0.
        let distantPastFrecency = FrecencyMath.frecency(
            launchCount: 100, lastLaunchedAt: Date.distantPast, now: base, halfLifeDays: halfLifeDays
        )
        assertClose(distantPastFrecency, 0, tolerance: 0.0001, "distantPast lastLaunchedAt decays to ~0")

        // Monotonically decreasing over time.
        let earlier = FrecencyMath.frecency(
            launchCount: 10, lastLaunchedAt: base, now: base.addingTimeInterval(86_400), halfLifeDays: halfLifeDays
        )
        let later = FrecencyMath.frecency(
            launchCount: 10, lastLaunchedAt: base, now: base.addingTimeInterval(2 * 86_400), halfLifeDays: halfLifeDays
        )
        assertTrue(earlier > later, "frecency strictly decreases as elapsed time increases")

        // Count scaling is linear.
        let tenCount = FrecencyMath.frecency(
            launchCount: 10, lastLaunchedAt: base, now: oneHalfLifeLater, halfLifeDays: halfLifeDays
        )
        let twentyCount = FrecencyMath.frecency(
            launchCount: 20, lastLaunchedAt: base, now: oneHalfLifeLater, halfLifeDays: halfLifeDays
        )
        assertClose(twentyCount, tenCount * 2, tolerance: 0.0001, "frecency scales linearly with launchCount")
    }

    // MARK: - SearchHotkeyMatch

    static func testSearchHotkeyMatch() {
        let spaceKeyCode: Int64 = 49
        let tabKeyCode: Int64 = 48

        assertTrue(SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: .maskCommand),
                   "keycode 49 + cmd matches")

        assertTrue(!SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: [.maskCommand, .maskShift]),
                   "cmd+shift+space does not match")
        assertTrue(!SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: [.maskCommand, .maskAlternate]),
                   "cmd+option+space does not match")
        assertTrue(!SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: .maskControl),
                   "ctrl+space (no cmd) does not match")
        assertTrue(!SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: []),
                   "bare space does not match")
        assertTrue(!SearchHotkeyMatch.isCommandSpace(keyCode: tabKeyCode, flags: .maskCommand),
                   "keycode 48 (tab) + cmd does not match")

        // Caps-lock / fn / numpad flag noise combined with cmd+space still matches.
        let noisyFlags: CGEventFlags = [.maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad]
        assertTrue(SearchHotkeyMatch.isCommandSpace(keyCode: spaceKeyCode, flags: noisyFlags),
                   "cmd+space with caps-lock/fn/numpad noise still matches")
    }
}
