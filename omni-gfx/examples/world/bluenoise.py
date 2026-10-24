"""蓝噪声抖动图：用频域高通与秩排序生成六十四像素见方的贴图数据。

调用位置：`render.py` 启动时调用 `texture_data()`，把结果上传成一张单通道纹理。
调用示例：
    data = texture_data()  # 4096 个字节，按行优先排列，零到二百五十五。
设计原因与取舍：
    项目不引入图片资源和数值库，蓝噪声只在启动时算一次。
    做法是先取固定种子的白噪声，做二维快速傅里叶变换，把低频压掉再变回来，
    最后按数值大小排成均匀分布；这样得到的点分布比白噪声更均匀，抖动在空间上
    不结块，时间累积后不会留下固定的斜条纹。
    这是蓝噪声的近似构造，频谱不如逐点优化的经典算法干净，但同一份代码在任何
    机器上都生成同一张贴图，不需要额外文件。
"""
from __future__ import annotations

import math  # 圆周率与三角函数。
import random  # 固定种子的白噪声，保证可重复。

SIZE = 64  # 贴图边长，必须与生成库 `ogxBlueNoise` 里写死的六十四一致。


def _fft(values: list[complex], inverse: bool) -> None:
    """原地做基二快速傅里叶变换，`values` 的长度必须是二的幂。

    蝶形运算按位反转重排输入，再逐级合并；整数索引避免递归，纯 Python 也能跑得动。
    """
    count = len(values)  # 变换长度。
    j = 0  # 位反转后的目标下标。
    for i in range(1, count):  # 标准位反转重排。
        bit = count >> 1
        while j & bit:  # 找到下一个空位。
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:  # 只在后半段交换，避免换回去。
            values[i], values[j] = values[j], values[i]
    length = 2  # 当前合并的块长度。
    while length <= count:
        angle = (2.0 if inverse else -2.0) * math.pi / length  # 正变换取负角。
        step = complex(math.cos(angle), math.sin(angle))  # 每一级的单位旋转。
        half = length >> 1  # 半个块的长度。
        for start in range(0, count, length):  # 逐块合并。
            factor = 1 + 0j  # 块内旋转因子。
            for offset in range(start, start + half):  # 蝶形的一对。
                left = values[offset]
                right = values[offset + half] * factor
                values[offset] = left + right
                values[offset + half] = left - right
                factor *= step
        length <<= 1
    if inverse:  # 逆变换要除以长度。
        scale = 1.0 / count
        for index in range(count):
            values[index] *= scale


def _transform2d(field: list[complex], inverse: bool) -> None:
    """对二维数组做可分离变换：先逐行，再逐列。"""
    for row in range(SIZE):  # 每一行一次一维变换。
        line = field[row * SIZE:(row + 1) * SIZE]  # 切片复制出一行，变换后写回。
        _fft(line, inverse)
        field[row * SIZE:(row + 1) * SIZE] = line
    for column in range(SIZE):  # 每一列一次一维变换。
        line = [field[row * SIZE + column] for row in range(SIZE)]
        _fft(line, inverse)
        for row in range(SIZE):
            field[row * SIZE + column] = line[row]


def _blue_field() -> list[float]:
    """生成高频占优的随机场，低频被压到接近零。

    振幅按到直流点的距离线性增长：中心的最低频几乎不动，越靠边的高频保留越多。
    这样排序后留下的是细密而不结块的点，正是抖动需要的分布。
    """
    generator = random.Random(20261024)  # 固定种子，换机器也得到同一张图。
    field = [complex(generator.random() - 0.5, 0.0) for _ in range(SIZE * SIZE)]  # 零均值白噪声。
    _transform2d(field, False)  # 换到频域。
    half = SIZE // 2  # 频率折叠后的半宽，用来把负频率也映射到同一半径。
    for y in range(SIZE):
        for x in range(SIZE):
            fx = (x if x <= half else x - SIZE) / half  # 横向频率，范围负一到一。
            fy = (y if y <= half else y - SIZE) / half  # 纵向频率。
            radius = math.sqrt(fx * fx + fy * fy)  # 到直流点的距离，零到约一点四。
            weight = min(radius * 4.0, 1.0) ** 1.5  # 低频压得狠，高频接近原样。
            field[y * SIZE + x] *= weight  # 只调整振幅，相位保留白噪声的随机性。
    _transform2d(field, True)  # 变回空间域。
    return [value.real for value in field]  # 虚部是舍入噪声，只取实部。


def texture_data() -> bytes:
    """返回排好序的蓝噪声字节，数值近似均匀分布。

    排序后按名次映射到零到二百五十五，直方图因此完全平坦，
    `ogxBlueNoise` 拿到的就是一维均匀抖动。
    """
    field = _blue_field()  # 高频占优的随机场。
    order = sorted(range(len(field)), key=lambda index: field[index])  # 由小到大排名。
    result = bytearray(len(field))  # 输出字节。
    for rank, index in enumerate(order):  # 名次就是灰度值。
        result[index] = round(rank * 255.0 / (len(field) - 1))  # 均匀铺满零到二百五十五。
    return bytes(result)
