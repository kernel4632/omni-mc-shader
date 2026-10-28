"""照片级测试世界的植被与石块：树干、树枝、树叶卡片、草丛、野花与巨石。

调用位置：
    `omni-gfx/examples/world/render.py` 在地形网格之后调用 `build`；
    返回三组顶点数组：不透明的树干与岩石、带透明通道的树叶、草丛与野花。
调用示例：`groups = build(terrain)`；逐组上传顶点并绘制。

设计原因与取舍：
    树叶不用方块叶团，而是几十张带叶片的透明卡片交叉堆叠。
    方块叶团的轮廓一眼就是体素，透明卡片在逆光时能透出层次，边缘也自然。
    草叶同样用卡片：一张卡片是一小丛，近看每片叶子有独立渐变，远看连成草甸。
    树干、树枝用锥形圆管，岩石用细分二十面体加噪声位移；两者都带真实扫描纹理，
    粗糙度与法线来自贴图，不靠纯色高光。所有落点与形状由固定哈希决定，画面可重复。
"""
from __future__ import annotations

import math  # 三角函数、平方根与向量运算。
import random  # 固定种子的落点与形状；不使用系统随机。
from array import array  # 紧凑顶点数组。

import terrain  # 高度、坡度与材质编号。

PROPS_FLOATS = 13  # 位置三、法线三、UV 二、颜色三、风摆一、材质一。
CARDS_FLOATS = 12  # 位置三、法线三、UV 二、颜色三、风摆一。

TREE_COUNT = 88  # 中近景树的数量；再多会挡住湖面与山口。
GRASS_COUNT = 16000  # 近景草丛卡片数量。
REED_COUNT = 2600  # 湖岸芦苇数量。
FLOWER_COUNT = 2200  # 近景野花卡片数量。
ROCK_COUNT = 30  # 散落岩石与巨石数量。
GRASS_RADIUS = 42.0  # 草丛只铺在机位周围，远处交给地面贴图。
HERO_TREES = (  # 固定机位附近的主景树，手动摆位保证构图。
    (-48.0, 132.0, 1.00, 0),
    (60.0, 126.0, 0.94, 2),
    (-92.0, 92.0, 1.05, 0),
    (108.0, 82.0, 1.00, 1),
    (-140.0, 10.0, 1.15, 0),
    (150.0, 0.0, 1.08, 2),
    (-60.0, -180.0, 1.20, 0),
    (50.0, -190.0, 1.05, 1),
)


def _append_quad(cards: array, corners, normal, uv_rect, color, sway_bottom: float, sway_top: float) -> None:
    """把一张卡片写成两个三角形，四个角各自带风摆权重。

    `corners` 依次是左下、左上、右上、右下；UV 的纵向零在下、一在上，
    因此草叶与花从底边向上生长，树叶卡片则整张参与摆动。
    """
    u0, v0, u1, v1 = uv_rect
    uvs = ((u0, v0), (u0, v1), (u1, v1), (u1, v0))  # 与四角顺序对应。
    for index in (0, 1, 2, 0, 2, 3):  # 两个三角形。
        point = corners[index]
        uv = uvs[index]
        sway = sway_bottom if index in (0, 3) else sway_top  # 下边少摆、上边多摆。
        cards.extend((point[0], point[1], point[2], normal[0], normal[1], normal[2],
                      uv[0], uv[1], color[0], color[1], color[2], sway))


def _card_corners(center, right, up, half_width: float, half_height: float, bottom_anchor: bool):
    """由中心点、横轴与纵轴构造四个角；`bottom_anchor` 为真时中心在底边。"""
    if bottom_anchor:  # 草叶与花的根在底边。
        base = (center[0] - right[0] * half_width, center[1] - right[1] * half_width,
                center[2] - right[2] * half_width)
        base_r = (center[0] + right[0] * half_width, center[1] + right[1] * half_width,
                  center[2] + right[2] * half_width)
        top = (base[0] + up[0] * half_height * 2.0, base[1] + up[1] * half_height * 2.0,
               base[2] + up[2] * half_height * 2.0)
        top_r = (base_r[0] + up[0] * half_height * 2.0, base_r[1] + up[1] * half_height * 2.0,
                 base_r[2] + up[2] * half_height * 2.0)
        return (base, top, top_r, base_r)
    return (
        (center[0] - right[0] * half_width - up[0] * half_height,
         center[1] - right[1] * half_width - up[1] * half_height,
         center[2] - right[2] * half_width - up[2] * half_height),
        (center[0] - right[0] * half_width + up[0] * half_height,
         center[1] - right[1] * half_width + up[1] * half_height,
         center[2] - right[2] * half_width + up[2] * half_height),
        (center[0] + right[0] * half_width + up[0] * half_height,
         center[1] + right[1] * half_width + up[1] * half_height,
         center[2] + right[2] * half_width + up[2] * half_height),
        (center[0] + right[0] * half_width - up[0] * half_height,
         center[1] + right[1] * half_width - up[1] * half_height,
         center[2] + right[2] * half_width - up[2] * half_height),
    )


def _rotate(vector, angle: float):
    """绕纵轴旋转一个水平向量，卡片朝向因此互不平行。"""
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    return (vector[0] * cos_a - vector[2] * sin_a, vector[1], vector[0] * sin_a + vector[2] * cos_a)


def _tree_color(rng: random.Random) -> tuple[float, float, float]:
    """给一棵树一个整体色调，同一片林子不会全部一个绿色。"""
    hue = rng.random()
    if hue < 0.18:  # 偏黄绿的早秋树。
        return (0.62, 0.60, 0.40)
    if hue < 0.30:  # 深绿针叶或背阴树。
        return (0.38, 0.48, 0.38)
    if hue < 0.38:  # 少量偏红的灌木。
        return (0.58, 0.42, 0.32)
    return (0.46 + rng.random() * 0.14, 0.54 + rng.random() * 0.14, 0.36 + rng.random() * 0.12)


def _add_tube(props: array, path, radii, sides: int, tint, material: int, uv_scale: float) -> int:
    """沿折线生成一根锥形圆管，返回三角形数。

    每个折点生成一圈顶点；相邻两圈之间补侧面四边形。
    切线接近竖直时改用另一个参考轴，避免叉乘退化。
    """
    rings = []
    normals_rings = []
    for index, point in enumerate(path):  # 每个折点算一圈。
        if index == 0:
            tangent = (path[1][0] - point[0], path[1][1] - point[1], path[1][2] - point[2])
        elif index == len(path) - 1:
            tangent = (point[0] - path[index - 1][0], point[1] - path[index - 1][1], point[2] - path[index - 1][2])
        else:
            tangent = (path[index + 1][0] - path[index - 1][0], path[index + 1][1] - path[index - 1][1],
                       path[index + 1][2] - path[index - 1][2])
        length = math.sqrt(sum(component * component for component in tangent))
        tangent = tuple(component / max(length, 1e-6) for component in tangent)
        reference = (0.0, 0.0, 1.0) if abs(tangent[1]) < 0.92 else (1.0, 0.0, 0.0)
        right = (tangent[1] * reference[2] - tangent[2] * reference[1],
                 tangent[2] * reference[0] - tangent[0] * reference[2],
                 tangent[0] * reference[1] - tangent[1] * reference[0])
        right_length = math.sqrt(sum(component * component for component in right))
        right = tuple(component / max(right_length, 1e-6) for component in right)
        up = (right[1] * tangent[2] - right[2] * tangent[1],
              right[2] * tangent[0] - right[0] * tangent[2],
              right[0] * tangent[1] - right[1] * tangent[0])
        ring = []
        normal_ring = []
        for side in range(sides):  # 一圈顶点。
            angle = 2.0 * math.pi * side / sides
            offset = (right[0] * math.cos(angle) + up[0] * math.sin(angle),
                      right[1] * math.cos(angle) + up[1] * math.sin(angle),
                      right[2] * math.cos(angle) + up[2] * math.sin(angle))
            ring.append((point[0] + offset[0] * radii[index], point[1] + offset[1] * radii[index],
                         point[2] + offset[2] * radii[index]))
            normal_ring.append(offset)
        rings.append(ring)
        normals_rings.append(normal_ring)
    triangles = 0
    accumulated = 0.0
    for index in range(len(path) - 1):  # 每两个折点之间一圈侧面。
        segment = (path[index + 1][0] - path[index][0], path[index + 1][1] - path[index][1],
                   path[index + 1][2] - path[index][2])
        accumulated += math.sqrt(sum(component * component for component in segment))
        for side in range(sides):  # 逐侧面写两个三角形。
            next_side = (side + 1) % sides
            p0 = rings[index][side]
            p1 = rings[index][next_side]
            p2 = rings[index + 1][next_side]
            p3 = rings[index + 1][side]
            n0 = normals_rings[index][side]
            n1 = normals_rings[index][next_side]
            n2 = normals_rings[index + 1][next_side]
            n3 = normals_rings[index + 1][side]
            u0 = side / sides * math.pi * 2.0 * uv_scale
            u1 = (side + 1) / sides * math.pi * 2.0 * uv_scale
            v0 = (accumulated - math.sqrt(sum(component * component for component in segment))) * uv_scale
            v1 = accumulated * uv_scale
            for vertex, normal, uv in ((p0, n0, (u0, v0)), (p1, n1, (u1, v0)),
                                       (p2, n2, (u1, v1)), (p0, n0, (u0, v0)),
                                       (p2, n2, (u1, v1)), (p3, n3, (u0, v1))):
                props.extend((vertex[0], vertex[1], vertex[2], normal[0], normal[1], normal[2],
                              uv[0], uv[1], tint[0], tint[1], tint[2], 0.0, float(material)))
            triangles += 2
    return triangles


def _add_tree(props: array, cards: array, x: float, z: float, scale: float, kind: int,
               rng: random.Random, detailed: bool = True) -> tuple[int, int]:
    """在指定位置长一棵树，返回写入的不透明三角形与卡片三角形数量。

    `kind` 零为阔叶大树，一为阔叶小树，二为针叶树。
    阔叶树用几个椭圆叶团，针叶树用逐层收窄的枝叶环；两者都用同一张叶片卡片，
    靠尺寸、密度与颜色区分，近看不会出现两种完全不同的塑料模型。
    """
    ground = terrain.height_at(x, z)
    color = _tree_color(rng)
    broadleaf = kind != 2
    trunk_height = (8.5 + rng.random() * 3.5) * scale if broadleaf else (11.0 + rng.random() * 4.0) * scale
    trunk_radius = (0.38 + rng.random() * 0.16) * scale if broadleaf else (0.26 + rng.random() * 0.10) * scale
    lean_x = (rng.random() - 0.5) * 0.9 * scale
    lean_z = (rng.random() - 0.5) * 0.9 * scale
    path = []
    radii = []
    for level in range(5):  # 五段树干，轻微弯曲。
        t = level / 4.0
        path.append((x + lean_x * t * t, ground - 0.25 + trunk_height * t, z + lean_z * t * t))
        radii.append(trunk_radius * (1.0 - 0.62 * t))
    triangles = _add_tube(props, path, radii, 9, (0.52 + rng.random() * 0.10, 0.42 + rng.random() * 0.08,
                                                     0.30 + rng.random() * 0.06),
                          terrain.MATERIAL_BARK, 0.55)

    # 主枝：从树干中上部向外伸出，托住叶团。
    branch_count = 6 if broadleaf else 4
    canopy_centers = []
    for branch in range(branch_count):
        angle = branch / branch_count * math.pi * 2.0 + rng.uniform(-0.4, 0.4)
        start_t = 0.52 + rng.random() * 0.26
        start = (x + lean_x * start_t * start_t, ground + trunk_height * start_t, z + lean_z * start_t * start_t)
        reach = (2.1 + rng.random() * 2.2) * scale if broadleaf else (1.2 + rng.random() * 1.4) * scale
        rise = (1.2 + rng.random() * 1.4) * scale if broadleaf else (0.4 + rng.random() * 0.8) * scale
        end = (start[0] + math.cos(angle) * reach, start[1] + rise, start[2] + math.sin(angle) * reach)
        middle = ((start[0] + end[0]) * 0.5 + math.cos(angle + 1.2) * 0.3 * scale,
                  (start[1] + end[1]) * 0.5,
                  (start[2] + end[2]) * 0.5 + math.sin(angle + 1.2) * 0.3 * scale)
        branch_radius = trunk_radius * (0.34 - branch * 0.03)
        triangles += _add_tube(props, [start, middle, end],
                               [branch_radius, branch_radius * 0.62, branch_radius * 0.18], 6,
                               (0.48, 0.38, 0.28), terrain.MATERIAL_BARK, 0.8)
        canopy_centers.append((end[0], end[1] + (1.2 if broadleaf else 0.4) * scale,
                               end[2], (2.9 + rng.random() * 1.4) * scale))

    card_triangles = 0
    if broadleaf:  # 阔叶树：几个椭圆叶团拼成不规则树冠。
        canopy_centers.append((x + lean_x, ground + trunk_height * 0.98 + 1.0 * scale,
                               z + lean_z, (4.0 + rng.random() * 1.4) * scale))
        canopy_centers.append((x + lean_x * 0.7, ground + trunk_height * 0.64,
                               z + lean_z * 0.7, (2.6 + rng.random() * 1.0) * scale))
        expanded = []
        if detailed:  # 近景树拆子团，轮廓更碎。
            for center_x, center_y, center_z, radius in canopy_centers:
                expanded.append((center_x, center_y, center_z, radius))
                for _ in range(3):  # 每个主叶团再拆三个偏心子团，树冠边缘不会是一个圆球。
                    offset_x = (rng.random() - 0.5) * radius * 1.35
                    offset_y = (rng.random() - 0.45) * radius * 0.55
                    offset_z = (rng.random() - 0.5) * radius * 1.35
                    expanded.append((center_x + offset_x, center_y + offset_y, center_z + offset_z,
                                     radius * rng.uniform(0.42, 0.68)))
        else:  # 远景树只保留主叶团，用更大的卡片维持轮廓，省掉八成叶片。
            expanded = canopy_centers
        for center_x, center_y, center_z, radius in expanded:
            # 叶团体积内撒卡片；中心密、边缘略疏，轮廓因此毛茸茸的。
            card_count = int(18 + radius * 8) if detailed else int(10 + radius * 5)
            for card in range(card_count):
                theta = rng.random() * math.pi * 2.0
                phi = math.acos(1.0 - 2.0 * rng.random())
                distance = (rng.random() ** 0.42) * radius
                px = center_x + math.sin(phi) * math.cos(theta) * distance
                py = center_y + math.cos(phi) * distance * 0.72
                pz = center_z + math.sin(phi) * math.sin(theta) * distance
                outward = (px - center_x, (py - center_y) * 0.7, pz - center_z)
                outward_length = math.sqrt(sum(component * component for component in outward)) or 1.0
                normal = (outward[0] / outward_length, outward[1] / outward_length + 0.35,
                          outward[2] / outward_length)
                normal_length = math.sqrt(sum(component * component for component in normal)) or 1.0
                normal = tuple(component / normal_length for component in normal)
                facing = rng.random() * math.pi * 2.0
                right = (math.cos(facing), 0.08 * math.sin(facing), math.sin(facing))
                up = (-math.sin(facing) * 0.5, 0.9, math.cos(facing) * 0.5)
                half = (0.62 + rng.random() * 0.46) * scale if detailed else (1.45 + rng.random() * 0.85) * scale
                corners = _card_corners((px, py, pz), right, up, half, half * (0.80 + rng.random() * 0.30), False)
                depth = distance / max(radius, 0.1)  # 叶团内部比外层暗，树冠才有体积。
                shade = (0.58 + rng.random() * 0.26) * (1.0 - depth * 0.30)
                tint = (color[0] * shade, color[1] * shade, color[2] * shade)
                _append_quad(cards, corners, normal, (0.0, 0.0, 1.0, 1.0), tint, 0.35, 1.0)
                card_triangles += 2
    else:  # 针叶树：一层层向外下垂的枝叶环。
        tiers = 7
        for tier in range(tiers):
            t = tier / (tiers - 1)
            tier_y = ground + trunk_height * (0.36 + t * 0.62)
            tier_radius = (3.4 * (1.0 - t) + 0.7) * scale
            cards_in_tier = int(20 - tier * 1.5)
            for card in range(cards_in_tier):
                angle = card / cards_in_tier * math.pi * 2.0 + tier * 0.7 + rng.uniform(-0.2, 0.2)
                px = x + lean_x * t + math.cos(angle) * tier_radius * rng.uniform(0.25, 0.85)
                pz = z + lean_z * t + math.sin(angle) * tier_radius * rng.uniform(0.25, 0.85)
                py = tier_y + rng.uniform(-0.4, 0.4)
                normal = (math.cos(angle) * 0.55, 0.82, math.sin(angle) * 0.55)
                facing = angle + math.pi * 0.5 + rng.uniform(-0.5, 0.5)
                right = (math.cos(facing), 0.15, math.sin(facing))
                up = (-math.sin(facing) * 0.4, 0.9, math.cos(facing) * 0.4)
                half = (0.75 + rng.random() * 0.55) * scale
                corners = _card_corners((px, py, pz), right, up, half, half * 0.55, False)
                shade = 0.74 + rng.random() * 0.22
                tint = (color[0] * shade * 0.82, color[1] * shade * 0.92, color[2] * shade * 0.82)
                _append_quad(cards, corners, normal, (0.0, 0.0, 1.0, 1.0), tint, 0.2, 0.8)
                card_triangles += 2
    return triangles, card_triangles


def _scatter_grass(cards: array, rng: random.Random, count: int, radius: float,
                   reed: bool = False) -> int:
    """在相机附近撒草叶卡片，返回三角形数。

    落点用极坐标抖动；水面以下、陡坡与远处都跳过。
    草丛高度随离岸距离变化，湖边更高更密，形成一条自然的水线。
    """
    camera_x, camera_z = terrain.CAMERA_START
    triangles = 0
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 8:
        attempts += 1
        angle = rng.random() * math.pi * 2.0
        distance = math.sqrt(rng.random()) * radius
        x = camera_x + math.cos(angle) * distance
        z = camera_z + math.sin(angle) * distance
        height = terrain.height_at(x, z)
        if height < terrain.WATER_LEVEL + (0.12 if reed else 0.35):  # 水里不长草；芦苇紧贴水线。
            continue
        if not reed and height > terrain.WATER_LEVEL + 24.0:  # 太高的山坡只保留稀疏草。
            if rng.random() > 0.25:
                continue
        if terrain.slope_at(x, z) > (0.42 if not reed else 0.55):
            continue
        # 小径上不长草，让泥土路面成为一条从机位通向水边的引导线。
        path_x = 5.2 * math.sin((z - 104.0) * 0.045) + 2.4 * math.sin((z - 104.0) * 0.013 + 1.3)
        if not reed and 110.0 < z < 220.0 and abs(x - path_x) < 2.1:
            continue
        if reed:  # 芦苇只长在岸线附近。
            lake = terrain.lake_distance(x, z)
            if lake < 1.00 or lake > 1.14:
                continue
        size = rng.uniform(0.42, 0.88) if not reed else rng.uniform(1.10, 1.85)
        width = size * rng.uniform(0.95, 1.35)
        shade = rng.uniform(0.82, 1.18)
        if reed:  # 芦苇偏黄，和湿润的岸线对比。
            tint = (1.02 * shade, 0.92 * shade, 0.52 * shade)
        else:
            tint = (0.55 * shade, 0.68 * shade, 0.45 * shade)
        for plane in range(2):  # 两张交叉卡片已经能覆盖一圈，第三张在 720p 下只增加填充成本。
            facing = plane / 2.0 * math.pi + rng.uniform(-0.18, 0.18)
            right = (math.cos(facing), 0.0, math.sin(facing))
            up = (0.06 * math.sin(facing), 1.0, -0.06 * math.cos(facing))
            corners = _card_corners((x, height, z), right, up, width * 0.5, size * 0.5, True)
            normal = (0.55 * math.cos(facing), 0.6, 0.55 * math.sin(facing))
            _append_quad(cards, corners, normal, (0.0, 0.0, 1.0, 1.0), tint, 0.0, 1.0)
            triangles += 2
        placed += 1
    return triangles


def _scatter_shrubs(cards: array, rng: random.Random, count: int) -> int:
    """在草坡与林缘撒灌木卡片，打破远处地面过于光滑的绿色。

    只用叶片卡片，不复制完整树；每株两张交叉片，尺寸一米左右，
    近看是灌木，远看只是一团深绿，能有效打散“高尔夫球场”一样的草坡。
    """
    camera_x, camera_z = terrain.CAMERA_START
    triangles = 0
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 8:
        attempts += 1
        angle = rng.random() * math.pi * 2.0
        distance = 18.0 + math.sqrt(rng.random()) * 340.0
        x = camera_x + math.cos(angle) * distance
        z = camera_z + math.sin(angle) * distance
        if terrain.lake_distance(x, z) < 1.12:  # 水里不长灌木。
            continue
        height = terrain.height_at(x, z)
        if height < 0.8 or height > 120.0 or terrain.slope_at(x, z) > 0.38:
            continue
        size = rng.uniform(0.55, 1.65)
        shade = rng.uniform(0.55, 0.95)
        tint = (0.78 * shade, 0.98 * shade, 0.58 * shade)
        for plane in range(2):  # 两张交叉片，远看有体积。
            facing = plane / 2.0 * math.pi + rng.uniform(-0.5, 0.5)
            right = (math.cos(facing), 0.0, math.sin(facing))
            up = (0.0, 1.0, 0.0)
            corners = _card_corners((x, height, z), right, up, size * 0.55, size * 0.55, True)
            _append_quad(cards, corners, (0.2 * math.cos(facing), 0.75, 0.2 * math.sin(facing)),
                         (0.0, 0.0, 1.0, 1.0), tint, 0.0, 1.0)
            triangles += 2
        placed += 1
    return triangles


def _scatter_far_rocks(props: array, rng: random.Random, count: int) -> int:
    """在较远的草坡上撒小石块，让山坡有可读的尺度参照。"""
    camera_x, camera_z = terrain.CAMERA_START
    triangles = 0
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 8:
        attempts += 1
        angle = rng.random() * math.pi * 2.0
        distance = 25.0 + math.sqrt(rng.random()) * 260.0
        x = camera_x + math.cos(angle) * distance
        z = camera_z + math.sin(angle) * distance
        if terrain.lake_distance(x, z) < 1.12:
            continue
        height = terrain.height_at(x, z)
        if height < 0.8 or terrain.slope_at(x, z) > 0.42:
            continue
        triangles += _add_rock(props, x, z, rng.uniform(0.35, 1.4), rng, 1)
        placed += 1
    return triangles



def _scatter_flowers(cards: array, rng: random.Random, count: int) -> int:
    """在近景草地撒野花卡片，保持小尺寸，远看只是颜色点。"""
    camera_x, camera_z = terrain.CAMERA_START
    triangles = 0
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 10:
        attempts += 1
        angle = rng.random() * math.pi * 2.0
        distance = math.sqrt(rng.random()) * 34.0
        x = camera_x + math.cos(angle) * distance
        z = camera_z + math.sin(angle) * distance
        height = terrain.height_at(x, z)
        if height < terrain.WATER_LEVEL + 0.8 or terrain.slope_at(x, z) > 0.32:
            continue
        path_x = 5.2 * math.sin((z - 104.0) * 0.045) + 2.4 * math.sin((z - 104.0) * 0.013 + 1.3)
        if 110.0 < z < 220.0 and abs(x - path_x) < 1.8:
            continue
        size = rng.uniform(0.55, 1.05)
        tint = (1.0, 1.0, 1.0)
        for plane in range(2):  # 两张交叉卡片已经够小。
            facing = plane / 2.0 * math.pi + rng.uniform(-0.4, 0.4)
            right = (math.cos(facing), 0.0, math.sin(facing))
            up = (0.0, 1.0, 0.0)
            corners = _card_corners((x, height, z), right, up, size * 0.5, size * 0.5, True)
            _append_quad(cards, corners, (0.0, 0.7, 0.4), (0.0, 0.0, 1.0, 1.0), tint, 0.0, 1.0)
            triangles += 2
        placed += 1
    return triangles


def _icosphere(subdivisions: int):
    """返回细分二十面体的顶点与三角面，用于生成不规则岩石。"""
    golden = (1.0 + math.sqrt(5.0)) * 0.5
    vertices = [
        (-1, golden, 0), (1, golden, 0), (-1, -golden, 0), (1, -golden, 0),
        (0, -1, golden), (0, 1, golden), (0, -1, -golden), (0, 1, -golden),
        (golden, 0, -1), (golden, 0, 1), (-golden, 0, -1), (-golden, 0, 1),
    ]
    vertices = [tuple(component / math.sqrt(3.0) for component in vertex) for vertex in vertices]
    faces = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]
    for _ in range(subdivisions):
        cache = {}
        new_faces = []

        def midpoint(a, b):
            key = (min(a, b), max(a, b))
            if key in cache:
                return cache[key]
            point = tuple((vertices[a][i] + vertices[b][i]) * 0.5 for i in range(3))
            length = math.sqrt(sum(component * component for component in point))
            index = len(vertices)
            vertices.append(tuple(component / length for component in point))
            cache[key] = index
            return index

        for a, b, c in faces:
            ab = midpoint(a, b)
            bc = midpoint(b, c)
            ca = midpoint(c, a)
            new_faces.extend(((a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)))
        faces = new_faces
    return vertices, faces


def _add_rock(props: array, x: float, z: float, size: float, rng: random.Random, subdivisions: int = 2) -> int:
    """生成一块带噪声位移的岩石，返回三角形数。

    岩石用世界坐标三平面采样贴图，不需要 UV；面法线取平均后仍保留一点硬边，
    近看是粗糙石头而不是光滑橡皮。
    """
    base_vertices, faces = _icosphere(subdivisions)
    ground = terrain.height_at(x, z)
    squash = rng.uniform(0.55, 0.9)  # 多数石头扁一些，像被水冲过。
    stretch = rng.uniform(0.8, 1.4)
    rotation = rng.random() * math.pi * 2.0
    cos_r = math.cos(rotation)
    sin_r = math.sin(rotation)
    tint_value = rng.uniform(0.78, 1.12)
    tint = (tint_value, tint_value, tint_value)
    world_vertices = []
    for vertex in base_vertices:
        noise = _rock_noise(vertex[0] * 2.6 + x, vertex[1] * 2.6 + z, vertex[2] * 2.6 + size)
        radius = size * (0.78 + noise * 0.52)  # 每块石头轮廓不同。
        local_x = vertex[0] * radius * stretch
        local_y = vertex[1] * radius * squash
        local_z = vertex[2] * radius
        world_vertices.append((x + local_x * cos_r - local_z * sin_r,
                               ground + local_y + size * 0.42,
                               z + local_x * sin_r + local_z * cos_r))
    # 先累加相邻面的法线，再归一化；圆滑法线让细分石面不再像低模三角片。
    smooth_normals = [[0.0, 0.0, 0.0] for _ in world_vertices]
    face_normals = []
    for a, b, c in faces:
        p0, p1, p2 = world_vertices[a], world_vertices[b], world_vertices[c]
        edge1 = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
        edge2 = (p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2])
        face_normal = (edge1[1] * edge2[2] - edge1[2] * edge2[1],
                       edge1[2] * edge2[0] - edge1[0] * edge2[2],
                       edge1[0] * edge2[1] - edge1[1] * edge2[0])
        face_normals.append(face_normal)
        for index in (a, b, c):
            smooth_normals[index][0] += face_normal[0]
            smooth_normals[index][1] += face_normal[1]
            smooth_normals[index][2] += face_normal[2]
    for normal in smooth_normals:
        length = math.sqrt(sum(component * component for component in normal))
        normal[0] /= max(length, 1e-8)
        normal[1] /= max(length, 1e-8)
        normal[2] /= max(length, 1e-8)
    triangles = 0
    for face, face_normal in zip(faces, face_normals):
        a, b, c = face
        # 面法线朝向相机外侧，平滑法线偶尔会被邻居拉平；两者混合保留一点硬边。
        length = math.sqrt(sum(component * component for component in face_normal)) or 1.0
        face_dir = [component / length for component in face_normal]
        for index in (a, b, c):
            point = world_vertices[index]
            normal = smooth_normals[index]
            blended = [normal[0] * 0.65 + face_dir[0] * 0.35,
                       normal[1] * 0.65 + face_dir[1] * 0.35,
                       normal[2] * 0.65 + face_dir[2] * 0.35]
            length = math.sqrt(sum(component * component for component in blended)) or 1.0
            props.extend((point[0], point[1], point[2], blended[0] / length, blended[1] / length,
                          blended[2] / length, 0.0, 0.0, tint[0], tint[1], tint[2], 0.0,
                          float(terrain.MATERIAL_ROCK)))
        triangles += 1
    return triangles


def _rock_noise(x: float, y: float, z: float) -> float:
    """岩石位移用的三维值噪声，返回零到一。"""
    ix, iy, iz = int(math.floor(x)), int(math.floor(y)), int(math.floor(z))
    fx, fy, fz = x - ix, y - iy, z - iz
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    fz = fz * fz * (3.0 - 2.0 * fz)

    def corner(dx, dy, dz):
        value = (ix + dx) * 73856093 ^ (iy + dy) * 19349663 ^ (iz + dz) * 83492791
        value = (value ^ (value >> 15)) * 2246822519
        return ((value ^ (value >> 13)) & 0xFFFFFFFF) / 4294967295.0

    c000 = corner(0, 0, 0)
    c100 = corner(1, 0, 0)
    c010 = corner(0, 1, 0)
    c110 = corner(1, 1, 0)
    c001 = corner(0, 0, 1)
    c101 = corner(1, 0, 1)
    c011 = corner(0, 1, 1)
    c111 = corner(1, 1, 1)
    x00 = c000 + (c100 - c000) * fx
    x10 = c010 + (c110 - c010) * fx
    x01 = c001 + (c101 - c001) * fx
    x11 = c011 + (c111 - c011) * fx
    y0 = x00 + (x10 - x00) * fy
    y1 = x01 + (x11 - x01) * fy
    return y0 + (y1 - y0) * fz


def build() -> dict:
    """构建全部植被与石块，返回三组顶点数据与三角形统计。

    返回值键：`props`、`leaves`、`grass`、`flowers` 四组顶点数组，
    以及同名加 `Triangles` 的计数；渲染器据此创建四个顶点数组。
    """
    rng = random.Random(20261028)  # 固定种子。
    props = array("f")
    leaves = array("f")
    grass = array("f")
    flowers = array("f")
    prop_triangles = 0
    leaf_triangles = 0

    placed_trees = []
    for x, z, scale, kind in HERO_TREES:  # 先放主景树，保证构图。
        opaque, leaf = _add_tree(props, leaves, x, z, scale, kind, rng)
        prop_triangles += opaque
        leaf_triangles += leaf
        placed_trees.append((x, z))

    camera_x, camera_z = terrain.CAMERA_START
    # 环湖树线：沿湖盆外缘撒一圈树，对岸因此有一条连续的林带，不像零散盆栽。
    shoreline = 0
    attempts = 0
    while shoreline < 120 and attempts < 8000:
        attempts += 1
        angle = rng.random() * math.pi * 2.0
        factor = rng.uniform(1.22, 1.62)
        x = terrain.LAKE_CENTER[0] + math.cos(angle) * terrain.LAKE_RADIUS[0] * factor
        z = terrain.LAKE_CENTER[1] + math.sin(angle) * terrain.LAKE_RADIUS[1] * factor
        if abs(x) < 38.0 and z > 40.0:  # 留出近岸观景走廊。
            continue
        if terrain.height_at(x, z) < 0.8 or terrain.slope_at(x, z) > 0.34:
            continue
        if (x - camera_x) ** 2 + (z - camera_z) ** 2 < 22.0 ** 2:
            continue
        if any((x - tx) ** 2 + (z - tz) ** 2 < 3.5 ** 2 for tx, tz in placed_trees):
            continue
        scale = rng.uniform(1.20, 2.00)
        kind = 2 if rng.random() < 0.30 else (0 if rng.random() < 0.4 else 1)
        opaque, leaf = _add_tree(props, leaves, x, z, scale, kind, rng, False)
        prop_triangles += opaque
        leaf_triangles += leaf
        placed_trees.append((x, z))
        shoreline += 1
    attempts = 0
    while len(placed_trees) < TREE_COUNT + shoreline and attempts < 6000:  # 其余树按规则撒点。
        attempts += 1
        x = rng.uniform(-260.0, 300.0)
        z = rng.uniform(-250.0, 210.0)
        if abs(x) < 30.0 and -160.0 < z < 140.0:  # 留出湖面与视线走廊。
            continue
        lake = terrain.lake_distance(x, z)
        if lake < 1.12:  # 不站在水里。
            continue
        height = terrain.height_at(x, z)
        if height < 1.0 or height > 110.0:  # 高山裸岩不长树。
            continue
        if terrain.slope_at(x, z) > 0.30:
            continue
        if (x - camera_x) ** 2 + (z - camera_z) ** 2 < 18.0 ** 2:  # 太近会糊住镜头。
            continue
        if abs(x - camera_x) < 32.0 and z < camera_z - 4.0 and z > 60.0:  # 留出正前方湖面视线。
            continue
        if any((x - tx) ** 2 + (z - tz) ** 2 < 8.5 ** 2 for tx, tz in placed_trees):
            continue
        scale = rng.uniform(0.62, 1.15)
        kind = 2 if rng.random() < 0.22 else (0 if rng.random() < 0.35 else 1)
        near = (x - camera_x) ** 2 + (z - camera_z) ** 2 < 95.0 ** 2
        opaque, leaf = _add_tree(props, leaves, x, z, scale, kind, rng, near)
        prop_triangles += opaque
        leaf_triangles += leaf
        placed_trees.append((x, z))

    grass_triangles = _scatter_grass(grass, rng, GRASS_COUNT, GRASS_RADIUS)  # 近景草甸。
    grass_triangles += _scatter_grass(grass, rng, REED_COUNT, 160.0, reed=True)  # 岸边芦苇。
    flower_triangles = _scatter_flowers(flowers, rng, FLOWER_COUNT)
    leaf_triangles += _scatter_shrubs(leaves, rng, 2600)  # 远处灌木，打散光滑草坡。

    rock_triangles = 0
    for index in range(ROCK_COUNT):  # 散落岩石：近景几块，岸边一排。
        if index < 10:  # 近景石块放在两侧，给草地一个尺度参照，不挡住湖面。
            side = -1.0 if index % 2 == 0 else 1.0
            x = camera_x + side * rng.uniform(4.0, 14.0)
            z = camera_z - rng.uniform(8.0, 34.0)
        else:
            angle = rng.random() * math.pi * 2.0
            distance = rng.uniform(40.0, 190.0)
            x = camera_x + math.cos(angle) * distance
            z = camera_z + math.sin(angle) * distance
        if terrain.lake_distance(x, z) < 1.0:  # 水里不放大石头。
            continue
        size = rng.uniform(0.55, 1.65) if index < 10 else rng.uniform(0.4, 1.8)
        subdivisions = 3 if index < 10 else 2
        rock_triangles += _add_rock(props, x, z, size, rng, subdivisions)
    rock_triangles += _scatter_far_rocks(props, rng, 50)  # 草坡上的小石块。

    return {
        "props": props, "propsTriangles": prop_triangles + rock_triangles,
        "leaves": leaves, "leafTriangles": leaf_triangles,
        "grass": grass, "grassTriangles": grass_triangles,
        "flowers": flowers, "flowerTriangles": flower_triangles,
        "trees": len(placed_trees),
    }
