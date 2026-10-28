"""测试世界的材质贴图加载：地面纹理数组与植物卡片。

调用位置：
    `omni-gfx/examples/world/render.py` 创建 `World` 时调用 `load()` 一次。
调用示例：`textures = load()`；退出时删除字典里的纹理编号。

设计原因与取舍：
    地面有草地、泥土、岩石、湿沙、腐殖土、树皮六种材质，每种三张图。
    如果每种材质各用一组 sampler，片元阶段很快会超过 OpenGL 3.3 保证的十六个纹理单元；
    改成 `sampler2DArray` 后，六层颜色只占一个单元，法线与粗糙度各一个。
    颜色图用 sRGB 内部格式让硬件在采样时转线性，法线与粗糙度保持线性数据；
    这两类数据混用同一个格式会让法线方向偏亮、粗糙度整体偏干。
    植物卡片是带透明通道的单张图，使用 sRGB 加 Alpha 的格式，并按 alpha 测试裁切。
"""
from __future__ import annotations

import sys  # 同目录模块导入。
from pathlib import Path  # 资源路径。

from OpenGL import GL  # 纹理上传与采样参数。

HERE = Path(__file__).resolve().parent  # 测试世界目录。
sys.path.insert(0, str(HERE))  # 复用同目录 PNG 解码。
import png  # 只依赖标准库的 PNG 读取。

ASSETS = HERE / "assets"  # 提交到仓库的贴图。
SIZE = 512  # 所有材质统一边长，纹理数组要求每层尺寸一致。
LAYERS = ("grass", "dirt", "rock", "sand", "forest", "bark")  # 与 terrain.MATERIAL_* 对应。
CARD_NAMES = ("grass_card", "leaf_card", "flower_card")  # 三张植物卡片。


def _flip_rows(pixels: bytes, channels: int) -> bytes:
    """把自上而下的图片行序翻成 OpenGL 的下到上，避免草根朝上、树皮倒纹。

    准备工具按普通图片方向保存；OpenGL 的纹理原点在左下，
    不翻转时带方向的贴图会上下颠倒。无缝地面纹理也会让法线绿通道反向。
    """
    stride = SIZE * channels  # 每行字节数。
    out = bytearray(len(pixels))  # 结果。
    for row in range(SIZE):  # 逐行搬到对称位置。
        out[row * stride:(row + 1) * stride] = pixels[(SIZE - 1 - row) * stride:(SIZE - row) * stride]
    return bytes(out)


def _read_layer(prefix: str, role: str) -> bytes:
    """读取一张 512 材质图并返回翻转后的 RGB 字节；尺寸不符直接报错。"""
    width, height, channels, pixels = png.read_png(ASSETS / f"{prefix}_{role}.png")
    if (width, height) != (SIZE, SIZE):
        raise ValueError(f"贴图尺寸应为 {SIZE}：{prefix}_{role} 是 {width}×{height}")
    if channels != 3:  # 材质图在准备阶段已经去掉透明通道。
        raise ValueError(f"材质图应为 RGB：{prefix}_{role}")
    return _flip_rows(pixels, 3)


def _array_texture(internal_format: int, layers: list[bytes]) -> int:
    """把六层同尺寸 RGB 数据上传成二维纹理数组，返回纹理编号。

    数组纹理的每一层共享采样参数与 mipmap，着色器用第三个坐标选层。
    各向异性过滤能保住远处掠射角的地面细节，驱动不支持时退回三线性。
    """
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D_ARRAY, texture)
    GL.glTexImage3D(GL.GL_TEXTURE_2D_ARRAY, 0, internal_format, SIZE, SIZE, len(layers), 0,
                    GL.GL_RGB, GL.GL_UNSIGNED_BYTE, b"".join(layers))
    GL.glTexParameteri(GL.GL_TEXTURE_2D_ARRAY, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D_ARRAY, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D_ARRAY, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)
    GL.glTexParameteri(GL.GL_TEXTURE_2D_ARRAY, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)
    GL.glGenerateMipmap(GL.GL_TEXTURE_2D_ARRAY)
    extensions = GL.glGetString(GL.GL_EXTENSIONS) or b""  # 扩展名列表是字节串，缺失时用空串。
    if b"GL_EXT_texture_filter_anisotropic" in extensions:  # 只有驱动声明支持时才读上限。
        maximum = GL.glGetFloatv(0x84FF)  # GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT。
        if maximum and maximum > 1.0:
            GL.glTexParameterf(GL.GL_TEXTURE_2D_ARRAY, 0x84FE, min(8.0, maximum))  # GL_TEXTURE_MAX_ANISOTROPY_EXT。
    return texture


def _card_texture(name: str) -> int:
    """上传一张带透明通道的植物卡片，返回纹理编号。"""
    width, height, channels, pixels = png.read_png(ASSETS / f"{name}.png")
    if (width, height) != (SIZE, SIZE) or channels != 4:
        raise ValueError(f"卡片应为 {SIZE}×{SIZE} RGBA：{name}")
    pixels = _flip_rows(pixels, 4)  # 卡片根在底边，必须翻转后上传。
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_SRGB8_ALPHA8, SIZE, SIZE, 0,
                    GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, pixels)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    GL.glGenerateMipmap(GL.GL_TEXTURE_2D)
    return texture


def load() -> dict:
    """加载全部材质，返回纹理编号字典。

    返回值键：`albedo`、`normal`、`rough` 三个纹理数组，
    `grass_card`、`leaf_card`、`flower_card` 三张单图。
    调用方负责在退出时删除这些纹理。
    """
    albedo = [_read_layer(prefix, "albedo") for prefix in LAYERS]
    normal = [_read_layer(prefix, "normal") for prefix in LAYERS]
    rough = [_read_layer(prefix, "rough") for prefix in LAYERS]
    textures = {
        "albedo": _array_texture(GL.GL_SRGB8, albedo),
        "normal": _array_texture(GL.GL_RGB8, normal),
        "rough": _array_texture(GL.GL_RGB8, rough),
    }
    for name in CARD_NAMES:
        textures[name] = _card_texture(name)
    GL.glBindTexture(GL.GL_TEXTURE_2D_ARRAY, 0)
    GL.glBindTexture(GL.GL_TEXTURE_2D, 0)
    return textures
