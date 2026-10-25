"""光影验证场景的几何：连续草甸湖盆、石台、五种粗糙度的球、方块与立石。

调用位置：`omni-gfx/examples/lighting/render.py` 在启动时构建一次。
设计原因与取舍：
    这一版不靠模型细节或扫描贴图，几何只保留能检验光照的形状：
    起伏地形给出大范围明暗与接触面，球体给出连续法线和高光形状，方块给出硬边与接触阴影，
    水面给出菲涅尔与反射，立石在低角度阳光下把体积雾切成可见光柱。
    所有表面只写线性反照率与粗糙度，材质差异来自真实的光照响应，而不是贴图纹理。
"""
from __future__ import annotations

import math  # 三角函数、平方根与球面参数。
import random  # 立石与草丛的固定随机扰动，保证每次启动几何一致。
from array import array  # 大量顶点用紧凑数组传给显卡。

WATER_LEVEL = 0.0  # 湖面高度，米；地形低于这里的地方被水覆盖。
TERRAIN_EXTENT = 620.0  # 地形与水面覆盖的方形边长，米；远处交给雾遮住边缘。
TERRAIN_CELLS = 256  # 地形每边分格数；一格约二点四米，低模轮廓仍然平滑。

# 相机位置与观看目标；湖盆、石台与立石都围绕这条视线摆放。
CAMERA_START = (10.0, 34.0)  # 相机站位的水平坐标，米；退后一点让整排球与湖面同时入镜。
LOOK_TARGET = (5.0, 3.0, -8.0)  # 看向湖对岸偏右，地平线压低，天空与云占更多画面。


class HeightField:
    """可重复采样的连续高度场；网格、球体落点和相机都读同一份函数。"""

    def __init__(self) -> None:
        """固定随机种子，保证地形、石台与立石在每次启动时位置一致。"""
        self.seed = 20261026  # 场景版本号式的种子；改它会改湖岸轮廓。
        self.pond_center = (0.0, -8.0)  # 湖盆中心的水平坐标，米。
        self.pond_radius = 36.0  # 从浅滩到草坡的过渡半径，米。

    def hash2(self, ix: int, iz: int) -> float:
        """二维整数哈希，返回零到一；不用贴图也能得到可重复的噪声。"""
        value = ix * 374761393 + iz * 668265263 + self.seed * 1442695041  # 三个大奇数打散格子坐标。
        value = (value ^ (value >> 13)) * 1274126177  # 异或移位后再乘一次，低位参与高位。
        value &= 0xFFFFFFFF  # 只保留三十二位，避免 Python 大整数无限增长。
        return ((value ^ (value >> 16)) & 0xFFFF) / 65535.0  # 压到零到一。

    def value_noise(self, x: float, z: float) -> float:
        """二维值噪声：格点随机值做平滑双线性插值，得到没有方向性的起伏。"""
        ix = math.floor(x)  # 左格点。
        iz = math.floor(z)  # 下格点。
        fx = x - ix  # 格内小数。
        fz = z - iz  # 格内小数。
        ux = fx * fx * (3.0 - 2.0 * fx)  # 两端导数为零的平滑曲线。
        uz = fz * fz * (3.0 - 2.0 * fz)  # 纵向同样平滑。
        a = self.hash2(ix, iz)  # 左下角。
        b = self.hash2(ix + 1, iz)  # 右下角。
        c = self.hash2(ix, iz + 1)  # 左上角。
        d = self.hash2(ix + 1, iz + 1)  # 右上角。
        return (a + (b - a) * ux) * (1.0 - uz) + (c + (d - c) * ux) * uz  # 先横向再纵向。

    def fbm(self, x: float, z: float, octaves: int) -> float:
        """多层值噪声叠加，低频给大起伏，高频给细碎变化。"""
        total = 0.0  # 累积值。
        amplitude = 1.0  # 当前层振幅。
        normalization = 0.0  # 振幅总和。
        frequency = 1.0  # 当前层空间频率。
        for _ in range(octaves):  # 逐层叠加。
            total += self.value_noise(x * frequency, z * frequency) * amplitude  # 当前层贡献。
            normalization += amplitude  # 记录归一化分母。
            amplitude *= 0.5  # 高频层越来越弱。
            frequency *= 2.03  # 略微偏离两倍，减少格点对齐的重复。
        return total / max(normalization, 1e-6)  # 回到零到一。

    def height(self, x: float, z: float) -> float:
        """返回世界坐标处的地面高度，米；水面固定在零。"""
        distance = math.hypot(x - self.pond_center[0], z - self.pond_center[1])  # 到湖心的水平距离。
        shore = self.fbm(x * 0.055 + 11.0, z * 0.055 - 3.0, 3) - 0.5  # 岸线扰动，避免完美圆。
        shaped_distance = distance + shore * 7.0  # 岸线被噪声推拉，形成小湾与突角。
        basin = 1.0 - min(max((shaped_distance - 16.0) / (self.pond_radius - 16.0), 0.0), 1.0)  # 一在湖心，零在岸上。
        basin = basin * basin * (3.0 - 2.0 * basin)  # 平滑过渡，岸边没有折线。
        base = 1.18 + self.fbm(x * 0.032, z * 0.032, 4) * 0.62 + self.fbm(x * 0.11, z * 0.11, 3) * 0.20  # 草甸缓坡。
        height = base - basin * 5.8  # 湖盆下挖，中心约负四米。
        height += min(max((z - 22.0) / 24.0, 0.0), 1.0) * 1.15  # 南岸抬高，相机站在干地上。
        north = min(max((-z - 52.0) / 150.0, 0.0), 1.0)  # 北侧远景从五十米外开始抬升。
        height += north * north * (7.0 + self.fbm(x * 0.013 + 7.0, z * 0.013, 3) * 15.0)  # 北面低山。
        west = min(max((-x - 60.0) / 170.0, 0.0), 1.0)  # 西侧远景从六十米外开始抬升。
        height += west * west * (4.0 + self.fbm(x * 0.011, z * 0.011 + 5.0, 3) * 11.0)  # 西面缓丘。
        # 近岸小土包：给球体与立石一个不完全平整的落点，接触阴影才有意义。
        height += math.exp(-((x + 11.0) ** 2 + (z - 24.0) ** 2) / 26.0) * 0.55
        height += math.exp(-((x - 15.0) ** 2 + (z - 18.0) ** 2) / 40.0) * 0.42
        return height

    def normal(self, x: float, z: float) -> tuple[float, float, float]:
        """用有限差分求法线，步长半米；地形着色与球体落点都用它。"""
        step = 0.5  # 采样间距，米。
        left = self.height(x - step, z)  # 西侧高度。
        right = self.height(x + step, z)  # 东侧高度。
        back = self.height(x, z - step)  # 北侧高度。
        front = self.height(x, z + step)  # 南侧高度。
        nx = left - right  # 高度差换成朝上的法线横分量。
        nz = back - front  # 高度差换成朝上的法线纵分量。
        ny = 2.0 * step  # 竖直分量由步长决定。
        length = math.sqrt(nx * nx + ny * ny + nz * nz)  # 归一化长度。
        return (nx / length, ny / length, nz / length)  # 返回单位法线。

    def material(self, x: float, z: float, height: float, normal_y: float) -> tuple[tuple[float, float, float], float]:
        """按坡度、高度与离水距离给线性反照率和粗糙度；不读取任何贴图。"""
        slope = 1.0 - max(min(normal_y, 1.0), 0.0)  # 零是平地，一是直壁。
        variation = self.fbm(x * 0.07, z * 0.07, 2)  # 大尺度干湿斑块。
        fine = self.fbm(x * 0.55, z * 0.55, 1)  # 细碎草色变化。
        grass = (0.040 + variation * 0.026, 0.090 + variation * 0.040, 0.022 + fine * 0.018)  # 偏黄的草绿，饱和度略高。
        rock = (0.085 + fine * 0.030, 0.080 + fine * 0.028, 0.072 + fine * 0.024)  # 中性灰岩。
        mud = (0.115 + variation * 0.040, 0.088 + variation * 0.030, 0.055 + variation * 0.020)  # 湿泥与细沙。
        blend = min(max((slope - 0.22) / 0.26, 0.0), 1.0)  # 陡坡露岩。
        albedo = tuple(grass[i] * (1.0 - blend) + rock[i] * blend for i in range(3))  # 草与岩混合。
        shore = 1.0 - min(max((height - 0.05) / 0.85, 0.0), 1.0)  # 近水一米内算湿岸。
        albedo = tuple(albedo[i] * (1.0 - shore * 0.45) + mud[i] * shore * 0.45 for i in range(3))  # 湿岸更深更褐。
        if height < WATER_LEVEL - 0.02:  # 水下地面只保留很暗的底色，水体吸收会再压一次。
            albedo = tuple(component * 0.34 for component in albedo)
        roughness = 0.80 + fine * 0.08 - shore * 0.22  # 湿岸更光滑，草与岩偏粗糙。
        return albedo, max(0.18, min(0.92, roughness))


def add_vertex(vertices: array, position, normal, albedo, roughness: float, metallic: float = 0.0) -> None:
    """把位置、法线、线性反照率、粗糙度与金属度写进交错顶点数组。"""
    vertices.extend(position)  # 三个位置分量。
    vertices.extend(normal)  # 三个法线分量。
    vertices.extend(albedo)  # 三个线性颜色分量。
    vertices.append(roughness)  # 一个粗糙度。
    vertices.append(metallic)  # 一个金属度；零是电介质，一是金属。


def build_terrain(field: HeightField) -> tuple[array, int]:
    """生成规则网格地形，返回交错顶点数组与三角形数。

    先把高度存成二维表，再用相邻格点差分求法线；这样每个顶点只采样一次高度，
    在纯 Python 里启动时间从几十秒降到几秒。边缘用单侧差分，避免越界。
    """
    cells = TERRAIN_CELLS  # 每边格数。
    half = TERRAIN_EXTENT * 0.5  # 方形边长的一半。
    step = TERRAIN_EXTENT / cells  # 一格的世界尺寸。
    heights = [[0.0] * (cells + 1) for _ in range(cells + 1)]  # 高度表，行是 z，列是 x。
    for iz in range(cells + 1):  # 逐行填高度。
        z = -half + iz * step  # 当前行世界坐标。
        row = heights[iz]  # 当前行引用。
        for ix in range(cells + 1):  # 逐列填高度。
            row[ix] = field.height(-half + ix * step, z)  # 采样一次高度。
    vertices = array("f")  # 交错顶点。
    grid = array("f")  # 规则网格顶点，先按行列存，随后展开成三角形。
    for iz in range(cells + 1):  # 重新逐顶点生成法线与材质。
        z = -half + iz * step  # 当前行世界坐标。
        for ix in range(cells + 1):  # 逐列。
            x = -half + ix * step  # 当前列世界坐标。
            height = heights[iz][ix]  # 已算好的高度。
            left = heights[iz][max(ix - 1, 0)]  # 西侧邻居。
            right = heights[iz][min(ix + 1, cells)]  # 东侧邻居。
            back = heights[max(iz - 1, 0)][ix]  # 北侧邻居。
            front = heights[min(iz + 1, cells)][ix]  # 南侧邻居。
            nx = left - right  # 东西高度差。
            nz = back - front  # 南北高度差。
            ny = 2.0 * step  # 竖直分量。
            length = math.sqrt(nx * nx + ny * ny + nz * nz)  # 法线长度。
            normal = (nx / length, ny / length, nz / length)  # 单位法线。
            albedo, roughness = field.material(x, z, height, normal[1])  # 材质参数。
            add_vertex(grid, (x, height, z), normal, albedo, roughness)  # 先写网格。
    stride = (cells + 1) * 11  # 一行顶点的浮点数。
    for iz in range(cells):  # 每个格子两个三角形。
        for ix in range(cells):  # 逐列。
            a = iz * stride + ix * 11  # 左下角。
            b = a + 11  # 右下角。
            c = a + stride  # 左上角。
            d = c + 11  # 右上角。
            for start in (a, c, b, b, c, d):  # 正面朝上的逆时针绕序。
                vertices.extend(grid[start:start + 11])  # 复制十一个浮点。
    return vertices, cells * cells * 2  # 每个格子两个三角形。


def build_water() -> tuple[array, int]:
    """生成一张覆盖整个场景的平面水片；地形深度测试会挡住岸上部分。"""
    half = TERRAIN_EXTENT * 6.0  # 水面一直铺到雾里，避免远岸出现几何边缘。
    corners = [(-half, half), (half, half), (half, -half), (-half, -half)]  # 四个角，逆时针。
    vertices = array("f")  # 只存水平坐标，高度由着色器里的水面高度决定。
    for x, z in corners:  # 每个角两个分量。
        vertices.extend((x, z))
    return vertices, 2  # 两个三角形铺满场景。


def add_box(vertices: array, center, half_size, rotation: float, albedo, roughness: float) -> None:
    """把任意朝向的长方体写进顶点数组；法线按面固定，硬边因此清楚。"""
    cosine = math.cos(rotation)  # 绕纵轴旋转的余弦。
    sine = math.sin(rotation)  # 绕纵轴旋转的正弦。
    # 先算八个角，再按面取角；这样位置与法线共用同一套旋转，不会出现面与角错位。
    corners = []  # 八个世界坐标角。
    for sign_x in (-1.0, 1.0):  # 左右。
        for sign_y in (-1.0, 1.0):  # 上下。
            for sign_z in (-1.0, 1.0):  # 前后。
                local_x = sign_x * half_size[0]  # 局部横向偏移。
                local_y = sign_y * half_size[1]  # 局部竖向偏移。
                local_z = sign_z * half_size[2]  # 局部纵向偏移。
                world_x = center[0] + local_x * cosine + local_z * sine  # 绕纵轴旋转。
                world_z = center[2] - local_x * sine + local_z * cosine  # 同一旋转的纵向分量。
                corners.append((world_x, center[1] + local_y, world_z))  # 角点高度不受旋转影响。
    faces = (  # 每个面：四个角在 corners 里的下标，以及局部法线。
        ((1, 5, 7, 3), (0.0, 0.0, 1.0)),  # 前。
        ((4, 0, 2, 6), (0.0, 0.0, -1.0)),  # 后。
        ((4, 6, 7, 5), (1.0, 0.0, 0.0)),  # 右。
        ((0, 1, 3, 2), (-1.0, 0.0, 0.0)),  # 左。
        ((2, 3, 7, 6), (0.0, 1.0, 0.0)),  # 上。
        ((0, 4, 5, 1), (0.0, -1.0, 0.0)),  # 下。
    )
    for indices, local_normal in faces:  # 逐面生成两个三角形。
        normal = (local_normal[0] * cosine + local_normal[2] * sine, local_normal[1],
                  -local_normal[0] * sine + local_normal[2] * cosine)  # 法线绕纵轴旋转。
        for index in (indices[0], indices[1], indices[2], indices[0], indices[2], indices[3]):  # 保持逆时针。
            add_vertex(vertices, corners[index], normal, albedo, roughness)  # 写入顶点。


def add_sphere(vertices: array, center, radius: float, albedo, roughness: float, metallic: float = 0.0, rings: int = 24, segments: int = 48) -> None:
    """生成经纬球；法线等于单位方向，球面高光因此连续。"""
    def point(ring: int, segment: int):
        """返回球面位置与单位法线，供四个角共用。"""
        phi = ring / rings * math.pi  # 极角，从北极到南极。
        theta = segment / segments * math.tau  # 方位角。
        direction = (math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))  # 单位球方向。
        position = tuple(center[i] + direction[i] * radius for i in range(3))  # 球面点。
        return position, direction  # 位置与法线同向。

    for ring in range(rings):  # 每个纬度带。
        for segment in range(segments):  # 每个经度格。
            # 四角顺序保证两个三角形都朝外；极点附近的退化三角形由光栅化自然丢弃。
            p00, n00 = point(ring, segment)  # 左下。
            p10, n10 = point(ring + 1, segment)  # 左上。
            p11, n11 = point(ring + 1, segment + 1)  # 右上。
            p01, n01 = point(ring, segment + 1)  # 右下。
            for position, normal in ((p00, n00), (p01, n01), (p10, n10), (p10, n10), (p01, n01), (p11, n11)):  # 两个朝外的三角形。
                add_vertex(vertices, position, normal, albedo, roughness, metallic)  # 写入顶点。


def build_objects(field: HeightField) -> tuple[array, int, dict]:
    """生成石台、五个粗糙度球、两个方块与三根立石，返回顶点与统计。"""
    vertices = array("f")  # 交错顶点。
    rng = random.Random(7127)  # 固定随机数，石头朝向每次一致。
    # 石台：一条嵌在草坡里的长条石凳，给球体一个干净的接触面。
    shelf_x, shelf_z = 5.2, 23.4  # 石台中心，向右移让整排球进入画面。
    shelf_ground = max(field.height(shelf_x + dx, shelf_z + dz) for dx in (-4.5, 0.0, 4.5) for dz in (-1.0, 0.0, 1.0))  # 取范围内最高地面。
    shelf_top = shelf_ground + 0.32  # 石台顶面略高于草坡。
    add_box(vertices, (shelf_x, shelf_top - 0.28, shelf_z), (4.8, 0.28, 1.15), 0.02,
            (0.095, 0.090, 0.082), 0.72)  # 石台本体。
    # 五个球：从镜面到粗糙，摆在石台上；半径一致，差别只来自粗糙度。
    sphere_specs = (  # 位置偏移、半径、反照率、粗糙度、金属度。
        (-3.5, 0.0, 0.78, (0.72, 0.70, 0.66), 0.05, 1.0),  # 镜面金属；检验天空、云与地面的环境反射。
        (-1.75, 0.25, 0.78, (0.70, 0.62, 0.50), 0.18, 1.0),  # 微光金属，带一点暖色。
        (0.0, -0.1, 0.78, (0.20, 0.19, 0.18), 0.34, 0.0),  # 半光绝缘体。
        (1.75, 0.2, 0.78, (0.18, 0.17, 0.16), 0.55, 0.0),  # 哑光绝缘体。
        (3.5, -0.05, 0.78, (0.16, 0.15, 0.14), 0.78, 0.0),  # 粗糙绝缘体；高光摊成宽亮区。
    )
    for offset_x, offset_z, radius, albedo, roughness, metallic in sphere_specs:  # 逐球生成。
        center = (shelf_x + offset_x, shelf_top + radius, shelf_z + offset_z)  # 球心在石台顶面上。
        add_sphere(vertices, center, radius, albedo, roughness, metallic)  # 写入球体。
    # 方块：一个暖色哑光方块和一个较小的半光滑方块，检验硬边、接触阴影与颜色反弹。
    cube_x, cube_z = 12.0, 20.2  # 近岸方块位置，放在湖右侧。
    cube_ground = field.height(cube_x, cube_z)  # 地面高度。
    add_box(vertices, (cube_x, cube_ground + 0.62, cube_z), (0.62, 0.62, 0.62), 0.24,
            (0.22, 0.075, 0.032), 0.68)  # 暖赭色哑光方块。
    small_x, small_z = 11.5, 25.8  # 第二个方块，石台右侧。
    small_ground = field.height(small_x, small_z)  # 地面高度。
    add_box(vertices, (small_x, small_ground + 0.38, small_z), (0.38, 0.38, 0.38), -0.18,
            (0.13, 0.14, 0.15), 0.22)  # 偏冷的半光滑方块。
    # 立石：三根高低不同的石板，把低角度阳光切出条纹光柱。
    monolith_specs = (  # 水平位置、宽度、深度、高度、倾角。
        (-10.5, 27.0, 0.55, 0.45, 4.6, 0.10),
        (-13.2, 23.2, 0.62, 0.52, 3.7, -0.16),
        (-3.2, 29.5, 0.45, 0.38, 3.0, 0.15),
    )
    for x, z, half_w, half_d, height, tilt in monolith_specs:  # 逐根生成。
        ground = field.height(x, z)  # 底部埋进地面。
        albedo = (0.105 + rng.random() * 0.015, 0.100 + rng.random() * 0.012, 0.092 + rng.random() * 0.010)  # 微弱色差。
        add_box(vertices, (x, ground + height * 0.5 - 0.35, z), (half_w, height * 0.5, half_d), tilt,
                albedo, 0.66)  # 立石本体。
    # 几块散落的小石头，给近景提供额外接触阴影样本。
    for index in range(7):  # 固定数量，不做实例化。
        x = 12.0 + rng.uniform(-5.0, 5.0)  # 相机右侧岸上。
        z = 24.0 + rng.uniform(-4.0, 5.0)  # 近岸一带。
        size = rng.uniform(0.16, 0.38)  # 石头半径。
        ground = field.height(x, z)  # 地面高度。
        albedo = (0.09 + rng.random() * 0.02, 0.088 + rng.random() * 0.02, 0.080 + rng.random() * 0.02)  # 石灰岩灰。
        add_box(vertices, (x, ground + size * 0.55, z), (size, size * 0.8, size * 0.9), rng.uniform(0.0, 3.1),
                albedo, 0.70)  # 半埋进草里。
    triangles = len(vertices) // 11 // 3  # 每十一个浮点一个顶点，每三个顶点一个三角形。
    stats = {"shelfTop": shelf_top, "sphereCenters": [(shelf_x + s[0], shelf_top + 0.78, shelf_z + s[1]) for s in sphere_specs]}
    return vertices, triangles, stats


def build() -> dict:
    """构建整个场景，返回地形、物体与水面三组顶点和统计。"""
    field = HeightField()  # 高度场是唯一地形来源。
    terrain_vertices, terrain_triangles = build_terrain(field)  # 地形网格。
    object_vertices, object_triangles, stats = build_objects(field)  # 石台、球、方块与立石。
    water_vertices, water_triangles = build_water()  # 平面水片。
    camera_ground = field.height(CAMERA_START[0], CAMERA_START[1])  # 相机脚下地面。
    return {
        "field": field,
        "terrain": terrain_vertices,
        "terrainTriangles": terrain_triangles,
        "objects": object_vertices,
        "objectTriangles": object_triangles,
        "water": water_vertices,
        "waterTriangles": water_triangles,
        "cameraGround": camera_ground,
        "stats": stats,
    }


if __name__ == "__main__":
    """直接运行时打印关键高度，调机位与物体落点用。"""
    world = build()  # 构建一次。
    field = world["field"]  # 高度场。
    print("相机地面", round(world["cameraGround"], 3))  # 相机脚下高度。
    print("石台顶面", round(world["stats"]["shelfTop"], 3))  # 石台顶面高度。
    print("球心", [(round(p[0], 1), round(p[1], 2), round(p[2], 1)) for p in world["stats"]["sphereCenters"]])  # 球心。
    for name, x, z in (("湖心", 0.0, -8.0), ("南岸", 0.0, 26.0), ("立石", -10.5, 27.0), ("北方远景", 0.0, -140.0)):
        print(name, round(field.height(x, z), 2))  # 关键点高度。
    print("三角形：地形", world["terrainTriangles"], "物体", world["objectTriangles"], "水面", world["waterTriangles"])  # 规模。
