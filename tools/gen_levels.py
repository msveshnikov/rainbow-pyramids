"""Generate the level list for Rainbow Pyramids (assets/levels/levels.json).

Rules (from the design doc):
- every peg is a stack; only the top ring can be taken;
- a ring may go onto an empty peg, or onto a peg whose top ring has the same colour
  AND is larger (pegs always stay pyramids from the bottom up);
- a peg holds at most `cap` rings;
- the level is won when every colour sits on its own peg as a full pyramid N..1.

Levels are random deals (every colour's rings shuffled over `colors` full pegs, plus empty
spare pegs). An A* solver checks each deal: unsolvable deals are thrown away (with these strict
rules most deals on small boards are dead), and the shortest solution found becomes the level's
par for the star rating. Big boards fall back to weighted A* ("~" in the log = not proven optimal).
For each level the deal whose par is closest to the table's target is kept.

Run:  python tools/gen_levels.py            (writes assets/levels/levels.json)
"""
import heapq
import json
import os
import random
import sys
import time

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "levels", "levels.json")

# (colors, sizes, spare pegs, target par) per level; random deals, unsolvable ones rejected
TABLE = []
def add(colors, sizes, spare, targets):
    for t in targets:
        TABLE.append((colors, sizes, spare, t))

add(2, 3, 1, [5, 6])                      # 1-2   tutorial
add(3, 3, 2, [8, 9, 11])                  # 3-5
add(3, 4, 2, [13, 15, 17, 19, 22])        # 6-10
add(4, 4, 2, [17, 19, 21, 23, 26])        # 11-15
add(4, 4, 3, [19, 21, 22, 24, 25])        # 16-20
add(5, 4, 3, [24, 25, 27, 28, 29])        # 21-25
add(6, 4, 3, [28, 30, 33, 36, 40])        # 26-30
add(5, 5, 3, [38, 42, 46, 50, 55])        # 31-35
add(7, 4, 3, [36, 40, 44, 48, 52])        # 36-40
add(6, 5, 3, [50, 55, 60, 66, 72])        # 41-45
add(7, 5, 3, [60, 66, 72, 78, 85])        # 46-50


def ring(c, s):
    return c * 10 + s


def col(r):
    return r // 10


def size(r):
    return r % 10


def solved_state(colors, sizes, spare, rng):
    pegs = [tuple(ring(c, s) for s in range(sizes, 0, -1)) for c in range(colors)]
    pegs += [()] * spare
    rng.shuffle(pegs)
    return pegs


def legal(dst, r, cap):
    if len(dst) >= cap:
        return False
    if not dst:
        return True
    t = dst[-1]
    return col(t) == col(r) and size(t) > size(r)


def moves(state, cap):
    out = []
    for a, A in enumerate(state):
        if not A:
            continue
        r = A[-1]
        moved_to_empty = False
        for b, B in enumerate(state):
            if a == b or not legal(B, r, cap):
                continue
            if not B:
                # all empty pegs are equivalent, and moving a lone ring to another empty peg is useless
                if moved_to_empty or len(A) == 1:
                    continue
                moved_to_empty = True
            out.append((a, b))
    return out


def apply(state, m):
    a, b = m
    s = list(state)
    r = s[a][-1]
    s[a] = s[a][:-1]
    s[b] = s[b] + (r,)
    return s


def settled(peg, sizes):
    """How many rings at the bottom of this peg already form the start of a correct pyramid."""
    if not peg:
        return 0
    c = col(peg[0])
    n = 0
    for i, r in enumerate(peg):
        if col(r) == c and size(r) == sizes - i:
            n += 1
        else:
            break
    return n


def h(state, sizes, total):
    return total - sum(settled(p, sizes) for p in state)


def is_won(state, sizes, total):
    return h(state, sizes, total) == 0


def key(state):
    return tuple(sorted(state))


def astar(start, sizes, cap, total, weight=1.0, node_cap=400000):
    start = list(start)
    h0 = h(start, sizes, total)
    if h0 == 0:
        return []
    cnt = 0
    openq = [(h0 * weight, 0, cnt, start, None)]
    parent = {}
    best_g = {key(start): 0}
    expanded = 0
    while openq:
        f, g, _, s, _ = heapq.heappop(openq)
        k = key(s)
        if best_g.get(k, 1 << 30) < g:
            continue
        expanded += 1
        if expanded > node_cap:
            return None
        for m in moves(s, cap):
            n = apply(s, m)
            nk = key(n)
            ng = g + 1
            if ng >= best_g.get(nk, 1 << 30):
                continue
            best_g[nk] = ng
            parent[nk] = (k, m, s)
            hn = h(n, sizes, total)
            if hn == 0:
                # rebuild path of moves (indices are in the actual, unsorted state of each step)
                path = [m]
                kk = k
                while kk in parent:
                    pk, pm, _ = parent[kk]
                    path.append(pm)
                    kk = pk
                path.reverse()
                return path
            cnt += 1
            heapq.heappush(openq, (ng + hn * weight, ng, cnt, n, None))
    return None


def verify(start, path, sizes, cap, total):
    s = list(start)
    for m in path:
        a, b = m
        if not s[a]:
            return False
        if not legal(s[b], s[a][-1], cap):
            return False
        s = apply(s, m)
    return is_won(s, sizes, total)


def mixing(state):
    n = 0
    for p in state:
        for i in range(1, len(p)):
            if col(p[i]) != col(p[i - 1]) or size(p[i]) > size(p[i - 1]):
                n += 1
    return n


def deal(colors, sizes, spare, rng):
    rings = [ring(c, z) for c in range(colors) for z in range(1, sizes + 1)]
    rng.shuffle(rings)
    pegs = [tuple(rings[i * sizes:(i + 1) * sizes]) for i in range(colors)] + [()] * spare
    rng.shuffle(pegs)
    return pegs


def make_level(idx, params, rng):
    colors, sizes, spare, target = params
    total = colors * sizes
    cap = sizes
    best = None
    t0 = time.time()
    tries = 0
    big = total > 24
    while True:
        tries += 1
        s = deal(colors, sizes, spare, rng)
        if any(settled(p, sizes) >= max(2, sizes - 1) for p in s) or mixing(s) < total // 2:
            continue
        path = astar(s, sizes, cap, total, 1.0, node_cap=30000 if big else 150000)
        optimal = True
        if path is None:
            path = astar(s, sizes, cap, total, 2.5, node_cap=60000 if big else 0)
            optimal = False
        if path is not None:
            assert verify(s, path, sizes, cap, total), "solver produced an invalid path"
            cand = (abs(len(path) - target), -len(path), s, path, optimal)
            if best is None or cand[:2] < best[:2]:
                best = cand
        good = best is not None and best[0] <= max(1, target // 10)
        if (good and tries >= 4) or (best is not None and time.time() - t0 > 40) or tries > 400:
            break
    _, _, s, path, optimal = best
    return {
        "id": idx + 1,
        "colors": colors,
        "sizes": sizes,
        "cap": cap,
        "pegs": [[[col(r), size(r)] for r in p] for p in s],
        "par": len(path),
        "optimal": optimal,
        "solution": [list(m) for m in path],
    }


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 20261118
    levels = []
    for i, params in enumerate(TABLE):
        rng = random.Random(seed * 1000 + i)
        t = time.time()
        lv = make_level(i, params, rng)
        levels.append(lv)
        print(f"level {lv['id']:2d}: {lv['colors']}c x {lv['sizes']}s pegs={len(lv['pegs'])} cap={lv['cap']} "
              f"par={lv['par']}{'' if lv['optimal'] else '~'}  ({time.time() - t:.1f}s)", flush=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "levels": levels}, f, separators=(",", ":"))
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
