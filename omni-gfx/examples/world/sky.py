"""真实天空背景：加载 CC0 全景 HDR，上传成等距柱状纹理并给出太阳方向。

调用位置：
    `omni-gfx/examples/world/render.py` 创建世界时调用 `load_sky()` 一次。
调用示例：`sky = load_sky(path)`；取得纹理编号与太阳方向。

设计原因与取舍：
    程序化体积云在半分辨率与十几步采样下，云边容易糊成团，达不到照片级的天空。
    这里改用 Poly Haven 的 CC0 全景天空，云层、色温与太阳位置来自真实拍摄；
    同一条等距柱状纹理同时生成天空立方体贴图，环境光与水面反射因此完全同源。
    HDR 保留太阳的高动态范围，泛光与曝光曲线能自然处理日落高光。
    文件放在 `assets/`，来源与 CC0 许可写在同目录 `SOURCES.md`。
"""
from __future__ import annotations

import math  # 太阳方向与旋转。
import sys  # 同目录 HDR 模块。
from array import array  # 浮点像素翻转。

from OpenGL import GL  # 纹理上传。

HERE = __import__("pathlib").Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import hdr  # Radiance RGBE 解码。

SKY_PATH = HERE / "assets" / "sky_wasteland.hdr"  # 蓝天与散云的纯天空全景。
SKY_ROTATION = math.radians(-54.0)  # 太阳转到相机右后方，画面里只有被照亮的散云。
SKY_STRENGTH = 0.90  # 环境光与水面反射用的天空倍率。
SKY_BACKGROUND = 0.25  # 背景天空倍率，云层保持可读的层次。


def rotate_y(vector, angle: float):
    """绕纵轴旋转一个三维方向，角度以弧度计。"""
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    return (vector[0] * cos_a - vector[2] * sin_a, vector[1], vector[0] * sin_a + vector[2] * cos_a)


def _sun_from_pixels(width: int, height: int, values: array) -> tuple[float, float, float]:
    """找出天空中最亮的像素，换算成世界方向并应用天空旋转。

    最亮像素就是太阳；日落的太阳可能被云遮住一部分，但亮度峰值仍然指向它。
    等距柱状的映射与 `sky.frag` 使用同一个公式，旋转方向也保持一致。
    """
    best_luma = -1.0
    best_x = best_y = 0
    for y in range(0, height, 2):  # 隔行扫描，太阳是几十像素宽的亮斑，不会漏。
        row = y * width * 3
        for x in range(0, width, 2):
            index = row + x * 3
            red, green, blue = values[index], values[index + 1], values[index + 2]
            luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
            if luma > best_luma:
                best_luma = luma
                best_x, best_y = x, y
    u = (best_x + 0.5) / width
    v = (best_y + 0.5) / height
    theta = v * math.pi  # 零在天顶，一在地平线以下。
    phi = (u - 0.5) * 2.0 * math.pi
    direction = (math.cos(phi) * math.sin(theta), math.cos(theta), math.sin(phi) * math.sin(theta))
    # 着色器把采样方向旋转 +SKY_ROTATION，纹理特征看起来就旋转了 -SKY_ROTATION。
    return rotate_y(direction, -SKY_ROTATION)


def load_sky() -> tuple[int, tuple[float, float, float]]:
    """上传天空纹理，返回纹理编号与太阳方向。"""
    width, height, raw = hdr.read_hdr(SKY_PATH)
    values = array("f")
    values.frombytes(raw)
    sun = _sun_from_pixels(width, height, values)
    # 压缩高光：太阳原值两万多，直接乘倍率会让整片天空过曝；
    # 用一条温和的肩部曲线把太阳压到几倍，云与蓝天仍保持原有颜色。
    compressed = array("f", (value / (1.0 + value * 0.10) for value in values))
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGB16F, width, height, 0, GL.GL_RGB, GL.GL_FLOAT,
                    compressed.tobytes())  # 等距柱状的 v=0 在天顶，与解码行序一致，上传时不再翻转。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    GL.glGenerateMipmap(GL.GL_TEXTURE_2D)
    GL.glBindTexture(GL.GL_TEXTURE_2D, 0)
    return texture, sun
