import Foundation

enum PointerSource: String, CaseIterable {
    case watch
    case phone
}

/// Four-corner attitude → screen-pixel affine calibration (Foundation-only math).
/// Semantics mirror `tools/mac_pointer_server.py` (`_solve_linear`, `fit_affine_3d`,
/// `PointerState.set_corner` / `rebuild_map` spread guard).
final class CalibrationMap {
    /// Capture order: top row L→R, then bottom row L→R.
    static let cornerOrder: [String] = ["tl", "tr", "bl", "br"]

    /// Minimum wrist-attitude spread (radians) between corners for a usable map.
    static let minCalibSpan: Double = 0.06

    /// Normalized screen UV per corner name.
    static let screenUV: [String: (Double, Double)] = [
        "tl": (0.0, 0.0),
        "tr": (1.0, 0.0),
        "br": (1.0, 1.0),
        "bl": (0.0, 1.0),
    ]

    let x0: Double
    let y0: Double
    let width: Double
    let height: Double
    let displayID: UInt32
    let displayIsMain: Bool

    private struct SourceMap {
        var corners: [String: [Double]] = [:]
        var coeffX: [Double]?
        var coeffY: [Double]?
    }

    private var sourceMaps: [PointerSource: SourceMap] = [:]

    /// Compatibility view of the watch map used by the unchanged parity fixture.
    var corners: [String: [Double]] { corners(for: .watch) }
    var coeffX: [Double]? { sourceMaps[.watch]?.coeffX }
    var coeffY: [Double]? { sourceMaps[.watch]?.coeffY }

    var isCalibrated: Bool {
        isCalibrated(for: .watch)
    }

    /// Capture-order-sorted subset of corners that have been set.
    var calibratedCorners: [String] {
        calibratedCorners(for: .watch)
    }

    init(
        x0: Double,
        y0: Double,
        width: Double,
        height: Double,
        displayID: UInt32 = 0,
        displayIsMain: Bool = false
    ) {
        self.x0 = x0
        self.y0 = y0
        self.width = width
        self.height = height
        self.displayID = displayID
        self.displayIsMain = displayIsMain
    }

    /// Sets a corner pose. Returns `false` for an unknown name. Rebuilds coefficients when all four corners are present.
    @discardableResult
    func setCorner(_ name: String, roll: Double, yaw: Double, pitch: Double) -> Bool {
        setCorner(name, roll: roll, yaw: yaw, pitch: pitch, source: .watch)
    }

    @discardableResult
    func setCorner(
        _ name: String,
        roll: Double,
        yaw: Double,
        pitch: Double,
        source: PointerSource
    ) -> Bool {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.screenUV[key] != nil else { return false }
        var map = sourceMaps[source] ?? SourceMap()
        map.corners[key] = [roll, yaw, pitch]
        sourceMaps[source] = map
        if map.corners.count == 4 {
            rebuildMap(for: source)
        }
        return true
    }

    /// Unclamped affine prediction, or `nil` when not calibrated.
    func predict(roll: Double, yaw: Double, pitch: Double) -> (x: Double, y: Double)? {
        predict(roll: roll, yaw: yaw, pitch: pitch, source: .watch)
    }

    func predict(
        roll: Double,
        yaw: Double,
        pitch: Double,
        source: PointerSource
    ) -> (x: Double, y: Double)? {
        guard let map = sourceMaps[source],
              let cx = map.coeffX,
              let cy = map.coeffY,
              cx.count == 4,
              cy.count == 4
        else {
            return nil
        }
        let x = cx[0] * roll + cx[1] * yaw + cx[2] * pitch + cx[3]
        let y = cy[0] * roll + cy[1] * yaw + cy[2] * pitch + cy[3]
        return (x, y)
    }

    func clear() {
        clear(source: .watch)
    }

    func clear(source: PointerSource) {
        sourceMaps[source] = SourceMap()
    }

    func corners(for source: PointerSource) -> [String: [Double]] {
        sourceMaps[source]?.corners ?? [:]
    }

    func isCalibrated(for source: PointerSource) -> Bool {
        sourceMaps[source]?.coeffX != nil && sourceMaps[source]?.coeffY != nil
    }

    func calibratedCorners(for source: PointerSource) -> [String] {
        let corners = corners(for: source)
        return Self.cornerOrder.filter { corners[$0] != nil }
    }

    var hasAnyCorners: Bool {
        PointerSource.allCases.contains { !corners(for: $0).isEmpty }
    }

    /// Persist independent watch and phone maps. The single-map loader below migrates the old shape.
    func save(to url: URL) throws {
        let display: [String: Any] = [
            "id": displayID,
            "main": displayIsMain,
            "x": x0,
            "y": y0,
            "w": width,
            "h": height,
            "area": width * height,
        ]
        var payload: [String: Any] = [:]
        for source in PointerSource.allCases {
            payload[source.rawValue] = [
                "corners": corners(for: source),
                "display": display,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Load the nested source shape, or migrate a legacy single map into `defaultSource`.
    @discardableResult
    func load(from url: URL, defaultSource: PointerSource = .watch) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        sourceMaps.removeAll()
        var loadedAnyShape = false
        for source in PointerSource.allCases {
            guard let sourceObject = obj[source.rawValue] as? [String: Any],
                  let raw = sourceObject["corners"] as? [String: Any]
            else { continue }
            loadCorners(raw, source: source)
            loadedAnyShape = true
        }
        if loadedAnyShape {
            return true
        }
        guard let raw = obj["corners"] as? [String: Any] else { return false }
        loadCorners(raw, source: defaultSource)
        return true
    }

    private func loadCorners(_ raw: [String: Any], source: PointerSource) {
        var loaded: [String: [Double]] = [:]
        for (key, value) in raw {
            let name = key.lowercased()
            guard Self.screenUV[name] != nil else { continue }
            let nums: [Double]?
            if let arr = value as? [Double] {
                nums = arr
            } else if let arr = value as? [NSNumber] {
                nums = arr.map { $0.doubleValue }
            } else {
                nums = nil
            }
            guard let pose = nums, pose.count >= 3 else { continue }
            loaded[name] = [pose[0], pose[1], pose[2]]
        }
        sourceMaps[source] = SourceMap(corners: loaded)
        rebuildMap(for: source)
    }

    // MARK: - Map rebuild (Python `PointerState.rebuild_map`)

    private func rebuildMap(for source: PointerSource) {
        var map = sourceMaps[source] ?? SourceMap()
        let corners = map.corners
        guard corners.count >= 4 else {
            map.coeffX = nil
            map.coeffY = nil
            sourceMaps[source] = map
            return
        }

        let rolls = corners.values.map { $0[0] }
        let yaws = corners.values.map { $0[1] }
        let dr = (rolls.max() ?? 0) - (rolls.min() ?? 0)
        let dy = (yaws.max() ?? 0) - (yaws.min() ?? 0)
        if dy < Self.minCalibSpan || dr < Self.minCalibSpan {
            map.coeffX = nil
            map.coeffY = nil
            sourceMaps[source] = map
            return
        }

        var samples: [(Double, Double, Double, Double, Double)] = []
        for (name, pose) in corners {
            guard let uv = Self.screenUV[name], pose.count >= 3 else { continue }
            let sx = x0 + uv.0 * (width - 1)
            let sy = y0 + uv.1 * (height - 1)
            samples.append((pose[0], pose[1], pose[2], sx, sy))
        }
        guard samples.count == 4, let fit = Self.fitAffine3D(samples: samples) else {
            map.coeffX = nil
            map.coeffY = nil
            sourceMaps[source] = map
            return
        }
        map.coeffX = fit.0
        map.coeffY = fit.1
        sourceMaps[source] = map
    }

    // MARK: - Math (Python `_solve_linear` / `fit_affine_3d`)

    /// Gaussian elimination with partial pivot. `a` is n×n, `b` length n. Singular if pivot < 1e-12.
    static func solveLinear(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = (0..<n).map { i in a[i] + [b[i]] }
        for col in 0..<n {
            var pivot = col
            var best = abs(m[col][col])
            for r in (col + 1)..<n {
                let v = abs(m[r][col])
                if v > best {
                    best = v
                    pivot = r
                }
            }
            if abs(m[pivot][col]) < 1e-12 {
                return nil
            }
            if pivot != col {
                m.swapAt(col, pivot)
            }
            let div = m[col][col]
            for j in col...(n) {
                m[col][j] /= div
            }
            for r in 0..<n {
                if r == col { continue }
                let factor = m[r][col]
                for j in col...(n) {
                    m[r][j] -= factor * m[col][j]
                }
            }
        }
        return (0..<n).map { m[$0][n] }
    }

    /// Least squares: x,y = f(roll, yaw, pitch, 1). samples: (r, y, p, sx, sy).
    /// Drops pitch column when pitch spread ≤ 1e-4 (coefficient forced to 0). Ridge 1e-9 on ATA diagonal.
    static func fitAffine3D(samples: [(Double, Double, Double, Double, Double)]) -> ([Double], [Double])? {
        let pitches = samples.map { $0.2 }
        let pvar = (pitches.max() ?? 0) - (pitches.min() ?? 0)
        let usePitch = pvar > 1e-4

        func fitCols(_ cols: [Int]) -> ([Double], [Double])? {
            let n = cols.count
            var ata = Array(repeating: Array(repeating: 0.0, count: n), count: n)
            var atx = Array(repeating: 0.0, count: n)
            var aty = Array(repeating: 0.0, count: n)
            for (r, yw, p, sx, sy) in samples {
                let full = [r, yw, p, 1.0]
                let row = cols.map { full[$0] }
                for i in 0..<n {
                    atx[i] += row[i] * sx
                    aty[i] += row[i] * sy
                    for j in 0..<n {
                        ata[i][j] += row[i] * row[j]
                    }
                }
            }
            for i in 0..<n {
                ata[i][i] += 1e-9
            }
            guard let cx = solveLinear(ata, atx), let cy = solveLinear(ata, aty) else {
                return nil
            }
            return (cx, cy)
        }

        if usePitch {
            if let got = fitCols([0, 1, 2, 3]) {
                return got
            }
        }
        // roll, yaw, 1 → expand to 4 coeffs with pitch = 0
        guard let got = fitCols([0, 1, 3]) else {
            return nil
        }
        let (cx3, cy3) = got
        let cx = [cx3[0], cx3[1], 0.0, cx3[2]]
        let cy = [cy3[0], cy3[1], 0.0, cy3[2]]
        return (cx, cy)
    }
}
