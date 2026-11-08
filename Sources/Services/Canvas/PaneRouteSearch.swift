import Foundation

/// Orthogonal visibility grid around expanded pane borders. This is geometry only: routes never
/// move windows, change z-order or intercept input. A fully covered endpoint has no visible route.
enum PaneRouteSearch {
    private static let clearance: CGFloat = 3
    private static let maximumObstacles = 128
    private static let maximumNodes = 16_384
    private struct Port {
        let edge: CGPoint
        let outside: CGPoint
    }

    static func points(source: CGRect, target: CGRect, obstacles: [CGRect], bounds: CGRect) -> [CGPoint]? {
        guard valid(source), valid(target), valid(bounds), obstacles.count <= maximumObstacles else { return nil }
        let obstacles = obstacles.filter(valid)
        let blocks = obstacles.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        let starts = ports(source, obstacles: obstacles).filter { free($0.outside, blocks: blocks, bounds: bounds) }
        let ends = ports(target, obstacles: obstacles).filter { free($0.outside, blocks: blocks, bounds: bounds) }
        guard !starts.isEmpty, !ends.isEmpty else { return nil }
        let ports = starts + ends
        let xs = Array(
            Set(blocks.flatMap { [$0.minX, $0.maxX] } + ports.map(\.outside.x) + [bounds.minX, bounds.maxX])
        )
        .filter { $0 >= bounds.minX && $0 <= bounds.maxX }.sorted()
        let ys = Array(
            Set(blocks.flatMap { [$0.minY, $0.maxY] } + ports.map(\.outside.y) + [bounds.minY, bounds.maxY])
        )
        .filter { $0 >= bounds.minY && $0 <= bounds.maxY }.sorted()
        let width = xs.count
        guard !ys.isEmpty, width <= maximumNodes / ys.count else { return nil }
        let count = width * ys.count
        func point(_ node: Int) -> CGPoint { CGPoint(x: xs[node % width], y: ys[node / width]) }
        func node(_ p: CGPoint) -> Int? {
            guard let x = xs.firstIndex(of: p.x), let y = ys.firstIndex(of: p.y) else { return nil }
            return y * width + x
        }
        let available = (0..<count).map { free(point($0), blocks: blocks, bounds: bounds) }
        var edges = Array(repeating: [(Int, CGFloat)](), count: count)
        for index in 0..<count where available[index] {
            for next in [index % width + 1 < width ? index + 1 : -1, index + width < count ? index + width : -1]
            where next >= 0 && available[next] {
                let a = point(index)
                let b = point(next)
                guard !blocks.contains(where: { crosses(a, b, interior: $0) }) else { continue }
                let length = abs(a.x - b.x) + abs(a.y - b.y)
                edges[index].append((next, length))
                edges[next].append((index, length))
            }
        }
        // One Dijkstra search handles all exposed start/end ports. Stable ties avoid jitter on repaint.
        var costs = Array(repeating: CGFloat.infinity, count: count)
        var previous = Array(repeating: -1, count: count)
        var roots = Array(repeating: -1, count: count)
        var heap = RouteHeap()
        for (index, port) in starts.enumerated() {
            guard let n = node(port.outside) else { continue }
            costs[n] = 0
            roots[n] = index
            heap.push(node: n, cost: 0)
        }
        let goals = ends.enumerated().compactMap { index, port in node(port.outside).map { ($0, index) } }
        while let current = heap.pop() {
            guard current.cost == costs[current.node] else { continue }
            if let goal = goals.first(where: { $0.0 == current.node }) {
                var indices = [current.node]
                while let last = indices.last, previous[last] >= 0 { indices.append(previous[last]) }
                let start = starts[roots[current.node]]
                return simplify([start.edge] + indices.reversed().map(point) + [ends[goal.1].edge])
            }
            for (next, length) in edges[current.node] {
                let cost = current.cost + length
                guard cost < costs[next] else { continue }
                costs[next] = cost
                previous[next] = current.node
                roots[next] = roots[current.node]
                heap.push(node: next, cost: cost)
            }
        }
        return nil
    }

    private static func ports(_ frame: CGRect, obstacles: [CGRect]) -> [Port] {
        var result: [Port] = []
        // Midpoints of exposed edge intervals also work when another window covers a normal midpoint.
        for vertical in [true, false] {
            for far in [false, true] {
                let fixed = vertical ? (far ? frame.maxX : frame.minX) : (far ? frame.maxY : frame.minY)
                let low = vertical ? frame.minY : frame.minX
                let high = vertical ? frame.maxY : frame.maxX
                var cuts = [low, high]
                for block in obstacles where block != frame {
                    let spans =
                        vertical ? (block.minX...block.maxX).contains(fixed) : (block.minY...block.maxY).contains(fixed)
                    if spans {
                        cuts += [
                            max(low, min(high, vertical ? block.minY : block.minX)),
                            max(low, min(high, vertical ? block.maxY : block.maxX)),
                        ]
                    }
                }
                cuts = Array(Set(cuts)).sorted()
                for (a, b) in zip(cuts, cuts.dropFirst()) where b - a > clearance * 2 {
                    let middle = (a + b) / 2
                    let edge = vertical ? CGPoint(x: fixed, y: middle) : CGPoint(x: middle, y: fixed)
                    let outward = fixed + (far ? clearance : -clearance)
                    let outside = vertical ? CGPoint(x: outward, y: middle) : CGPoint(x: middle, y: outward)
                    guard !obstacles.contains(where: { $0 != frame && crosses(edge, outside, interior: $0) }) else {
                        continue
                    }
                    result.append(Port(edge: edge, outside: outside))
                }
            }
        }
        return result
    }

    static func valid(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0
            && [frame.minX, frame.maxX, frame.minY, frame.maxY, frame.width, frame.height].allSatisfy(\.isFinite)
    }

    private static func free(_ p: CGPoint, blocks: [CGRect], bounds: CGRect) -> Bool {
        p.x >= bounds.minX && p.x <= bounds.maxX && p.y >= bounds.minY && p.y <= bounds.maxY
            && !blocks.contains { p.x > $0.minX && p.x < $0.maxX && p.y > $0.minY && p.y < $0.maxY }
    }

    static func crosses(_ a: CGPoint, _ b: CGPoint, interior r: CGRect) -> Bool {
        if a.x == b.x { return a.x > r.minX && a.x < r.maxX && max(a.y, b.y) > r.minY && min(a.y, b.y) < r.maxY }
        return a.y > r.minY && a.y < r.maxY && max(a.x, b.x) > r.minX && min(a.x, b.x) < r.maxX
    }

    static func simplify(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for p in points where result.last != p {
            if result.count >= 2 {
                let a = result[result.count - 2]
                let b = result[result.count - 1]
                if (a.x == b.x && b.x == p.x) || (a.y == b.y && b.y == p.y) { result.removeLast() }
            }
            result.append(p)
        }
        return result
    }
}

private struct RouteHeap {
    private var entries: [(node: Int, cost: CGFloat)] = []
    mutating func push(node: Int, cost: CGFloat) {
        entries.append((node, cost))
        var index = entries.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard entries[index].cost < entries[parent].cost else { break }
            entries.swapAt(index, parent)
            index = parent
        }
    }
    mutating func pop() -> (node: Int, cost: CGFloat)? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries.removeLast() }
        let first = entries[0]
        entries[0] = entries.removeLast()
        var index = 0
        while index * 2 + 1 < entries.count {
            var child = index * 2 + 1
            if child + 1 < entries.count && entries[child + 1].cost < entries[child].cost { child += 1 }
            guard entries[child].cost < entries[index].cost else { break }
            entries.swapAt(child, index)
            index = child
        }
        return first
    }
}
