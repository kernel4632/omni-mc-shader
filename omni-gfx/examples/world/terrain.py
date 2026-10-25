"""程序化体素地形：高度图、方块网格、水面圆盘与网格小工具。

调用位置：`omni-gfx/examples/world/render.py` 在启动时生成一次，之后每帧只绘制；
`omni-gfx/examples/world/vegetation.py` 复用本文件的噪声与四边形写入工具。
设计原因与取舍：
    不读取任何外部资源，地形完全由固定种子生成，截图可以重复。
    网格只生成看得见的面：每个方块柱的顶面，以及比邻居高出来的侧墙。
    颜色、材质编号与逐顶点遮蔽在 CPU 侧算好，片元阶段只做光照与细节，
    这样测试世界的着色器保持短小，改画面时不必每次重算整张网格。
    水面用等比放大的圆盘，近处细、远处覆盖到肉眼地平线之外，天与海不会留下空带。
"""
from __future__ import annotations

import math  # 圆盘环带的三角函数。
from array import array  # 顶点数据用紧凑浮点数组，上传显卡更快。

SEA_LEVEL = 6.0  # 海平面高度，水面平面也放在这里。
MAX_HEIGHT = 46.0  # 地形最高限制，避免山峰穿出云层。
VERTEX_FLOATS = 13  # 每顶点十三个浮点，与顶点着色器的属性布局一一对应。

# 材质编号：片元着色器按编号选粗糙度、透光与高光强弱。
MATERIAL_GRASS = 0  # 草地顶面。
MATERIAL_DIRT = 1  # 草下泥土。
MATERIAL_STONE = 2  # 陡坡与高山岩石。
MATERIAL_SAND = 3  # 海滩与浅滩。
MATERIAL_LEAF = 4  # 树冠叶片。
MATERIAL_WOOD = 5  # 树干。
MATERIAL_BLADE = 6  # 草叶与花梗。
MATERIAL_FLOWER = 7  # 花冠。


def _hash(ix: int, iz: int, seed: int) -> float:
    """返回一个格点的确定性伪随机数，范围零到一。

    只用整数乘加与位运算，不依赖 Python 的随机模块，换机器也得到同一地形。
    """
    value = ix * 374761393 + iz * 668265263 + seed * 1442695040888963407  # 大常数让相邻格点充分打散。
    value = (value ^ (value >> 13)) * 1274126177  # 异或与乘法混合。
    return ((value ^ (value >> 16)) & 0xFFFFFFFF) / 4294967295.0  # 取低三十二位并归一化。


def _hash3(ix: int, iy: int, iz: int, seed: int) -> float:
    """三维格点哈希：同一株植物的每片叶子要稳定地取到不同扰动。"""
    value = ix * 73856093 ^ iy * 19349663 ^ iz * 83492791 ^ seed * 2654435761  # 三个方向各用一个大素数。
    value = (value ^ (value >> 15)) * 2246822519  # 混合高位与低位。
    return ((value ^ (value >> 13)) & 0xFFFFFFFF) / 4294967295.0  # 归一化到零到一。


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

    岛屿中间是一座带山脊的高地，周围是缓坡草地，最外圈沉到海面以下形成浅滩；
    海岸线用低频噪声扭过，不会是一个完美的圆。高度取整到方块，得到体素台阶。
    """
    heights = []  # 按行收集，索引为 z 乘尺寸加 x。
    center = (size - 1) * 0.5  # 岛屿中心。
    for z in range(size):  # 逐行生成。
        for x in range(size):  # 逐列生成。
            nx = (x - center) / center  # 归一化横向距离。
            nz = (z - center) / center  # 归一化纵向距离。
            warp = (_fbm(x * 0.031, z * 0.031, seed + 11, 3) - 0.5) * 0.40  # 让海岸线不规则。
            distance = math.sqrt(nx * nx + nz * nz) + warp  # 带噪声的半径。
            land = max(0.0, min(1.0, (1.04 - distance) / 0.62))  # 一到内陆，零到外海；过渡带越宽，海岸越平缓。
            land = _smooth(land)  # 边缘平滑过渡。
            hills = _fbm(x * 0.038, z * 0.038, seed, 5)  # 大尺度丘陵。
            ridge = 1.0 - abs(2.0 * _fbm(x * 0.052, z * 0.052, seed + 21, 4) - 1.0)  # 折线式山脊。
            mountain = (ridge ** 2.0) * _smooth(max(0.0, min(1.0, (land - 0.34) / 0.62))) * 6.0  # 只有内陆才起山。
            detail = (_fbm(x * 0.16, z * 0.16, seed + 33, 3) - 0.5) * 2.6  # 小尺度起伏。
            base = SEA_LEVEL - 2.2 + hills * 9.0 * (land ** 1.05)  # 海岸高度略低于海面。
            base += mountain * land + detail * land  # 山脊与细节只长在陆地上。
            base -= (1.0 - land) * 7.0  # 岛外快速沉入海底。
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


def column(heights: list[float], size: int, x: int, z: int) -> float:
    """读取一列高度；范围外按海底零处理，边缘因此自然收口。"""
    if x < 0 or z < 0 or x >= size or z >= size:  # 岛外用海底高度。
        return 0.0
    return heights[z * size + x]  # 行优先存放。


def slope_at(heights: list[float], size: int, x: int, z: int) -> float:
    """返回一列与四邻的最大高差，用来区分缓坡草地和陡坡岩石。"""
    height = column(heights, size, x, z)  # 当前列高度。
    neighbours = (  # 四个方向的邻居高度。
        column(heights, size, x - 1, z),
        column(heights, size, x + 1, z),
        column(heights, size, x, z - 1),
        column(heights, size, x, z + 1),
    )
    return max(abs(height - value) for value in neighbours)  # 最大高差。


def material_at(height: float, slope: float) -> int:
    """按高度与坡度选材质：海滩沙、陡坡石、高山石、其余草地。"""
    if height <= SEA_LEVEL + 1.6:  # 海平面附近是沙滩。
        return MATERIAL_SAND
    if slope >= 3.0 or height >= 36.0:  # 只有很陡的断崖与山顶露出岩石。
        return MATERIAL_STONE
    return MATERIAL_GRASS  # 其余是草地。


def _noise_tint(x: int, z: int, seed: int, strength: float) -> tuple[float, float, float]:
    """给同一种材质加一点低频色差，整片草地不会是一块纯色。"""
    low = _value_noise(x * 0.07, z * 0.07, seed)  # 十几米尺度的色块。
    high = _hash(x, z, seed + 7)  # 单方块级别的颗粒。
    amount = (low - 0.5) * 2.0 * strength + (high - 0.5) * strength * 0.45  # 两个尺度叠加。
    return (1.0 + amount, 1.0 + amount * 0.72, 1.0 + amount * 0.40)  # 暖色偏移，避免发灰。


def base_color(material: int, height: float, x: int, z: int) -> tuple[float, float, float]:
    """返回一种材质的线性底色；数值是漫反射率，不是屏幕颜色。"""
    tint = _noise_tint(x, z, 91, 0.16)  # 所有材质共用同一套色差节奏。
    if material == MATERIAL_SAND:
        color = (0.46, 0.40, 0.27)  # 干沙：比草地亮，但不能白到没有层次。
    elif material == MATERIAL_STONE:
        shade = 0.30 + 0.06 * _value_noise(x * 0.3, z * 0.3, 5)  # 石头的深浅纹理。
        color = (shade, shade * 1.01, shade * 1.05)  # 略偏冷。
    elif material == MATERIAL_DIRT:
        color = (0.215, 0.150, 0.098)  # 泥土：比草地暗一截，侧墙才不会一片米白。
    else:
        green = 0.36 + 0.07 * _value_noise(x * 0.13, z * 0.13, 17)  # 草地绿色随位置变化。
        color = (0.19, green, 0.115)  # 草地。
        if height > 24.0:  # 高处草色偏黄，像被风吹干。
            color = (0.28, green * 0.92, 0.13)
    return (color[0] * tint[0], color[1] * tint[1], color[2] * tint[2])  # 乘上低频色差。


def wall_color(material: int, height: float, x: int, z: int) -> tuple[float, float, float]:
    """侧墙颜色：草方块露出泥土，岩石保持石色，沙滩保持沙色。

    再叠一层随高度变化的横向纹理：同一面墙从下到上有深浅条带，
    远看像土层而不是一整块纯色，这也是没有贴图时最省的一条“材质感”。
    """
    if material == MATERIAL_GRASS:  # 草方块侧面是泥土，顶部一层草皮单独着色。
        material = MATERIAL_DIRT
    color = base_color(material, height, x, z)  # 从顶面颜色出发。
    strata = 0.82 + 0.26 * _value_noise(height * 0.85, (x + z) * 0.11, 71)  # 横向土层。
    color = (color[0] * strata, color[1] * strata, color[2] * strata)  # 叠上土层。
    if material == MATERIAL_DIRT:  # 泥土侧墙再压暗一点，形成自然的土层阴影。
        return (color[0] * 0.86, color[1] * 0.80, color[2] * 0.74)
    return (color[0] * 0.94, color[1] * 0.94, color[2] * 0.94)  # 其余材质只轻微压暗。


def push_quad(vertices: array, corners: list[tuple[float, float, float]], normal: tuple[float, float, float],
              color: tuple[float, float, float], occlusion: float, material: int, sway: float = 0.0) -> None:
    """把一个四边形拆成两个三角形追加到顶点数组。

    `corners` 按同一环绕顺序给出四个角，两个三角形共用零号和二号角。
    每个顶点十三个浮点：位置、法线、颜色、遮蔽、材质、摆动权重，与顶点着色器一致。
    `sway` 是风摆权重：零表示贴地不动，一表示枝条末端。
    """
    order = (0, 1, 2, 0, 2, 3)  # 两个三角形的顶点顺序。
    for index in order:  # 依次写入六个顶点。
        x, y, z = corners[index]  # 当前角点。
        vertices.extend((x, y, z, normal[0], normal[1], normal[2],
                         color[0], color[1], color[2], occlusion, float(material), sway))  # 十三个通道。


def push_box(vertices: array, origin: tuple[float, float, float], size: tuple[float, float, float],
             color: tuple[float, float, float], material: int, occlusion: float = 1.0,
             sway_top: float = 0.0, sway_bottom: float = 0.0) -> int:
    """写入一个长方体的六个面，返回三角形数。

    为什么不用背面剔除以外的优化：树木和石头的面数很小，逐个面写入最直观；
    顶面稍亮、底面稍暗是由法线光照自然产生的，这里只给侧面加一点固定差异。
    """
    x0, y0, z0 = origin  # 最小角。
    x1, y1, z1 = origin[0] + size[0], origin[1] + size[1], origin[2] + size[2]  # 最大角。
    faces = (  # 六个面的四角与法线。
        ([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], (0.0, 1.0, 0.0)),  # 顶面。
        ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0.0, -1.0, 0.0)),  # 底面。
        ([(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], (0.0, 0.0, -1.0)),  # 北面。
        ([(x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (x0, y0, z1)], (0.0, 0.0, 1.0)),  # 南面。
        ([(x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (x0, y0, z0)], (-1.0, 0.0, 0.0)),  # 西面。
        ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1.0, 0.0, 0.0)),  # 东面。
    )
    triangles = 0  # 统计本盒子写入的三角形。
    for corners, normal in faces:  # 逐面写入。
        shade = 1.0 if normal[1] > 0.0 else (0.72 if normal[1] < 0.0 else 0.88)  # 顶亮、底暗、侧中。
        face_color = (color[0] * shade, color[1] * shade, color[2] * shade)  # 面明暗。
        sway = sway_bottom if normal[1] < 0.0 else sway_top  # 上下面的摆动权重不同。
        push_quad(vertices, corners, normal, face_color, occlusion, material, sway)  # 写入四边形。
        triangles += 2  # 每面两个三角形。
    return triangles


def build_mesh(heights: list[float], size: int) -> tuple[array, int]:
    """由高度图生成地形三角形，返回顶点数组与三角形数量。

    只生成顶面与露出的侧墙；侧墙高度等于与邻居的高度差，形成方块台阶。
    顶面四角各自按邻柱高度算一点遮蔽，墙角与树下因此有柔和的暗部，
    这是去掉“塑料方块”观感最省的一条手段，不需要额外一张贴图。
    """
    vertices = array("f")  # 交错顶点数据。
    triangles = 0  # 统计三角形数量，写进性能记录。
    for z in range(size):  # 逐列生成方块柱。
        for x in range(size):  # 当前方块柱。
            height = column(heights, size, x, z)  # 当前高度。
            if height < SEA_LEVEL - 2.0:  # 深海底不生成，水面会盖住，省下看不见的三角形。
                continue
            slope = slope_at(heights, size, x, z)  # 最大高差。
            material = material_at(height, slope)  # 当前材质。
            color = base_color(material, height, x, z)  # 顶面颜色。
            corners = ((x, height, z), (x, height, z + 1), (x + 1, height, z + 1), (x + 1, height, z))  # 顶面四角。
            offsets = ((0, 0), (0, 1), (1, 1), (1, 0))  # 四角在网格里的方向。
            occlusion = []  # 每个角的遮蔽系数。
            for dx, dz in offsets:  # 逐角统计三个邻柱。
                side_a = column(heights, size, x + dx, z + dz - 1) > height  # 横向邻居更高。
                side_b = column(heights, size, x + dx - 1, z + dz) > height  # 纵向邻居更高。
                corner = column(heights, size, x + dx - 1, z + dz - 1) > height  # 斜角更高。
                hidden = float(side_a) + float(side_b) + float(corner)  # 三个遮挡源。
                occlusion.append(1.0 - 0.115 * hidden)  # 越多遮挡越暗。
            order = (0, 1, 2, 0, 2, 3)  # 两个三角形的顶点顺序。
            for index in order:  # 逐顶点写入顶面，每个角带自己的遮蔽。
                corner = corners[index]  # 当前角点。
                vertices.extend((corner[0], corner[1], corner[2], 0.0, 1.0, 0.0,
                                 color[0], color[1], color[2], occlusion[index], float(material), 0.0))  # 十三个通道。
            triangles += 2  # 顶面两个三角形。
            wall = wall_color(material, height, x, z)  # 侧墙颜色。
            if material == MATERIAL_GRASS:  # 草方块的侧墙以泥土为主，只在顶部混一点草色。
                lip = base_color(MATERIAL_GRASS, height, x, z)  # 顶面草色。
                wall = (wall[0] * 0.80 + lip[0] * 0.20, wall[1] * 0.80 + lip[1] * 0.20,
                        wall[2] * 0.80 + lip[2] * 0.20)  # 混出略带苔色的泥土墙。
            neighbours = (  # 四个方向的邻居高度。
                (column(heights, size, x - 1, z), -1.0, 0.0),  # 西。
                (column(heights, size, x + 1, z), 1.0, 0.0),  # 东。
                (column(heights, size, x, z - 1), 0.0, -1.0),  # 北。
                (column(heights, size, x, z + 1), 0.0, 1.0),  # 南。
            )
            for neighbour_height, normal_x, normal_z in neighbours:  # 逐方向补侧墙。
                if neighbour_height >= height:  # 邻居不低就没有露出的墙。
                    continue
                low = max(neighbour_height, SEA_LEVEL - 2.0)  # 墙底不低于海面以下两格。
                if normal_x < 0.0:  # 西墙。
                    side = [(x, low, z), (x, height, z), (x, height, z + 1), (x, low, z + 1)]
                elif normal_x > 0.0:  # 东墙。
                    side = [(x + 1, low, z), (x + 1, low, z + 1), (x + 1, height, z + 1), (x + 1, height, z)]
                elif normal_z < 0.0:  # 北墙。
                    side = [(x, low, z), (x + 1, low, z), (x + 1, height, z), (x, height, z)]
                else:  # 南墙。
                    side = [(x, low, z + 1), (x, height, z + 1), (x + 1, height, z + 1), (x + 1, low, z + 1)]
                shade = 0.80 if (normal_x + normal_z) > 0.0 else 0.92  # 背光面稍暗，增加体积感。
                face = (wall[0] * shade, wall[1] * shade, wall[2] * shade)  # 侧墙颜色。
                push_quad(vertices, side, (normal_x, 0.0, normal_z), face, 0.86, material)  # 侧墙不参与逐角遮蔽。
                triangles += 2  # 每面墙两个三角形。
    return vertices, triangles  # 顶点与三角形统计。
