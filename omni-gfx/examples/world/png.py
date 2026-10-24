"""不依赖第三方库的 PNG 写入，用于保存测试世界截图。

调用位置：`omni-gfx/examples/world/render.py` 在截图模式下调用 `write_rgb`。
设计原因与取舍：
    只写八位 RGB，足够保存屏幕截图；压缩用标准库自带的压缩模块，避免引入第三方图片库。
    OpenGL 读回的像素是自下而上排列，这里在写文件前翻转，得到正常方向。
"""
from __future__ import annotations

import struct  # 写 PNG 块长度与类型。
import zlib  # 压缩像素数据并计算块校验。


def _chunk(kind: bytes, data: bytes) -> bytes:
    """返回一个 PNG 数据块：长度、类型、内容与 CRC 校验。

    `kind` 是四字节块名，`data` 是块内容；长度与校验都按 PNG 规范计算。
    """
    # 长度与校验都按图片规范写，任何一块算错都会让查看器拒绝整张图。
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)  # 网络字节序与标准校验。


def write_rgb(path, width: int, height: int, pixels: bytes) -> None:
    """把自下而上的 RGB 像素写成 PNG 文件。

    `pixels` 每像素三字节，长度必须是宽乘高乘三；函数不返回内容，
    写失败时由标准库异常向上报告，调用方统一处理。
    """
    stride = width * 3  # 每行字节数。
    if len(pixels) != stride * height:  # 尺寸与数据必须匹配，避免写出花屏。
        raise ValueError(f"像素数据长度不符：{len(pixels)}，期望 {stride * height}")
    # 逐行收集过滤字节与像素，最后一次性压缩。
    raw = bytearray()  # 过滤字节与像素。
    for row in range(height - 1, -1, -1):  # OpenGL 原点在左下，PNG 原点在左上。
        raw.append(0)  # 每行使用零号过滤，最简单也最容易核对。
        start = row * stride
        raw.extend(pixels[start:start + stride])  # 追加这一整行。
    # 图像头写明尺寸、位深、颜色类型与隔行方式。
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 八位、三通道、无隔行。
    body = b"".join((
        b"\x89PNG\r\n\x1a\n",  # PNG 固定签名。
        _chunk(b"IHDR", header),  # 图像头。
        _chunk(b"IDAT", zlib.compress(bytes(raw), 9)),  # 压缩后的像素。
        _chunk(b"IEND", b""),  # 结束块。
    ))
    # 一次写完整文件，失败时不会留下只有一半的图片。
    path.write_bytes(body)  # 写入磁盘。
