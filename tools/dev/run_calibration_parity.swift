import Foundation

// Compile + run:
//   xcrun swiftc 'Pointer Mac/CalibrationMap.swift' tools/dev/run_calibration_parity.swift -o /tmp/calib_parity && /tmp/calib_parity
// (cwd = repo root)

@main
struct CalibrationParityRunner {
    static func main() {
        let fixtureURL = resolveFixtureURL()
        guard let data = try? Data(contentsOf: fixtureURL) else {
            fputs("FAIL: cannot read fixture at \(fixtureURL.path)\n", stderr)
            exit(1)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tolerance = doubleValue(root["tolerance"]) ?? Optional(1e-6),
              let scenarios = root["scenarios"] as? [[String: Any]]
        else {
            fputs("FAIL: invalid fixture schema\n", stderr)
            exit(1)
        }

        var failures = 0
        for scenario in scenarios {
            let name = scenario["name"] as? String ?? "<unnamed>"
            let ok = runScenario(scenario, tolerance: tolerance)
            if ok {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        if failures > 0 {
            fputs("\(failures) scenario(s) failed\n", stderr)
            exit(1)
        }
    }

    static func resolveFixtureURL() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let relative = cwd.appendingPathComponent("tests/fixtures/calibration_parity.json")
        if FileManager.default.fileExists(atPath: relative.path) {
            return relative
        }
        // Walk up from executable path if not launched from repo root.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("tests/fixtures/calibration_parity.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return relative
    }

    static func runScenario(_ scenario: [String: Any], tolerance: Double) -> Bool {
        let name = scenario["name"] as? String ?? "<unnamed>"
        guard let corners = scenario["corners"] as? [String: Any],
              let display = scenario["display"] as? [String: Any],
              let x0 = doubleValue(display["x"]),
              let y0 = doubleValue(display["y"]),
              let w = doubleValue(display["w"]),
              let h = doubleValue(display["h"])
        else {
            fputs("  \(name): missing corners/display\n", stderr)
            return false
        }

        let accepted: Bool
        if let a = scenario["accepted"] as? Bool {
            accepted = a
        } else if let rejected = scenario["expect_rejected"] as? Bool {
            accepted = !rejected
        } else {
            accepted = true
        }

        let map = CalibrationMap(x0: x0, y0: y0, width: w, height: h)
        for cornerName in CalibrationMap.cornerOrder {
            guard let arr = doubleArray(corners[cornerName]), arr.count >= 3 else {
                fputs("  \(name): missing corner \(cornerName)\n", stderr)
                return false
            }
            if !map.setCorner(cornerName, roll: arr[0], yaw: arr[1], pitch: arr[2]) {
                fputs("  \(name): setCorner rejected \(cornerName)\n", stderr)
                return false
            }
        }

        if !accepted {
            if map.isCalibrated {
                fputs("  \(name): expected rejected (isCalibrated == false), got calibrated\n", stderr)
                return false
            }
            return true
        }

        // Accepted: coefficients + predictions within tolerance.
        if !map.isCalibrated {
            fputs("  \(name): expected calibrated, isCalibrated == false\n", stderr)
            return false
        }

        if let expectX = doubleArray(scenario["coeffX"] ?? scenario["coeff_x"]),
           let expectY = doubleArray(scenario["coeffY"] ?? scenario["coeff_y"]),
           let gotX = map.coeffX,
           let gotY = map.coeffY
        {
            if !arraysClose(gotX, expectX, tol: tolerance) {
                fputs("  \(name): coeffX mismatch\n    got \(gotX)\n    exp \(expectX)\n", stderr)
                return false
            }
            if !arraysClose(gotY, expectY, tol: tolerance) {
                fputs("  \(name): coeffY mismatch\n    got \(gotY)\n    exp \(expectY)\n", stderr)
                return false
            }
        } else {
            fputs("  \(name): missing coeffX/coeffY in fixture or map\n", stderr)
            return false
        }

        guard let predictions = scenario["predictions"] as? [[String: Any]] else {
            fputs("  \(name): missing predictions\n", stderr)
            return false
        }

        for (i, pred) in predictions.enumerated() {
            let input: [Double]?
            let expected: [Double]?
            if let pose = doubleArray(pred["pose"]), let pixel = doubleArray(pred["pixel"]) {
                input = pose
                expected = pixel
            } else if let inp = doubleArray(pred["input"]), let exp = doubleArray(pred["expected"]) {
                input = inp
                expected = exp
            } else {
                fputs("  \(name): prediction[\(i)] missing pose/pixel\n", stderr)
                return false
            }
            guard let pose = input, pose.count >= 3, let exp = expected, exp.count >= 2 else {
                fputs("  \(name): prediction[\(i)] bad shape\n", stderr)
                return false
            }
            guard let got = map.predict(roll: pose[0], yaw: pose[1], pitch: pose[2]) else {
                fputs("  \(name): prediction[\(i)] predict returned nil\n", stderr)
                return false
            }
            if abs(got.x - exp[0]) > tolerance || abs(got.y - exp[1]) > tolerance {
                fputs(
                    "  \(name): prediction[\(i)] mismatch\n    got (\(got.x), \(got.y))\n    exp (\(exp[0]), \(exp[1]))\n",
                    stderr
                )
                return false
            }
        }
        return true
    }

    static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    static func doubleArray(_ any: Any?) -> [Double]? {
        if let a = any as? [Double] { return a }
        if let a = any as? [NSNumber] { return a.map { $0.doubleValue } }
        if let a = any as? [Any] {
            var out: [Double] = []
            out.reserveCapacity(a.count)
            for el in a {
                guard let d = doubleValue(el) else { return nil }
                out.append(d)
            }
            return out
        }
        return nil
    }

    static func arraysClose(_ a: [Double], _ b: [Double], tol: Double) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if abs(a[i] - b[i]) > tol { return false }
        }
        return true
    }
}
