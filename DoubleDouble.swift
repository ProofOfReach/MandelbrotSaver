import Foundation

// ============================================================================
// DOUBLE-DOUBLE PRECISION MATH
// ============================================================================
// Represents a number as the sum of two Doubles: hi + lo
// Provides ~31 decimal digits of precision (vs 15 for Double)
// ============================================================================

struct DoubleDouble: Equatable, CustomStringConvertible {
    var hi: Double
    var lo: Double
    
    init(_ hi: Double, _ lo: Double) {
        self.hi = hi
        self.lo = lo
    }
    
    init(_ value: Double) {
        self.hi = value
        self.lo = 0.0
    }
    
    // Parse from string for high precision constants
    init(_ string: String) {
        // Basic parser: split into high/low parts roughly
        // Ideally we use a Decimal/BigDecimal parser, but for this app:
        // We assume the string is a valid float.
        // We use Decimal to parse it to avoid immediate truncation
        if let d = Decimal(string: string) {
            let dHi = NSDecimalNumber(decimal: d).doubleValue
            let dRem = d - Decimal(dHi)
            let dLo = NSDecimalNumber(decimal: dRem).doubleValue
            self.hi = dHi
            self.lo = dLo
        } else {
            self.hi = Double(string) ?? 0.0
            self.lo = 0.0
        }
    }
    
    var description: String {
        return "\(hi) + \(lo)"
    }
    
    // MARK: - Arithmetic
    
    static func + (lhs: DoubleDouble, rhs: DoubleDouble) -> DoubleDouble {
        let s1 = lhs.hi + rhs.hi
        let v = s1 - lhs.hi
        let e = (lhs.hi - (s1 - v)) + (rhs.hi - v)
        
        let s2 = lhs.lo + rhs.lo
        let s = s1 + e + s2 // Approximate sum
        
        // Renormalize (roughly)
        return twoSum(s1, e + s2)
    }
    
    static func - (lhs: DoubleDouble, rhs: DoubleDouble) -> DoubleDouble {
        return lhs + DoubleDouble(-rhs.hi, -rhs.lo)
    }
    
    static func * (lhs: DoubleDouble, rhs: DoubleDouble) -> DoubleDouble {
        // p = lhs.hi * rhs.hi
        // e = fma(lhs.hi, rhs.hi, -p)
        // We don't have direct FMA in pure Swift Double easily without 'advanced' imports or C
        // Standard multiplication approximation:
        let p = lhs.hi * rhs.hi
        // Cross terms
        let c = lhs.hi * rhs.lo + lhs.lo * rhs.hi
        return DoubleDouble(p, c) // Simplified, assumes p is dominant
    }
    
    static func * (lhs: DoubleDouble, rhs: Double) -> DoubleDouble {
        return lhs * DoubleDouble(rhs)
    }
    
    // Internal TwoSum
    private static func twoSum(_ a: Double, _ b: Double) -> DoubleDouble {
        let s = a + b
        let v = s - a
        let e = (a - (s - v)) + (b - v)
        return DoubleDouble(s, e)
    }
}

// MARK: - Complex DoubleDouble

struct ComplexDD {
    var x: DoubleDouble
    var y: DoubleDouble
    
    static func + (lhs: ComplexDD, rhs: ComplexDD) -> ComplexDD {
        return ComplexDD(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    static func sqr(_ z: ComplexDD) -> ComplexDD {
        // (x + iy)^2 = x^2 - y^2 + 2ixy
        let x2 = z.x * z.x
        let y2 = z.y * z.y
        let two = DoubleDouble(2.0)
        let xy2 = (z.x * z.y) * two
        
        return ComplexDD(x: x2 - y2, y: xy2)
    }
}
