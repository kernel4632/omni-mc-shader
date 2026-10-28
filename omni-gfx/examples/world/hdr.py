"""Radiance RGBE 高动态范围图的读取，用于真实天空背景。

调用位置：
    `omni-gfx/tools/prepare_textures.py` 下载 CC0 天空后用本模块检查尺寸；
    `omni-gfx/examples/world/render.py` 启动时调用 `read_hdr` 并把浮点像素上传显卡。
调用示例：`width, height, pixels = read_hdr(path)`。

设计原因与取舍：
    测试世界原本用程序化大气加体积云，云的形状和边缘在低分辨率下容易糊成团。
    真实天空照片能立刻提供可信的云层、色温和太阳位置，也让环境光与水面反射同源。
    这里只实现 Radiance 的两种扫描线编码（新式 RLE 与旧式平铺），
    不引入图像库；文件本身放在 `assets/`，来源与 CC0 许可记录在 `SOURCES.md`。
    解码结果保留线性辐射值，不做色调映射；显示曲线仍由后期阶段统一处理。
"""
from __future__ import annotations

from array import array  # 六兆字节级浮点缓冲用紧凑数组，上传时不必再转 Python 列表。
import math  # ldexp 还原 RGBE 的指数。
from pathlib import Path  # 资源路径。


def _read_header(data: bytes) -> tuple[int, int, int]:
    """解析 Radiance 头，返回宽、高与数据起始偏移。

    头以空行结束，分辨率单独写在空行之后；只接受 `32-bit_rle_rgbe`。
    """
    offset = 0
    while True:  # 逐行读头，直到空行。
        end = data.find(b"\n", offset)
        if end < 0:
            raise ValueError("HDR 头不完整")
        line = data[offset:end].strip()
        offset = end + 1
        if not line:  # 空行表示头结束。
            break
        if line.startswith(b"FORMAT=") and b"32-bit_rle_rgbe" not in line:
            raise ValueError(f"不支持的 HDR 格式：{line!r}")
    end = data.find(b"\n", offset)  # 分辨率行在空行之后。
    if end < 0:
        raise ValueError("HDR 缺少分辨率")
    resolution = data[offset:end].split()
    offset = end + 1
    if len(resolution) != 4 or resolution[0] != b"-Y" or resolution[2] != b"+X":
        raise ValueError(f"不支持的 HDR 方向：{resolution!r}")
    height = int(resolution[1])
    width = int(resolution[3])
    if width <= 0 or height <= 0:
        raise ValueError("HDR 头缺少尺寸")
    return width, height, offset


def _decode_scanline(data: bytes, offset: int, width: int) -> tuple[list[int], int]:
    """解码一行 RGBE 扫描线，返回 RGBA 字节与新的偏移。

    新式编码以 2、2、高字节、低字节开头；每通道再做游程编码。
    旧式编码直接按像素读四个字节，也不做游程。
    """
    if width >= 8 and width < 32768 and offset + 4 <= len(data):
        if data[offset] == 2 and data[offset + 1] == 2:  # 新式 RLE 标记。
            scan_width = (data[offset + 2] << 8) | data[offset + 3]
            if scan_width == width:  # 宽度对得上才按 RLE 解。
                offset += 4
                channels = []
                for _ in range(4):  # 四个通道分别解压。
                    channel = bytearray()
                    while len(channel) < width:
                        count = data[offset]
                        offset += 1
                        if count > 128:  # 连续重复。
                            value = data[offset]
                            offset += 1
                            channel.extend(bytes((value,)) * (count - 128))
                        else:  # 原样复制。
                            channel.extend(data[offset:offset + count])
                            offset += count
                    channels.append(channel)
                pixels = []
                for index in range(width):  # 四个通道重新交错。
                    pixels.extend((channels[0][index], channels[1][index], channels[2][index], channels[3][index]))
                return pixels, offset
    pixels = []
    for _ in range(width):  # 旧式：一行就是宽度个四字节像素。
        pixels.extend(data[offset:offset + 4])
        offset += 4
    return pixels, offset


def read_hdr(path) -> tuple[int, int, bytes]:
    """读取 RGBE 文件，返回宽、高与线性 RGB 浮点字节。

    返回的浮点顺序是 RGB、行序从上到下；OpenGL 上传前由调用方翻转行序。
    """
    data = Path(path).read_bytes()
    width, height, offset = _read_header(data)
    floats = array("f")
    for _ in range(height):  # 逐行解码。
        pixels, offset = _decode_scanline(data, offset, width)
        for index in range(width):
            red, green, blue, exponent = pixels[index * 4:index * 4 + 4]
            if exponent == 0:  # 全零表示黑色。
                floats.extend((0.0, 0.0, 0.0))
                continue
            scale = math.ldexp(1.0, exponent - (128 + 8))  # RGBE 的公共指数。
            floats.extend((red * scale, green * scale, blue * scale))
    return width, height, floats.tobytes()


def read_hdr_array(path) -> tuple[int, int, array]:
    """读取 RGBE 文件并返回浮点数组，便于计算亮度与太阳位置。"""
    width, height, raw = read_hdr(path)
    values = array("f")
    values.frombytes(raw)
    return width, height, values
