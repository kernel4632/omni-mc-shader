"""照片级测试世界的连续地形：湖盆、草甸、远山与水面的程序化几何。

调用位置：
    `omni-gfx/examples/world/render.py` 启动时调用 `build_terrain` 与 `water_disc`；
    `omni-gfx/examples/world/vegetation.py` 用 `height_at`、`normal_at` 决定树、草与石块的位置。
调用示例：`terrain = build_terrain()`；用 `height_at(x, z)` 放置植被。

设计原因与取舍：
    旧的方块岛每次升级都绕不开“台阶”轮廓，远看仍像技术演示。
    这里改成连续高度场：同一套噪声同时决定湖盆、草甸与远山，网格按离相机的距离
    指数加密，近处约两米一个顶点，远处几百米一个，既保住山脊轮廓又控制三角形数量。
    湖面固定在世界高度零，地形在湖盆内压到水下，水面用一张大圆盘覆盖；
    这样不需要额外的水域边界，岸线由高度场自然形成。
    所有随机量来自固定整数哈希，换机器与换会话得到同一座山谷，截图可以逐像素比较。
"""
from __future__ import annotations

import math  # 三角函数、指数与平方根。
from array import array  # 顶点数据用紧凑数组上传。

WATER_LEVEL = 0.0  # 湖面世界高度，米；地形低于它的部分被水覆盖。
LAKE_CENTER = (0.0, -30.0)  # 湖心在世界坐标的横向与纵向位置。
LAKE_RADIUS = (112.0, 148.0)  # 湖盆横向与纵向半径，米；岸线因此是一个椭圆。
MAX_TERRAIN = 330.0  # 山体高度上限，避免山尖穿出云层。
CAMERA_START = (0.0, 165.0)  # 默认机位在湖岸草坡的观景走廊上，离水线约四十五米。
TERRAIN_RADIUS = 3000.0  # 地形圆盘半径，米；远山之外仍留出空气透视的空隙。
TERRAIN_RINGS = 280  # 径向分格；指数间距让近处细、远处粗。
TERRAIN_SEGMENTS = 480  # 环向分格；远处山脊也不会出现明显折线。

# 材质编号与片元着色器里的纹理数组层号一一对应。
MATERIAL_GRASS = 0  # 草甸。
MATERIAL_DIRT = 1  # 泥土、小径与湖岸裸土。
MATERIAL_ROCK = 2  # 岩石、陡坡与山体。
MATERIAL_SAND = 3  # 湖岸湿沙。
MATERIAL_FOREST = 4  # 树下腐殖土。
MATERIAL_BARK = 5  # 树皮，只给树干与枝条使用。


def _hash(ix: int, iz: int, seed: int) -> float:
    """返回一个格点的确定性伪随机数，范围零到一。"""
    value = ix * 374761393 + iz * 668265263 + seed * 1442695040888963407  # 大常数打散相邻格点。
    value = (value ^ (value >> 13)) * 1274126177  # 异或与乘法混合。
    return ((value ^ (value >> 16)) & 0xFFFFFFFF) / 4294967295.0  # 归一化到零到一。


def _smooth(t: float) -> float:
    """三次平滑曲线，让值噪声的格子边界没有折线。"""
    return t * t * (3.0 - 2.0 * t)


def _value_noise(x: float, z: float, seed: int) -> float:
    """二维值噪声：四个格点哈希后按平滑曲线双线性插值。"""
    ix = int(math.floor(x))
    iz = int(math.floor(z))
    fx = _smooth(x - ix)
    fz = _smooth(z - iz)
    a = _hash(ix, iz, seed)
    b = _hash(ix + 1, iz, seed)
    c = _hash(ix, iz + 1, seed)
    d = _hash(ix + 1, iz + 1, seed)
    top = a + (b - a) * fx
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fz


def _fbm(x: float, z: float, seed: int, octaves: int) -> float:
    """分形叠加：频率翻倍、权重减半，得到自然的多尺度起伏。"""
    total = 0.0
    amplitude = 0.5
    frequency = 1.0
    for octave in range(octaves):
        total += _value_noise(x * frequency, z * frequency, seed + octave * 101) * amplitude
        frequency *= 2.0
        amplitude *= 0.5
    return total


def _ridge(x: float, z: float, seed: int, octaves: int) -> float:
    """山脊噪声：把一减绝对值的折线叠加，得到尖锐但不规则的山脊。"""
    total = 0.0
    amplitude = 0.55
    frequency = 1.0
    for octave in range(octaves):
        value = 1.0 - abs(2.0 * _value_noise(x * frequency, z * frequency, seed + octave * 71) - 1.0)
        total += value * value * amplitude  # 平方让脊线更窄。
        frequency *= 2.03  # 非整数倍频，山脊不会重复同一形状。
        amplitude *= 0.48
    return total


def lake_distance(x: float, z: float) -> float:
    """返回点到湖盆椭圆的归一化距离，小于一在水里。

    椭圆本身太规整，会增加两层低频噪声把岸线扭出小湾与半岛；
    噪声只改岸线，不改湖心深度，水面仍是一整片连续平面。
    """
    dx = (x - LAKE_CENTER[0]) / LAKE_RADIUS[0]
    dz = (z - LAKE_CENTER[1]) / LAKE_RADIUS[1]
    warp = (_value_noise(x * 0.010, z * 0.010, 91) - 0.5) * 0.28  # 二十米级的大湾。
    warp += (_value_noise(x * 0.040, z * 0.040, 93) - 0.5) * 0.07  # 几米级的碎岸。
    return math.sqrt(dx * dx + dz * dz) + warp


def height_at(x: float, z: float) -> float:
    """返回世界坐标处的地形高度，米；这是整个测试世界唯一的陆地形状来源。

    组成从大到小：
    1. 草甸缓坡与大尺度丘陵，给近景提供起伏；
    2. 湖盆：椭圆内部压到水下，边缘平滑过渡成沙滩；
    3. 两侧低山：夹住湖面，让视线有前景、中景与远景；
    4. 远处山脉：从三百米外抬升到两百米，山脊线提供天空的负形。
    所有项都连续，网格再密也不会出现方块台阶。
    """
    rolling = _fbm(x * 0.0075, z * 0.0075, 11, 4) * 14.0  # 百米级丘陵。
    rolling += _fbm(x * 0.030, z * 0.030, 23, 3) * 2.6  # 三十米级起伏。
    rolling += _fbm(x * 0.14, z * 0.14, 37, 2) * 0.45  # 米级细节，近处草地不呆板。
    base = 1.8 + rolling  # 整体抬高，保证湖盆外都高于水面。

    distance = lake_distance(x, z)  # 归一的湖盆距离。
    shore = _smooth(max(0.0, min(1.0, (distance - 0.94) / 0.55)))  # 零在水线，一到岸外五十米。
    bed = -3.4 - 4.6 * max(0.0, 1.0 - distance)  # 湖心更深，岸边缓。
    height = bed * (1.0 - shore) + base * shore  # 湖盆与草甸连续过渡。
    # 水线附近压出一圈很缓的浅滩：岸坡不再是一道陡壁，石头与草地自然接到水面。
    shelf = _smooth(max(0.0, min(1.0, (distance - 0.95) / 0.09))) * (1.0 - _smooth(max(0.0, min(1.0, (distance - 1.12) / 0.26))))
    height = height * (1.0 - shelf * 0.70) + (0.18 + 0.12 * _value_noise(x * 0.15, z * 0.15, 95)) * shelf * 0.70

    # 两侧低山：两个椭圆高斯，夹住湖面但不挡正前方的主山；湖内不抬升。
    land = _smooth(max(0.0, min(1.0, (distance - 0.96) / 0.22)))  # 岸外才允许加山丘。
    left = math.exp(-(((x + 245.0) / 170.0) ** 2 + ((z + 10.0) / 210.0) ** 2))
    right = math.exp(-(((x - 285.0) / 185.0) ** 2 + ((z + 40.0) / 230.0) ** 2))
    height += (30.0 * left + 36.0 * right) * land

    # 远处山脉：从五百米外开始抬升，山脊高度随噪声变化；山离得远，空气透视才有层次。
    radius = math.sqrt((x * 0.82) ** 2 + ((z + 20.0) * 0.70) ** 2)  # 纵向压扁，山带更宽。
    rise = _smooth(max(0.0, min(1.0, (radius - 500.0) / 720.0)))  # 五百米外开始起山。
    ridge = _ridge(x * 0.0024, z * 0.0024, 51, 5)  # 山脊形状；频率降低，山体更宽。
    height += rise * (14.0 + 150.0 * ridge)  # 主山带；高度略降，远处不再像一堵白墙。
    # 主山带前面再放一层低丘，山脚不会从平地突然拔起。
    foothill = _smooth(max(0.0, min(1.0, (radius - 330.0) / 340.0)))
    height += foothill * (4.0 + 22.0 * _fbm(x * 0.0050, z * 0.0050, 67, 3))

    # 湖岸草坡的观景走廊：从机位到水边做成连续下坡，避免一道隆起把湖面挡住。
    # 走廊只在机位正前方、约一百二十米宽的范围里生效，边缘用平滑权重融入自然地形。
    corridor_x = 1.0 - _smooth(max(0.0, min(1.0, (abs(x) - 35.0) / 190.0)))
    corridor_z = _smooth(max(0.0, min(1.0, (z - 118.0) / 16.0))) * (1.0 - _smooth(max(0.0, min(1.0, (z - 168.0) / 28.0))))
    ramp = max(0.0, (z - 120.0) / 50.0) * 10.8  # 水边零米，机位后方约十米。
    height = height * (1.0 - corridor_x * corridor_z * 0.82) + ramp * corridor_x * corridor_z * 0.82

    # 山体越高越尖，避免整个高原一样平；只在高处生效，不影响草甸。
    if height > 60.0:
        height += (height - 60.0) * 0.22 * _fbm(x * 0.020, z * 0.020, 83, 2)
    return max(-9.0, min(MAX_TERRAIN, height))


def slope_at(x: float, z: float, step: float = 1.5) -> float:
    """返回地形坡度，零是水平，一是垂直；用于放置植被与选择材质。"""
    dx = height_at(x + step, z) - height_at(x - step, z)
    dz = height_at(x, z + step) - height_at(x, z - step)
    gradient = math.sqrt(dx * dx + dz * dz) / (2.0 * step)
    return gradient / math.sqrt(1.0 + gradient * gradient)  # 斜率换成倾角正弦。


def water_disc(radius: float, rings: int, segments: int) -> tuple[array, int]:
    """生成覆盖整个湖盆与远景的水面圆盘，返回顶点数组与三角形数。

    水只在湖盆里可见，圆盘比湖大很多也不会露出：周围地形都高于水面，会遮住它。
    环半径指数增长，近处几米一格，远处几百米一格；地平线以外仍需存在水面，
    否则天空与山脚之间会露出一条底色。
    """
    vertices = array("f")  # 每顶点两个浮点，高度由顶点着色器填。
    inner = 0.6  # 最内圈半径，避免中心退化。
    ratio = (radius / inner) ** (1.0 / rings)  # 每圈放大的倍数。
    for ring in range(rings):  # 逐圈生成环带。
        near_radius = inner * (ratio ** ring)
        far_radius = near_radius * ratio
        for segment in range(segments):  # 环向分段。
            angle0 = 2.0 * math.pi * segment / segments
            angle1 = 2.0 * math.pi * (segment + 1) / segments
            corners = (
                (math.cos(angle0) * near_radius, math.sin(angle0) * near_radius),
                (math.cos(angle1) * near_radius, math.sin(angle1) * near_radius),
                (math.cos(angle1) * far_radius, math.sin(angle1) * far_radius),
                (math.cos(angle0) * far_radius, math.sin(angle0) * far_radius),
            )
            for index in (0, 1, 2, 0, 2, 3):  # 两个三角形。
                vertices.extend(corners[index])
    return vertices, rings * segments * 2


def build_terrain(center: tuple[float, float], radius: float = TERRAIN_RADIUS,
                  rings: int = TERRAIN_RINGS, segments: int = TERRAIN_SEGMENTS) -> tuple[array, int]:
    """生成以相机为中心的放射状地形网格，返回顶点数组与三角形数。

    顶点只有位置与法线：材质、颜色、粗糙度全部由片元阶段按世界坐标和坡度混合，
    这样换贴图或调材质比例不用重建 CPU 网格。
    法线在生成后由相邻顶点差商计算，不为每个顶点额外调用五次高度函数；
    高度函数含十几次噪声，省下这一步能把启动时间压到几秒。
    """
    center_x, center_z = center  # 网格中心，默认在机位脚下。
    inner = 0.75  # 最内圈半径，避免中心面积为零。
    ratio = (radius / inner) ** (1.0 / rings)  # 指数间距。
    heights = []  # 每圈每个顶点的高度。
    positions = []  # 世界坐标，法线计算要用邻居。
    for ring in range(rings + 1):  # 从内圈到最外圈。
        ring_radius = inner * (ratio ** ring)  # 内圈也有面积，中心另外补一个扇形盖。
        heights.append([])
        positions.append([])
        for segment in range(segments):  # 环向一圈。
            angle = 2.0 * math.pi * segment / segments
            x = center_x + math.cos(angle) * ring_radius
            z = center_z + math.sin(angle) * ring_radius
            y = height_at(x, z)
            heights[ring].append(y)
            positions[ring].append((x, y, z))
    vertices = array("f")  # 位置与法线交错。
    triangles = 0
    for ring in range(rings):  # 逐环带生成三角形。
        for segment in range(segments):  # 当前角度。
            next_segment = (segment + 1) % segments
            p0 = positions[ring][segment]  # 内圈当前角。
            p1 = positions[ring][next_segment]  # 内圈下一个角。
            p2 = positions[ring + 1][next_segment]  # 外圈下一个角。
            p3 = positions[ring + 1][segment]  # 外圈当前角。
            # 四个角共用同一套法线计算，边缘不会出现一条硬折线。
            n0 = _vertex_normal(positions, heights, ring, segment)
            n1 = _vertex_normal(positions, heights, ring, next_segment)
            n2 = _vertex_normal(positions, heights, ring + 1, next_segment)
            n3 = _vertex_normal(positions, heights, ring + 1, segment)
            for point, normal in ((p0, n0), (p1, n1), (p2, n2), (p0, n0), (p2, n2), (p3, n3)):
                vertices.extend((point[0], point[1], point[2], normal[0], normal[1], normal[2]))
            triangles += 2
    # 最内圈围成一圈，中心补一个扇形盖，低头时脚下不会看到一个小洞。
    center_height = height_at(center_x, center_z)
    step = 1.2  # 中心法线的差分步长，米。
    dx = height_at(center_x + step, center_z) - height_at(center_x - step, center_z)
    dz = height_at(center_x, center_z + step) - height_at(center_x, center_z - step)
    center_normal = (-dx / (2.0 * step), 1.0, -dz / (2.0 * step))
    normal_length = math.sqrt(sum(component * component for component in center_normal))
    center_normal = tuple(component / normal_length for component in center_normal)
    for segment in range(segments):  # 每个环向分段一个三角形。
        next_segment = (segment + 1) % segments
        p0 = positions[0][segment]
        p1 = positions[0][next_segment]
        for point, normal in (((center_x, center_height, center_z), center_normal), (p1, _vertex_normal(positions, heights, 0, next_segment)),
                              (p0, _vertex_normal(positions, heights, 0, segment))):
            vertices.extend((point[0], point[1], point[2], normal[0], normal[1], normal[2]))
        triangles += 1
    return vertices, triangles


def _vertex_normal(positions, heights, ring: int, segment: int) -> tuple[float, float, float]:
    """用环向与径向邻居的高度差计算顶点法线，返回单位向量。

    径向邻居在内圈和外圈各取一个；中心圈没有内邻居时只取外圈。
    环向首尾相连，湖面与山脊跨过接缝也不会出现一条亮线。
    """
    segments = len(positions[ring])
    next_segment = (segment + 1) % segments
    previous_segment = (segment - 1) % segments
    current = positions[ring][segment]
    along_segment = (
        positions[ring][next_segment][0] - positions[ring][previous_segment][0],
        positions[ring][next_segment][1] - positions[ring][previous_segment][1],
        positions[ring][next_segment][2] - positions[ring][previous_segment][2],
    )
    inner = positions[max(0, ring - 1)][segment]
    outer = positions[min(len(positions) - 1, ring + 1)][segment]
    along_ring = (outer[0] - inner[0], outer[1] - inner[1], outer[2] - inner[2])
    nx = along_segment[1] * along_ring[2] - along_segment[2] * along_ring[1]
    ny = along_segment[2] * along_ring[0] - along_segment[0] * along_ring[2]
    nz = along_segment[0] * along_ring[1] - along_segment[1] * along_ring[0]
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-6:  # 退化三角形给一个朝上的法线。
        return 0.0, 1.0, 0.0
    if ny < 0.0:  # 三角形绕序与高度场方向相反时翻回来。
        nx, ny, nz = -nx, -ny, -nz
    return nx / length, ny / length, nz / length
