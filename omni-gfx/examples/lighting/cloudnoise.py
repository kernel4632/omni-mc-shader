"""体积云与雾用的三维噪声：纯 Python 生成、磁盘缓存、启动时上传成纹理。

调用位置：`omni-gfx/examples/lighting/render.py` 启动时调用 `ensure()`。
调用示例：渲染入口启动前调用 `ensure()`，取得带磁盘缓存的三维噪声字节。

设计原因与取舍：
    体积云的形状来自三维噪声，不再用二维贴图拼贴，否则云的侧面会变成一层纸。
    项目不引入 NumPy 或图像库，生成器只用标准库；代价是首次启动要几秒，
    因此把固定种子的原始字节缓存到 `.dev/omni-gfx/lighting/`，后续启动直接读取。
    生成规则是平铺的：值噪声与 Worley 都在格子边界取模，纹理重复时接缝不可见。
"""
from __future__ import annotations

import math  # 距离与平滑曲线。
import random  # 固定种子的特征点。
import time  # 首次生成时打印耗时。
from pathlib import Path  # 缓存路径。

HERE = Path(__file__).resolve().parent  # 当前示例目录。
ROOT = HERE.parents[2]  # 仓库根目录。
CACHE = ROOT / ".dev" / "omni-gfx" / "lighting" / "noise-v3"  # 生成缓存；开发产物不提交。改噪声参数时换版本号，避免读到旧体素。

BASE_SIZE = 64  # 生成基础形状噪声时的边长；参考纹理存在时改用 128 立方。
DETAIL_SIZE = 48  # 细节侵蚀噪声边长；高频，尺寸小也看不出块。
CURL_SIZE = 256  # 二维扰动噪声边长；采样次数多，分辨率高一些。
SEED = 20261026  # 固定种子，保证不同机器生成同一片云。
REFERENCE_BASE = ROOT / "references" / "iterationT" / "shaders" / "texture" / "CloudNoise_128_128_128.bin"  # 参考光影的 128 立方 Perlin-Worley；存在时优先使用。


def _hash3(ix: int, iy: int, iz: int, seed: int) -> float:
    """三维整数哈希，返回零到一；用于值噪声的格点随机值。"""
    value = ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1442695041  # 三个大奇数混合坐标。
    value = (value ^ (value >> 13)) * 1274126177  # 异或移位后再乘一次。
    value &= 0xFFFFFFFF  # 保留三十二位。
    return ((value ^ (value >> 16)) & 0xFFFF) / 65535.0  # 压到零到一。


def _smooth(value: float) -> float:
    """五次平滑曲线，值噪声插值在格点处一阶与二阶导数都为零。"""
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)


def value3(x: float, y: float, z: float, cells: int) -> float:
    """平铺三维值噪声：先把坐标乘到格子数，再对八个角做三线性插值。"""
    px = x * cells  # 横向格坐标。
    py = y * cells  # 竖向格坐标。
    pz = z * cells  # 纵向格坐标。
    ix = math.floor(px)  # 左下后格点。
    iy = math.floor(py)
    iz = math.floor(pz)
    fx = _smooth(px - ix)  # 格内平滑权重。
    fy = _smooth(py - iy)
    fz = _smooth(pz - iz)
    total = 0.0  # 插值结果。
    for dz in (0, 1):  # 八个角逐个加权。
        wz = fz if dz else 1.0 - fz
        for dy in (0, 1):  # 竖向。
            wy = fy if dy else 1.0 - fy
            for dx in (0, 1):  # 横向。
                wx = fx if dx else 1.0 - fx
                total += _hash3((ix + dx) % cells, (iy + dy) % cells, (iz + dz) % cells, SEED) * wx * wy * wz  # 平铺取模。
    return total  # 零到一。


def fbm3(x: float, y: float, z: float, octaves: int) -> float:
    """多层值噪声叠加，用于云的大尺度覆盖与雾的缓慢流动。"""
    total = 0.0  # 累积。
    amplitude = 1.0  # 当前振幅。
    normalization = 0.0  # 归一化分母。
    frequency = 1.0  # 当前频率倍率。
    for _ in range(octaves):  # 逐层叠加。
        total += value3(x * frequency, y * frequency, z * frequency, 4) * amplitude  # 四格一层。
        normalization += amplitude  # 累积分母。
        amplitude *= 0.5  # 高频减弱。
        frequency *= 2.0  # 频率翻倍。
    return total / max(normalization, 1e-6)  # 回到零到一。


def _feature_points(cells: int, seed: int) -> list[list[tuple[float, float, float]]]:
    """为每个格子生成一个特征点，坐标在格内零到一。"""
    rng = random.Random(seed)  # 固定种子。
    return [[[(rng.random(), rng.random(), rng.random()) for _ in range(cells)] for _ in range(cells)] for _ in range(cells)]  # 三维格点表。


def worley3(size: int, cells: int, seed: int, falloff: float = 5.0) -> list[float]:
    """平铺三维 Worley 噪声，返回一减最近距离；靠近特征点的地方接近一。"""
    points = _feature_points(cells, seed)  # 每格一个特征点。
    scale = cells / size  # 像素坐标换到格坐标。
    result = [0.0] * (size * size * size)  # 输出体素。
    for z in range(size):  # 逐层。
        fz = z * scale  # 当前格坐标。
        cz = int(fz)  # 当前格。
        for y in range(size):  # 逐行。
            fy = y * scale  # 当前格坐标。
            cy = int(fy)  # 当前格。
            row = (z * size + y) * size  # 行起始下标。
            for x in range(size):  # 逐列。
                fx = x * scale  # 当前格坐标。
                cx = int(fx)  # 当前格。
                best = 9.0  # 最近距离平方。
                for dz in (-1, 0, 1):  # 检查二十七个邻格。
                    for dy in (-1, 0, 1):  # 竖向。
                        for dx in (-1, 0, 1):  # 横向。
                            point = points[(cx + dx) % cells][(cy + dy) % cells][(cz + dz) % cells]  # 平铺特征点。
                            px = (point[0] + cx + dx) / cells  # 特征点世界坐标。
                            py = (point[1] + cy + dy) / cells
                            pz = (point[2] + cz + dz) / cells
                            distance = (fx / cells - px) ** 2 + (fy / cells - py) ** 2 + (fz / cells - pz) ** 2  # 距离平方。
                            if distance < best:  # 保留最近。
                                best = distance
                result[row + x] = 1.0 - min(math.sqrt(best) * falloff, 1.0)  # 反相，云块内部接近一。
    return result  # 扁平体素列表。


def _write_raw(path: Path, channels: list[list[float]]) -> None:
    """把若干通道按 RGBA 交错写成字节；值先夹紧再量化到八位。"""
    count = len(channels[0])  # 体素数量。
    data = bytearray(count * 4)  # 四通道字节。
    for index in range(count):  # 逐体素。
        target = index * 4  # 输出偏移。
        for channel in range(4):  # 四个通道。
            value = channels[channel][index] if channel < len(channels) else 0.0  # 缺省通道为零。
            data[target + channel] = max(0, min(255, int(value * 255.0 + 0.5)))  # 夹紧量化。
    path.parent.mkdir(parents=True, exist_ok=True)  # 缓存目录可能不存在。
    path.write_bytes(bytes(data))  # 原始字节，不含图片头。


def _build_base() -> list[list[float]]:
    """基础形状噪声：R 是低频覆盖，G/B/A 是三种尺度的云块。"""
    size = BASE_SIZE  # 输出边长。
    low = [0.0] * (size * size * size)  # 低频覆盖。
    for z in range(size):  # 逐层填低频。
        nz = z / size  # 归一化坐标。
        for y in range(size):  # 逐行。
            ny = y / size  # 归一化坐标。
            row = (z * size + y) * size  # 行起始。
            for x in range(size):  # 逐列。
                low[row + x] = fbm3(x / size, ny, nz, 4)  # 四层低频值噪声。
    blob4 = worley3(size, 4, SEED + 1, 4.4)  # 大云团。
    blob8 = worley3(size, 8, SEED + 2, 4.2)  # 中云团。
    blob16 = worley3(size, 16, SEED + 3, 4.8)  # 小云团。
    red = [0.0] * len(low)  # 覆盖通道。
    for index in range(len(low)):  # 逐体素混合。
        shape = low[index] * 0.50 + blob4[index] * 0.50  # 低频起伏加大云团。
        red[index] = min(max((shape - 0.30) * 2.2, 0.0), 1.0)  # 拉高对比，留出蓝天缝隙。
    return [red, blob4, blob8, blob16]  # 四通道。


def _build_detail() -> list[list[float]]:
    """细节侵蚀噪声：三种高频 Worley，用来削薄云的边缘。"""
    size = DETAIL_SIZE  # 输出边长。
    return [worley3(size, 8, SEED + 11, 7.0), worley3(size, 16, SEED + 12, 6.0), worley3(size, 32, SEED + 13, 5.0), [0.0] * (size ** 3)]  # 三个频率加空通道。


def _build_curl() -> list[list[float]]:
    """二维扰动噪声：R 是低频，G 是高频，W 是云的水平扭曲量。"""
    size = CURL_SIZE  # 输出边长。
    low = [0.0] * (size * size)  # 低频通道。
    high = [0.0] * (size * size)  # 高频通道。
    curl = [0.0] * (size * size)  # 扭曲通道。
    for y in range(size):  # 逐行。
        ny = y / size  # 归一化纵坐标。
        for x in range(size):  # 逐列。
            nx = x / size  # 归一化横坐标。
            low[y * size + x] = fbm3(nx, ny, 0.37, 4)  # 四层低频。
            high[y * size + x] = fbm3(nx * 4.0, ny * 4.0, 0.71, 3)  # 更细的斑块。
            curl[y * size + x] = fbm3(nx * 2.0 + 0.13, ny * 2.0 + 0.57, 0.21, 3)  # 平滑扭曲。
    return [low, high, [0.0] * (size * size), curl]  # 四通道。


def _load_or_build(name: str, builder) -> bytes:
    """按固定文件名读取缓存；不存在时生成并写入。"""
    path = CACHE / name  # 缓存文件。
    if path.is_file():  # 已经有同一版本的文件。
        return path.read_bytes()  # 直接读取。
    started = time.perf_counter()  # 首次生成计时。
    channels = builder()  # 生成四通道。
    _write_raw(path, channels)  # 写入缓存。
    print(f"生成 {name}：{time.perf_counter() - started:.1f} 秒")  # 告诉用户首次启动为什么慢。
    return path.read_bytes()  # 返回字节。


def ensure() -> dict[str, bytes]:
    """返回三张噪声的原始字节，缺失时生成；调用方负责上传纹理。

    基础云噪声优先读取参考光影的 128 立方 Perlin-Worley：它的通道分布与 Nubis
    的密度公式直接对应，云块比本地 64 立方生成的更细，也不需要每次重新生成。
    """
    if REFERENCE_BASE.is_file():  # 参考包存在时直接用它的云噪声。
        base = REFERENCE_BASE.read_bytes()  # 八兆字节，启动读取很快。
    else:  # 没有参考包时回退到本地生成，保证测试世界仍能独立启动。
        base = _load_or_build(f"base-{BASE_SIZE}.rgba", _build_base)
    return {
        "base": base,  # 基础形状。
        "detail": _load_or_build(f"detail-{DETAIL_SIZE}.rgba", _build_detail),  # 细节侵蚀。
        "curl": _load_or_build(f"curl-{CURL_SIZE}.rgba", _build_curl),  # 二维扰动。
    }
