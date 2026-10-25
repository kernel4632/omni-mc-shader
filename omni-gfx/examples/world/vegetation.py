"""植被与石块：把树、草叶、花和散落岩石追加进地形顶点数组。

调用位置：`omni-gfx/examples/world/render.py` 生成地形后调用一次。
设计原因与取舍：
    树冠只写露在外面的面：先收集一整团叶方块，再逐格判断六个邻居是否也在叶团里，
    这样一顶帽子从几百个面降到几十个面，阴影与主画面都不用为看不见的面付费。
    草叶用两片交叉四边形而不是实体方块：远看有体积，近看是两面薄片，
    这种做法和游戏里的植物一样，几乎不增加三角形却明显打散地面的纯色块。
    所有位置与形状都由整数哈希决定，换机器、换会话都得到同一片森林。
"""
from __future__ import annotations

from array import array  # 与地形共用紧凑浮点数组。

import terrain  # 复用噪声、列高读取与四边形写入工具。


def _scatter(heights: list[float], size: int, step: int, seed: int, chance: float):
    """按固定网格撒点，返回满足条件的落点与编号。

    网格保证同类植物之间至少有 `step` 米间隔，抖动让它们不排成一条直线。
    条件：落在草地上、坡度不大、高于海面两格以上。
    """
    points = []  # 收集落点。
    for gz in range(2, size - 2, step):  # 逐格扫描。
        for gx in range(2, size - 2, step):  # 当前格。
            roll = terrain._hash3(gx, 3, gz, seed)  # 每个格子的固定随机数。
            if roll > chance:  # 大多数格子不长东西。
                continue
            jitter_x = int((terrain._hash3(gx, 5, gz, seed + 1) - 0.5) * step)  # 横向抖动。
            jitter_z = int((terrain._hash3(gx, 7, gz, seed + 2) - 0.5) * step)  # 纵向抖动。
            x = max(1, min(size - 2, gx + jitter_x))  # 夹进岛内。
            z = max(1, min(size - 2, gz + jitter_z))
            height = terrain.column(heights, size, x, z)  # 落点高度。
            if height < terrain.SEA_LEVEL + 1.0:  # 沙滩与水边不长树。
                continue
            slope = terrain.slope_at(heights, size, x, z)  # 坡度。
            if slope > 1.0:  # 陡坡站不住。
                continue
            points.append((x, z, height, gx, gz))  # 记录落点与格子编号。
    return points  # 结果顺序固定，画面可重复。


def _leaf_color(x: int, y: int, z: int, seed: int) -> tuple[float, float, float]:
    """叶片颜色：同一棵树也有深浅，避免树冠像一块塑料。"""
    value = terrain._hash3(x, y, z, seed)  # 每格叶子的固定随机数。
    depth = 0.19 + value * 0.11  # 绿色分量。
    return (0.045 + value * 0.030, depth, 0.035 + value * 0.028)  # 偏深的叶绿，红光低一点才不会发黄。


def add_tree(vertices: array, x: int, z: int, ground: float, seed: int) -> int:
    """在指定列上长一棵树，返回写入的三角形数。

    树干高四到七格，树冠是三层半径递减的叶团；每团里再按哈希挖掉一部分格子，
    边缘因此不规则，不会像倒扣的碗。
    """
    triangles = 0  # 本棵树写入的三角形。
    trunk = 5 + int(terrain._hash3(x, 11, z, seed) * 4)  # 树干高度。
    wood = (0.24, 0.17, 0.11)  # 树干底色。
    taper = 0.90 + 0.20 * terrain._hash3(x, 13, z, seed)  # 每棵树的粗细倍率。
    triangles += terrain.push_box(vertices, (x + 0.32, ground, z + 0.32),
                                  (0.36 * taper, float(trunk), 0.36 * taper), wood, terrain.MATERIAL_WOOD,
                                  0.95, 0.35)  # 树干略微内缩，树冠不会浮在树干外面。
    top = ground + trunk  # 树冠中心高度。
    leaves = set()  # 叶方块集合，坐标是整数格。
    for layer in range(-2, 4):  # 六层树冠，上下两层收窄。
        radius = 3.1 - abs(layer + 0.4) * 0.62  # 中间最宽。
        if layer > 0:  # 上半部分收得更快。
            radius -= layer * 0.30
        span = int(radius + 0.5)  # 转成整数格数。
        for dz in range(-span, span + 1):  # 逐格填充。
            for dx in range(-span, span + 1):
                distance = (dx * dx + dz * dz) ** 0.5  # 到中心的水平距离。
                if distance > radius + 0.25:  # 圆盘边缘。
                    continue
                roll = terrain._hash3(x + dx, int(top) + layer, z + dz, seed + 9)  # 边缘挖洞用。
                if distance > radius - 0.4 and roll < 0.40:  # 外圈随机缺格，叶团因此不圆滑。
                    continue
                leaves.add((x + dx, int(top) + layer, z + dz))  # 记录叶方块。
    faces = (  # 六个方向的邻居偏移与面法线。
        ((0, 1, 0), (0.0, 1.0, 0.0)),
        ((0, -1, 0), (0.0, -1.0, 0.0)),
        ((0, 0, -1), (0.0, 0.0, -1.0)),
        ((0, 0, 1), (0.0, 0.0, 1.0)),
        ((-1, 0, 0), (-1.0, 0.0, 0.0)),
        ((1, 0, 0), (1.0, 0.0, 0.0)),
    )
    for cx, cy, cz in leaves:  # 逐叶方块写外表面。
        color = _leaf_color(cx, cy, cz, seed + 17)  # 每格自己的颜色。
        sway = min(1.0, 0.35 + (cy - ground) / max(float(trunk), 1.0) * 0.55)  # 越靠上摆得越多。
        for (dx, dy, dz), normal in faces:  # 六个方向。
            if (cx + dx, cy + dy, cz + dz) in leaves:  # 内部面不写。
                continue
            shade = 1.0 if normal[1] > 0.0 else 0.78  # 顶面亮，侧面暗，底面最暗。
            face = (color[0] * shade, color[1] * shade, color[2] * shade)  # 面颜色。
            if normal[1] > 0.0:  # 顶面的四个角。
                corners = [(cx, cy + 1, cz), (cx, cy + 1, cz + 1), (cx + 1, cy + 1, cz + 1), (cx + 1, cy + 1, cz)]
            elif normal[1] < 0.0:  # 底面。
                corners = [(cx, cy, cz), (cx + 1, cy, cz), (cx + 1, cy, cz + 1), (cx, cy, cz + 1)]
            elif normal[2] < 0.0:  # 北面。
                corners = [(cx, cy, cz), (cx, cy + 1, cz), (cx + 1, cy + 1, cz), (cx + 1, cy, cz)]
            elif normal[2] > 0.0:  # 南面。
                corners = [(cx + 1, cy, cz + 1), (cx + 1, cy + 1, cz + 1), (cx, cy + 1, cz + 1), (cx, cy, cz + 1)]
            elif normal[0] < 0.0:  # 西面。
                corners = [(cx, cy, cz + 1), (cx, cy + 1, cz + 1), (cx, cy + 1, cz), (cx, cy, cz)]
            else:  # 东面。
                corners = [(cx + 1, cy, cz), (cx + 1, cy + 1, cz), (cx + 1, cy + 1, cz + 1), (cx + 1, cy, cz + 1)]
            terrain.push_quad(vertices, corners, normal, face, 0.88, terrain.MATERIAL_LEAF, sway)  # 写入。
            triangles += 2  # 每个外表面两个三角形。
    return triangles  # 本棵树的三角形数。


def add_tuft(vertices: array, x: float, z: float, ground: float, height: float, seed: int, color) -> int:
    """写一丛交叉草叶：两片互成直角的四边形，远处看起来有体积。"""
    half = 0.16  # 草叶半宽。
    top = ground + height  # 叶片顶端。
    bright = 0.90 + 0.20 * terrain._hash3(int(x), 23, int(z), seed)  # 每丛亮度不同。
    face = (color[0] * bright, color[1] * bright, color[2] * bright)  # 草叶颜色。
    plane_a = [(x - half, ground, z), (x - half * 0.45, top, z), (x + half * 0.45, top, z + 0.001),
               (x + half, ground, z + 0.001)]  # 第一片。
    plane_b = [(x, ground, z - half), (x + 0.001, top, z - half * 0.45), (x + 0.001, top, z + half * 0.45),
               (x, ground, z + half)]  # 第二片，绕纵轴转九十度。
    terrain.push_quad(vertices, plane_a, (0.0, 0.35, -1.0), face, 0.95, terrain.MATERIAL_BLADE, 1.0)  # 第一片。
    terrain.push_quad(vertices, plane_b, (-1.0, 0.35, 0.0), face, 0.95, terrain.MATERIAL_BLADE, 1.0)  # 第二片。
    return 4  # 两片各两个三角形。


def add_flower(vertices: array, x: float, z: float, ground: float, seed: int) -> int:
    """写一朵小花：细梗加一片朝向天空的花冠。"""
    stem_height = 0.35 + 0.20 * terrain._hash3(int(x), 31, int(z), seed)  # 花梗高度。
    stem = (0.16, 0.30, 0.10)  # 花梗绿色。
    petals = ((0.85, 0.42, 0.16), (0.82, 0.76, 0.24), (0.72, 0.26, 0.44), (0.86, 0.84, 0.78))  # 四种花色。
    color = petals[int(terrain._hash3(int(x), 37, int(z), seed) * 4.0) % 4]  # 固定选一种。
    terrain.push_quad(vertices, [(x - 0.03, ground, z), (x - 0.03, ground + stem_height, z),
                                 (x + 0.03, ground + stem_height, z + 0.001), (x + 0.03, ground, z + 0.001)],
                      (0.0, 0.2, -1.0), stem, 0.95, terrain.MATERIAL_BLADE, 0.6)  # 花梗。
    terrain.push_quad(vertices, [(x - 0.10, ground + stem_height, z + 0.10), (x - 0.10, ground + stem_height + 0.18, z + 0.10),
                                 (x + 0.10, ground + stem_height + 0.18, z - 0.10), (x + 0.10, ground + stem_height, z - 0.10)],
                      (0.0, 1.0, 0.0), color, 0.95, terrain.MATERIAL_FLOWER, 0.8)  # 花冠斜着朝上。
    return 4  # 两片各两个三角形。


def add_bush(vertices: array, x: float, z: float, ground: float, seed: int) -> int:
    """写一丛矮灌木：贴地的一团叶子，填充树与树之间的空地。"""
    triangles = 0  # 本丛写入的三角形。
    leaves = set()  # 叶方块集合。
    for layer in range(0, 3):  # 三层，越往上越小。
        radius = 1.5 - layer * 0.42  # 半径。
        span = int(radius + 0.5)  # 整数格数。
        for dz in range(-span, span + 1):  # 逐格填充。
            for dx in range(-span, span + 1):
                distance = (dx * dx + dz * dz) ** 0.5  # 到中心的水平距离。
                if distance > radius + 0.2:  # 圆盘边缘。
                    continue
                if terrain._hash3(int(x) + dx, layer + 21, int(z) + dz, seed) < 0.22:  # 随机缺口。
                    continue
                leaves.add((int(x) + dx, int(ground) + layer, int(z) + dz))  # 记录叶方块。
    faces = (  # 六个方向的邻居偏移与面法线。
        ((0, 1, 0), (0.0, 1.0, 0.0)),
        ((0, -1, 0), (0.0, -1.0, 0.0)),
        ((0, 0, -1), (0.0, 0.0, -1.0)),
        ((0, 0, 1), (0.0, 0.0, 1.0)),
        ((-1, 0, 0), (-1.0, 0.0, 0.0)),
        ((1, 0, 0), (1.0, 0.0, 0.0)),
    )
    for cx, cy, cz in leaves:  # 逐叶方块写外表面。
        color = _leaf_color(cx, cy, cz, seed + 5)  # 每格自己的颜色。
        for (dx, dy, dz), normal in faces:  # 六个方向。
            if (cx + dx, cy + dy, cz + dz) in leaves:  # 内部面不写。
                continue
            shade = 1.0 if normal[1] > 0.0 else 0.74  # 顶面亮，侧面暗。
            face = (color[0] * shade, color[1] * shade, color[2] * shade)  # 面颜色。
            if normal[1] != 0.0:  # 顶面与底面。
                y = cy + (1.0 if normal[1] > 0.0 else 0.0)
                corners = [(cx, y, cz), (cx, y, cz + 1), (cx + 1, y, cz + 1), (cx + 1, y, cz)]
            elif normal[2] != 0.0:  # 南北面。
                z = cz + (1.0 if normal[2] > 0.0 else 0.0)
                corners = [(cx, cy, z), (cx, cy + 1, z), (cx + 1, cy + 1, z), (cx + 1, cy, z)]
            else:  # 东西面。
                x = cx + (1.0 if normal[0] > 0.0 else 0.0)
                corners = [(x, cy, cz), (x, cy + 1, cz), (x, cy + 1, cz + 1), (x, cy, cz + 1)]
            terrain.push_quad(vertices, corners, normal, face, 0.86, terrain.MATERIAL_LEAF, 0.55)  # 写入。
            triangles += 2  # 每个外表面两个三角形。
    return triangles  # 本丛的三角形数。


def add_vegetation(vertices: array, heights: list[float], size: int) -> int:
    """把树、灌木、草、花与石块追加到顶点数组，返回三角形总数。

    顺序固定：先树（会挡住草），再灌木、草与花，最后石头；
    顶点顺序不影响画面，但固定顺序能让截图完全可重复。
    """
    triangles = 0  # 累计三角形。
    for x, z, height, gx, gz in _scatter(heights, size, 6, 401, 0.34):  # 六米一格，留下草地空隙。
        triangles += add_tree(vertices, x, z, height, 517 + (gx * 31 + gz * 17) % 97)  # 每棵树用不同哈希种子。
    for x, z, height, gx, gz in _scatter(heights, size, 5, 457, 0.24):  # 灌木比树更密。
        triangles += add_bush(vertices, x + 0.5, z + 0.5, height, 463 + gx)  # 一丛灌木。
    tufts = _scatter(heights, size, 2, 613, 0.50)  # 两米一格，草比较密。
    for x, z, height, gx, gz in tufts:  # 逐丛生成。
        if terrain.column(heights, size, x, z) < terrain.SEA_LEVEL + 1.0:  # 水边不长草。
            continue
        blade_height = 0.45 + 0.50 * terrain._hash3(gx, 41, gz, 613)  # 高低不齐。
        color = (0.18 + 0.10 * terrain._hash3(gx, 43, gz, 607), 0.32 + 0.10 * terrain._hash3(gx, 47, gz, 609), 0.10)  # 草色。
        triangles += add_tuft(vertices, x + 0.5, z + 0.5, height, blade_height, 619, color)  # 一丛草。
    flowers = _scatter(heights, size, 7, 701, 0.30)  # 七米一格，花更稀疏。
    for x, z, height, gx, gz in flowers:  # 逐朵生成。
        triangles += add_flower(vertices, x + 0.5, z + 0.5, height, 709)  # 一朵花。
    for x, z, height, gx, gz in _scatter(heights, size, 11, 811, 0.22):  # 散落岩石。
        width = 0.8 + 0.9 * terrain._hash3(gx, 53, gz, 811)  # 石头大小。
        depth = width * (0.8 + 0.4 * terrain._hash3(gx, 59, gz, 811))  # 长宽不等。
        stone = terrain.base_color(terrain.MATERIAL_STONE, height, x, z)  # 石头颜色。
        triangles += terrain.push_box(vertices, (x + 0.5 - width * 0.5, height - 0.25, z + 0.5 - depth * 0.5),
                                      (width, 0.45 + 0.4 * width, depth), stone, terrain.MATERIAL_STONE, 0.9)  # 半埋进地面。
    return triangles  # 全部新增三角形。
