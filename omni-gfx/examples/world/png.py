"""不依赖第三方库的 PNG 读写，用于截图、贴图预处理与并排对比图。

调用位置：
    `omni-gfx/examples/world/render.py` 保存截图时调用 `write_rgb`；
    `omni-gfx/tools/prepare_textures.py` 下载 CC0 贴图后调用 `read_png` 与 `write_rgba`；
    并排对比脚本读取两张图片时调用 `read_png`。
调用示例：`write_rgb(path, width, height, pixels)`。

设计原因与取舍：
    测试世界只依赖标准库与 OpenGL，不把 Pillow 或 numpy 变成运行前提。
    解码只支持本项目实际用到的八位 RGB/RGBA、非隔行 PNG；遇到其他格式直接报错，
    不静默返回一张错色图片。
    写入支持 RGB 与 RGBA 两种，截图沿用自下而上的翻转约定，贴图预处理则按原方向写入。
"""
from __future__ import annotations

import struct  # PNG 块长度与文件头。
import zlib  # 解压与压缩像素数据，并计算块校验。


def _chunk(kind: bytes, data: bytes) -> bytes:
    """返回一个 PNG 数据块：长度、类型、内容与 CRC 校验。"""
    # 长度与校验都按图片规范写，任何一块算错都会让查看器拒绝整张图。
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def _paeth(left: int, up: int, upper_left: int) -> int:
    """Paeth 预测：选与当前像素最接近的邻居，照片类贴图的残差因此更小。"""
    estimate = left + up - upper_left  # 线性预测。
    distance_left = abs(estimate - left)  # 与左邻居的差。
    distance_up = abs(estimate - up)  # 与上邻居的差。
    distance_upper_left = abs(estimate - upper_left)  # 与左上邻居的差。
    if distance_left <= distance_up and distance_left <= distance_upper_left:  # 左邻居最近。
        return left
    if distance_up <= distance_upper_left:  # 上邻居最近。
        return up
    return upper_left  # 左上邻居最近。


def read_png(path) -> tuple[int, int, int, bytes]:
    """读取八位 RGB 或 RGBA PNG，返回宽、高、通道数与自上而下的像素字节。

    只支持非隔行、位深八；其他格式抛出 ValueError 并写明原因。
    返回的像素顺序与 PNG 文件一致，左上角是第一个像素。
    """
    data = path.read_bytes() if hasattr(path, "read_bytes") else bytes(path)  # 兼容路径与原始字节。
    if data[:8] != b"\x89PNG\r\n\x1a\n":  # PNG 固定签名。
        raise ValueError("不是 PNG 文件")
    offset = 8  # 从签名之后开始读块。
    width = height = bit_depth = color_type = interlace = 0  # 文件头字段。
    compressed = bytearray()  # 收集全部 IDAT，部分编码器会拆成多块。
    while offset < len(data):  # 逐块扫描。
        length = struct.unpack(">I", data[offset:offset + 4])[0]  # 块内容长度。
        kind = data[offset + 4:offset + 8]  # 四字节块名。
        payload = data[offset + 8:offset + 8 + length]  # 块内容。
        offset += 12 + length  # 跳过长、类型、内容与校验。
        if kind == b"IHDR":  # 图像头。
            width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":  # 压缩像素。
            compressed.extend(payload)
        elif kind == b"IEND":  # 结束块。
            break
    if bit_depth not in (8, 16) or interlace != 0 or color_type not in (0, 2, 4, 6):  # 只接受本项目用到的格式。
        raise ValueError(f"只支持八位或十六位非隔行灰度/RGB/RGBA PNG：位深 {bit_depth}，颜色类型 {color_type}，隔行 {interlace}")
    source_channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]  # 文件里实际存的通道数。
    channels = 4 if color_type in (4, 6) else 3  # 统一输出 RGB 或 RGBA。
    sample_bytes = bit_depth // 8  # 每个通道占几个字节。
    stride = width * source_channels * sample_bytes  # 每行字节数。
    raw = zlib.decompress(bytes(compressed))  # 解压全部扫描行。
    expected = (stride + 1) * height  # 每行带一个过滤字节。
    if len(raw) != expected:  # 长度不对说明文件损坏或格式判断错误。
        raise ValueError(f"PNG 像素长度不符：{len(raw)}，期望 {expected}")
    filtered = bytearray(stride * height)  # 去掉过滤字节后的原始像素。
    previous = bytearray(stride)  # 上一行，第一行按全零处理。
    source = 0  # 当前读取位置。
    pixel_bytes = source_channels * sample_bytes  # 过滤器按完整像素跨距参考左邻居。
    for row in range(height):  # 逐行还原过滤。
        filter_type = raw[source]  # 当前行的过滤方式。
        source += 1
        line = bytearray(raw[source:source + stride])  # 当前行残差。
        source += stride
        if filter_type == 1:  # 减法滤波：只参考左邻居。
            for index in range(pixel_bytes, stride):
                line[index] = (line[index] + line[index - pixel_bytes]) & 0xFF
        elif filter_type == 2:  # 向上滤波：只参考上邻居。
            for index in range(stride):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif filter_type == 3:  # 平均滤波：左与上的平均。
            for index in range(stride):
                left = line[index - pixel_bytes] if index >= pixel_bytes else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif filter_type == 4:  # Paeth：三者中最接近的邻居。
            for index in range(stride):
                left = line[index - pixel_bytes] if index >= pixel_bytes else 0
                upper_left = previous[index - pixel_bytes] if index >= pixel_bytes else 0
                line[index] = (line[index] + _paeth(left, previous[index], upper_left)) & 0xFF
        elif filter_type != 0:  # 零到四以外的过滤器不存在。
            raise ValueError(f"未知 PNG 过滤器：{filter_type}")
        filtered[row * stride:(row + 1) * stride] = line  # 写入结果。
        previous = line  # 下一行要用这一行做参考。
    if sample_bytes == 1:  # 八位图直接使用过滤结果。
        source_pixels = filtered
    else:  # 十六位统一取高字节，等价于除以 257，足够贴图使用。
        source_pixels = bytearray(width * height * source_channels)
        for index in range(width * height * source_channels):
            source_pixels[index] = filtered[index * 2]
    if source_channels == channels:  # RGB/RGBA 不需要扩通道。
        return width, height, channels, bytes(source_pixels)
    pixels = bytearray(width * height * channels)  # 灰度或灰度加透明要扩成彩色。
    for index in range(width * height):  # 逐像素展开。
        gray = source_pixels[index * source_channels]
        alpha = source_pixels[index * source_channels + 1] if source_channels == 2 else 255
        pixels[index * channels] = gray
        pixels[index * channels + 1] = gray
        pixels[index * channels + 2] = gray
        if channels == 4:
            pixels[index * channels + 3] = alpha
    return width, height, channels, bytes(pixels)


def write_rgb(path, width: int, height: int, pixels: bytes) -> None:
    """把自下而上的 RGB 像素写成 PNG 文件。

    OpenGL 读回的像素原点在左下，PNG 原点在左上；这里负责翻转。
    """
    stride = width * 3  # 每行字节数。
    if len(pixels) != stride * height:  # 尺寸与数据必须匹配，避免写出花屏。
        raise ValueError(f"像素数据长度不符：{len(pixels)}，期望 {stride * height}")
    raw = bytearray()  # 过滤字节与像素。
    for row in range(height - 1, -1, -1):  # OpenGL 原点在左下，PNG 原点在左上。
        raw.append(0)  # 每行使用零号过滤，最简单也最容易核对。
        start = row * stride
        raw.extend(pixels[start:start + stride])  # 追加这一整行。
    _write(path, width, height, 2, bytes(raw))  # 三通道、八位。


def write_rgba(path, width: int, height: int, pixels: bytes, flip: bool = False) -> None:
    """把八位 RGBA 像素写成 PNG；`flip` 为真时按自下而上翻转。

    贴图预处理使用默认的自上而下；需要从 OpenGL 读回结果时再打开翻转。
    """
    stride = width * 4  # 每行字节数。
    if len(pixels) != stride * height:  # 尺寸不符直接报错。
        raise ValueError(f"像素数据长度不符：{len(pixels)}，期望 {stride * height}")
    raw = bytearray()  # 过滤字节与像素。
    rows = range(height - 1, -1, -1) if flip else range(height)  # 需要时翻转行序。
    for row in rows:  # 逐行拼接。
        raw.append(0)  # 不使用过滤器。
        start = row * stride
        raw.extend(pixels[start:start + stride])
    _write(path, width, height, 6, bytes(raw))  # 四通道、八位。


def _write(path, width: int, height: int, color_type: int, raw: bytes) -> None:
    """写出 PNG 公共部分；颜色类型二为 RGB，六为 RGBA。"""
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)  # 八位、无隔行。
    body = b"".join((
        b"\x89PNG\r\n\x1a\n",  # PNG 固定签名。
        _chunk(b"IHDR", header),  # 图像头。
        _chunk(b"IDAT", zlib.compress(raw, 9)),  # 压缩后的像素。
        _chunk(b"IEND", b""),  # 结束块。
    ))
    path.write_bytes(body)  # 一次写完整文件，失败时不会留下只有一半的图片。
