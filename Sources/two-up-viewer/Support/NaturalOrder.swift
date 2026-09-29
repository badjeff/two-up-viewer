// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import Foundation

enum NaturalOrder {

    static func isBefore(_ lhs: String, _ rhs: String) -> Bool {
        var l = lhs.unicodeScalars.makeIterator()
        var r = rhs.unicodeScalars.makeIterator()

        var a: Unicode.Scalar? = l.next()
        var b: Unicode.Scalar? = r.next()

        while let x = a, let y = b {
            if isDigit(x), isDigit(y) {
                var lDigits = String(x)
                var rDigits = String(y)
                while let n = l.next() { lDigits.unicodeScalars.append(n) }
                while let n = r.next() { rDigits.unicodeScalars.append(n) }

                let lv = Int(lDigits) ?? 0
                let rv = Int(rDigits) ?? 0
                if lv != rv { return lv < rv }
                if lDigits.count != rDigits.count { return lDigits.count < rDigits.count }
            } else {
                let lx = fold(x), ly = fold(y)
                if lx != ly { return lx < ly }
                if x != y { return x.value < y.value }
            }
            a = l.next()
            b = r.next()
        }

        if a != nil || b != nil { return a == nil }
        return lhs < rhs
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s.value >= 48 && s.value <= 57
    }

    private static func fold(_ s: Unicode.Scalar) -> UInt32 {
        (s.value >= 65 && s.value <= 90) ? s.value + 32 : s.value
    }
}

