"""程序化体素地形：高度图、方块网格与水面圆盘。

调用位置：`omni-gfx/examples/world/render.py` 在启动时生成一次，之后每帧只绘制。
设计原因与取舍：
    不读取任何外部资源，地形完全由固定种子生成，截图可以重复。
    网格只生成看得见的面：每个方块柱的顶面，以及比邻居高出来的侧墙。
    颜色与遮蔽在 CPU 侧算好，片元阶段只做光照，减少测试世界的着色器分支。
    水面用等比放大的圆盘，近处细、远处覆盖到肉眼地平线之外，天与海不会留下空带。
"""
from __future__ import annotations

import math  # 圆盘环带的三角函数。
from array import array  # 顶点数据用紧凑浮点数组，上传显卡更快。

SEA_LEVEL = 6.0  # 海平面高度，水面平面也放在这里。
MAX_HEIGHT = 24.0  # 地形最高限制，避免山峰穿出云层。


def _hash(ix: int, iz: int, seed: int) -> float:
    """返回一个格点的确定性伪随机数，范围零到一。

    只用整数乘加与位运算，不依赖 Python 的随机模块，换机器也得到同一地形。
    """
    value = ix * 374761393 + iz * 668265263 + seed * 1442695040888963407  # 大常数让相邻格点充分打散。
    value = (value ^ (value >> 13)) * 1274126177  # 异或与乘法混合。
    return ((value ^ (value >> 16)) & 0xFFFFFFFF) / 4294967295.0  # 取低三十二位并归一化。


def _smooth(t: float) -> float:
    """平滑曲线：两端导数为零，让值噪声的格子边界不出现折线。"""
    return t * t * (3.0 - 2.0 * t)  # 三次平滑曲线。


def _value_noise(x: float, z: float, seed: int) -> float:
    """二维值噪声：四个格点哈希后按平滑曲线双线性插值。"""
    ix = int(x // 1)  # 格子左下角。
    iz = int(z // 1)
    fx = _smooth(x - ix)  # 格子内的小数位置。
    fz = _smooth(z - iz)
    a = _hash(ix, iz, seed)  # 四个角点。
    b = _hash(ix + 1, iz, seed)
    c = _hash(ix, iz + 1, seed)
    d = _hash(ix + 1, iz + 1, seed)
    top = a + (b - a) * fx  # 先横向插值。
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fz  # 再纵向插值。


def _fbm(x: float, z: float, seed: int, octaves: int) -> float:
    """分形叠加：每层频率翻倍、权重减半，得到山丘的自然起伏。"""
    total = 0.0  # 累加结果。
    amplitude = 0.5  # 当前层权重。
    frequency = 1.0  # 当前层频率。
    for octave in range(octaves):  # 固定层数，结果可重复。
        total += _value_noise(x * frequency, z * frequency, seed + octave * 101) * amplitude  # 当前层。
        frequency *= 2.0  # 频率翻倍。
        amplitude *= 0.5  # 权重减半。
    return total  # 大致在零到一之间。


def heightmap(size: int, seed: int = 7) -> list[float]:
    """生成一张方形高度图，返回按行排列的高度列表。

    岛屿中心高、四周沉入海面；高度取整到方块，得到体素台阶而不是平滑曲面。
    """
    heights = []  # 按行收集，索引为 z 乘尺寸加 x。
    center = (size - 1) * 0.5  # 岛屿中心。
    for z in range(size):  # 逐行生成。
        for x in range(size):  # 逐列生成。
            nx = (x - center) / center  # 归一化横向距离。
            nz = (z - center) / center  # 归一化纵向距离。
            distance = (nx * nx + nz * nz) ** 0.5  # 到中心的距离。
            falloff = max(0.0, min(1.0, (1.05 - distance) / 0.5))  # 边缘快速降到零。
            falloff = _smooth(falloff)  # 用同一平滑曲线，边缘不突兀。
            hills = _fbm(x * 0.055, z * 0.055, seed, 5)  # 大尺度山丘。
            detail = _fbm(x * 0.16, z * 0.16, seed + 33, 3)  # 小尺度起伏。
            base = 2.0 + hills * 20.0 * falloff + detail * 3.0 * falloff  # 中心最高约二十多米。
            base -= (1.0 - falloff) * 8.0  # 岛外沉到海面以下。
            heights.append(float(max(0.0, min(MAX_HEIGHT, round(base)))))  # 取整成方块高度。
    return heights  # 长度为尺寸的平方。


def water_disc(radius: float, rings: int, segments: int) -> tuple[array, int]:
    """生成一直铺到远处的水面圆盘，返回顶点数组与三角形数量。

    为什么用圆盘而不是方格：方格平面要么近处太粗，要么顶点数暴涨；
    圆盘的环半径按等比增长，近处几米一格、远处几百米一格，肉眼地平线之外的
    海面只占几个像素，却必须存在，否则天与海之间会露出一条空带。
    每顶点只有横向与纵向两个坐标，高度由顶点着色器按海平面填。
    """
    vertices = array("f")  # 每顶点两个浮点。
    inner = 2.0  # 最内圈半径，米。
    ratio = (radius / inner) ** (1.0 / rings)  # 每圈放大的倍数。
    for ring in range(rings):  # 逐圈生成环带。
        near_radius = inner * (ratio ** ring)  # 内圈半径。
        far_radius = near_radius * ratio  # 外圈半径。
        for segment in range(segments):  # 环向分段。
            angle0 = 2.0 * math.pi * segment / segments  # 当前角度。
            angle1 = 2.0 * math.pi * (segment + 1) / segments  # 下一个角度。
            corners = (
                (math.cos(angle0) * near_radius, math.sin(angle0) * near_radius),  # 内圈起点。
                (math.cos(angle1) * near_radius, math.sin(angle1) * near_radius),  # 内圈终点。
                (math.cos(angle1) * far_radius, math.sin(angle1) * far_radius),  # 外圈终点。
                (math.cos(angle0) * far_radius, math.sin(angle0) * far_radius),  # 外圈起点。
            )
            for index in (0, 1, 2, 0, 2, 3):  # 两个三角形共六个顶点。
                vertices.extend(corners[index])  # 写入横向与纵向坐标。
    return vertices, rings * segments * 2  # 三角形数量。


def _top_color(height: float, variation: float, slope: float) -> tuple[float, float, float]:
    """按高度、坡度和位置变化选择顶面颜色。

    海滩用沙色、高山与陡坡用岩石、其余用带深浅变化的草色。
    """
    if height <= SEA_LEVEL + 1.0:  # 海平面附近是沙滩。
        return (0.70 + variation * 0.08, 0.60 + variation * 0.07, 0.40 + variation * 0.05)
    if height > 17.0 or slope >= 3.0:  # 高山与陡坡露出岩石。
        return (0.38 + variation * 0.08, 0.38 + variation * 0.08, 0.40 + variation * 0.08)
    return (0.19 + variation * 0.06, 0.35 + variation * 0.09, 0.15 + variation * 0.05)  # 草地。


def _add_quad(vertices: array, corners: list[tuple[float, float, float]], normal: tuple[float, float, float],
              color: tuple[float, float, float], occlusion: float) -> None:
    """把一个四边形拆成两个三角形追加到顶点数组。

    `corners` 按逆时针或顺时针给出四个角，两个三角形共用零号和二号角。
    每个顶点十个浮点：位置、法线、颜色、遮蔽，与顶点着色器的布局一致。
    """
    order = (0, 1, 2, 0, 2, 3)  # 两个三角形的顶点顺序。
    for index in order:  # 依次写入六个顶点。
        x, y, z = corners[index]  # 当前角点。
        vertices.extend((x, y, z, normal[0], normal[1], normal[2], color[0], color[1], color[2], occlusion))  # 十个通道。


def build_mesh(heights: list[float], size: int) -> tuple[array, int]:
    """由高度图生成地形三角形，返回顶点数组与三角形数量。

    只生成顶面与露出的侧墙；侧墙高度等于与邻居的高度差，形成方块台阶。
    """
    vertices = array("f")  # 交错顶点数据。
    triangles = 0  # 统计三角形数量，写进性能记录。
    for z in range(size):  # 逐列生成方块柱。
        for x in range(size):  # 当前方块柱。
            height = heights[z * size + x]  # 当前高度。
            neighbors = (  # 四个方向的邻居高度，越界按零处理。
                heights[z * size + x - 1] if x > 0 else 0.0,
                heights[z * size + x + 1] if x + 1 < size else 0.0,
                heights[(z - 1) * size + x] if z > 0 else 0.0,
                heights[(z + 1) * size + x] if z + 1 < size else 0.0,
            )
            slope = max(abs(height - neighbor) for neighbor in neighbors)  # 最大高差决定陡坡。
            variation = _hash(x, z, 91)  # 每个方块固定的颜色扰动。
            color = _top_color(height, variation, slope)  # 顶面颜色。
            occlusion = 0.72 + 0.28 * max(0.0, 1.0 - slope / 4.0)  # 陡坡边缘略暗。
            _add_quad(vertices, [  # 顶面四个角。
                (x, height, z),
                (x, height, z + 1),
                (x + 1, height, z + 1),
                (x + 1, height, z),
            ], (0.0, 1.0, 0.0), color, occlusion)
            triangles += 2  # 顶面两个三角形。
            wall_color = (color[0] * 0.50 + 0.16, color[1] * 0.50 + 0.14, color[2] * 0.50 + 0.11)  # 侧墙混入泥土与岩石色。
            for direction, neighbor in enumerate(neighbors):  # 四个方向分别补侧墙。
                if neighbor >= height:  # 邻居不低就没有露出的墙。
                    continue
                low = neighbor  # 墙底高度。
                if direction == 0:  # 西侧。
                    corners = [(x, low, z), (x, height, z), (x, height, z + 1), (x, low, z + 1)]
                    normal = (-1.0, 0.0, 0.0)
                elif direction == 1:  # 东侧。
                    corners = [(x + 1, low, z), (x + 1, low, z + 1), (x + 1, height, z + 1), (x + 1, height, z)]
                    normal = (1.0, 0.0, 0.0)
                elif direction == 2:  # 北侧。
                    corners = [(x, low, z), (x + 1, low, z), (x + 1, height, z), (x, height, z)]
                    normal = (0.0, 0.0, -1.0)
                else:  # 南侧。
                    corners = [(x, low, z + 1), (x, height, z + 1), (x + 1, height, z + 1), (x + 1, low, z + 1)]
                    normal = (0.0, 0.0, 1.0)
                _add_quad(vertices, corners, normal, wall_color, 0.68)  # 侧墙统一略暗。
                triangles += 2  # 每面墙两个三角形。
    return vertices, triangles  # 顶点与三角形统计。


    return vertices, rings * segments * 2  # 三角形数量。
