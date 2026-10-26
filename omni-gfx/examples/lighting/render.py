"""光影验证场景：简单地形、五种粗糙度的球、方块、湖面、体积雾与物理天空。

调用位置：`python omni-gfx/build.py lighting` 或直接运行本文件。
调用示例：
    python omni-gfx/examples/lighting/render.py --frames 120 --screenshot .dev/omni-gfx/world-lighting.png
    python omni-gfx/examples/lighting/render.py --window
设计原因与取舍：
    这一版不追求模型照片级：地形、球与方块都保持低模，材质只有线性反照率与粗糙度。
    真实感由光照承担：太阳色温来自大气透过率，天空是单次散射，云是三维噪声体积步进，
    阴影是三级级联 PCSS 加屏幕空间接触阴影，暗部有天光与草地颜色反弹，
    水面有菲涅尔、粗糙平面反射、折射、吸收与泡沫，最后用 AgX 压缩高光。
    只要其中一项退化成常亮或常暗，并排图就会直接暴露，不靠贴图细节遮掩。
"""
from __future__ import annotations

import argparse  # 截图、计时与交互共用一套入口。
import ctypes  # 顶点属性偏移包装。
import json  # 性能记录。
import math  # 视场角与矩阵。
import struct  # 读预计算大气表的浮点数。
import sys  # 搜索路径。
import time  # 帧时测量。
from array import array  # 读回曝光统计。
from pathlib import Path  # 输出路径。

import glfw  # 窗口与输入。
from OpenGL import GL  # 绘制调用。

HERE = Path(__file__).resolve().parent  # 本示例目录。
LIB = HERE.parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用上下文与着色器工具。
sys.path.insert(0, str(HERE))  # 同目录几何与噪声模块。
sys.path.insert(0, str(HERE.parent / "world"))  # 复用已验证的相机矩阵。

import camera  # 相机与矩阵。
import cloudnoise  # 三维噪声生成与缓存。
import geometry  # 地形、球、方块、立石与水面。
import gl  # OpenGL 小工具。
import png  # 无依赖图片写入。

WIDTH = 1280  # 截图宽度。
HEIGHT = 720  # 截图高度。
NEAR = 0.2  # 近平面。
FAR = 12000.0  # 远平面，覆盖到真实地平线；水面在十二公里处与天空接上。
FOV = 44.0  # 竖直视场角，略宽于五十毫米镜头，让整排球与湖面同时入镜。
EYE_HEIGHT = 1.72  # 站立视高，米。
SUN_DIRECTION = (-0.85, 0.50, 0.15)  # 太阳方向：正左方，仰角三十度；树影横向落在草地与湖面上，能看清软硬。
SUN_COLOR = (1.0, 1.0, 1.0)  # 太阳色温倾向；一表示完全使用大气透过率算出的颜色。
SUN_IRRADIANCE = 1.0  # 太阳辐照度倍率；一表示直接使用 iterationT 的太阳光谱。
SKY_INTENSITY = 1.0  # 天空整体倍率；一表示直接使用 precomputed atmosphere。
CASCADE_SIZE = 1024  # 每级阴影贴图边长。
CASCADE_COUNT = 3  # 三级级联。
CASCADE_EXTENTS = (26.0, 90.0, 300.0)  # 每级正交视锥半边长，米。
CASCADE_SPLITS = (32.0, 115.0, 380.0)  # 按视深度选级的分界。
CASCADE_BLEND = 10.0  # 级联交界过渡宽度。
SKY_MAP_SIZE = (512, 256)  # 环境光与反射用的等距柱状天空贴图尺寸。
CLOUD_STEPS = 20  # iterationT 的晴天云最多二十步，视线越竖直越少。
CLOUD_SHADOW_SIZE = 256  # 云影贴图边长，与 CLOUD_SHADOWTEX_SIZE 相同。
CLOUD_SHADOW_RANGE = 4096.0  # 云影覆盖范围，米；与 iterationT 的 CLOUD_SHADOW_RANGE 相同。
REFLECTION_SCALE = 2  # 平面反射每边缩小的倍数。
RENDER_SCALE = 1.0  # 内部渲染比例；输出与内部分辨率一致。
GI_BLEND = 0.16  # 全局光时间累积里本帧权重。
CLOUD_BLEND = 0.14  # 云时间累积里本帧权重。
TAA_BLEND = 0.03  # TAA 本帧权重；iterationT 的历史权重是 0.97。
BLOOM_SIZE = (320, 180)  # 泛光最细一级。
BLOOM_COARSE_SIZE = (160, 90)  # 泛光最粗一级。
LUMINANCE_SIZE = (64, 36)  # 曝光统计第一级。
EXPOSURE_KEY = 0.18  # 自动曝光参考亮度；AgX 中间灰是 0.18，配合 AE_CURVE 0.7。
BLOOM_STRENGTH = 0.13  # 泛光强度，与 iterationT 的 BLOOM_AMOUNT 相同。
FOG_DENSITY = 0.01  # 对应 iterationT 的 VFOG_DENSITY。
FOG_HEIGHT = 2.0  # 雾层上限相对水面高度，米；兼容旧参数。
FOG_SCATTER = 1.0  # 阳光散射倍率；一对应 VFOG_SUNLIGHT_DENSITY。
FOG_AMBIENT = 1.0  # 天光雾倍率；一对应 VFOG_FOG_DENSITY。
AO_STRENGTH = 0.95  # 环境光遮蔽强度，与 GTAO_STRENGTH 相同。
CONTACT_STRENGTH = 0.7  # 接触阴影强度。
BOUNCE_STRENGTH = 0.6  # 颜色反弹强度。
ATMO_LUT_PATH = ROOT / "references/iterationT/shaders/texture/AtmoData_620_540_440_n4.bin"  # iterationT 的预计算大气表。
ATMO_LUT_SIZE = 512 * 128 * 33 * 16  # 512×128×33 的 RGBA32F；文件末尾多出的 163840 字节不参与纹理。
CLOUD_NOISE_PATH = ROOT / "references/iterationT/shaders/texture/CloudNoise_128_128_128.bin"  # 128 立方基础云噪声。
CLOUD_DETAIL_PATH = ROOT / "references/iterationT/shaders/texture/CloudNoise2_32_32_32.bin"  # 32 立方细节云噪声。
JITTER_SEQUENCE = ((0.5, 0.5), (0.25, 0.75), (0.75, 0.25), (0.125, 0.375), (0.625, 0.875),
                   (0.375, 0.125), (0.875, 0.625), (0.0625, 0.5625))  # 八相位次像素抖动。


def make_program(name: str, vertex: str, fragment: str) -> int:
    """编译一个场景程序；`name` 只用于错误信息。"""
    return gl.build_program(HERE / "shaders" / vertex, HERE / "shaders" / fragment)


def upload_mesh(vertices, attributes: list[tuple[int, int, int]]) -> tuple[int, int]:
    """把交错顶点数组上传到显卡，返回顶点数组与缓冲编号。"""
    vao = GL.glGenVertexArrays(1)  # 顶点数组对象。
    vbo = GL.glGenBuffers(1)  # 顶点缓冲。
    GL.glBindVertexArray(vao)  # 绑定。
    GL.glBindBuffer(GL.GL_ARRAY_BUFFER, vbo)  # 绑定缓冲。
    GL.glBufferData(GL.GL_ARRAY_BUFFER, vertices.tobytes(), GL.GL_STATIC_DRAW)  # 一次性上传。
    stride = sum(count for _, count, _ in attributes) * 4  # 每个顶点的字节数。
    for location_index, count, offset in attributes:  # 按偏移打开属性。
        GL.glEnableVertexAttribArray(location_index)  # 打开这个属性。
        GL.glVertexAttribPointer(location_index, count, GL.GL_FLOAT, GL.GL_FALSE, stride, ctypes.c_void_p(offset))  # 交错指针。
    return vao, vbo  # 调用方负责释放。


def make_depth_target(size: int) -> tuple[int, int]:
    """创建只有深度附件的帧缓冲，返回帧缓冲与深度纹理。"""
    texture = GL.glGenTextures(1)  # 深度纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_DEPTH_COMPONENT24, size, size, 0,
                    GL.GL_DEPTH_COMPONENT, GL.GL_FLOAT, None)  # 二十四位深度。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 深度不插值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 深度不插值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    fbo = GL.glGenFramebuffers(1)  # 帧缓冲。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 绑定。
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_ATTACHMENT, GL.GL_TEXTURE_2D, texture, 0)  # 挂深度。
    GL.glDrawBuffer(GL.GL_NONE)  # 没有颜色附件。
    GL.glReadBuffer(GL.GL_NONE)  # 不读颜色。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 驱动不支持时尽早报错。
        raise RuntimeError("阴影帧缓冲不完整")  # 中文错误。
    return fbo, texture  # 返回编号。


def make_color_target(width: int, height: int, channels: int = 4) -> tuple[int, int]:
    """创建十六位浮点颜色目标，返回帧缓冲与纹理；默认四通道线性过滤。"""
    texture = GL.glGenTextures(1)  # 颜色纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
    internal = GL.GL_RGBA16F if channels == 4 else GL.GL_R16F  # 单通道用于曝光统计。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, internal, width, height, 0, GL.GL_RGBA if channels == 4 else GL.GL_RED,
                    GL.GL_FLOAT, None)  # 浮点存储。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 线性缩小。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 线性放大。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    fbo = GL.glGenFramebuffers(1)  # 帧缓冲。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 绑定。
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0, GL.GL_TEXTURE_2D, texture, 0)  # 挂颜色。
    GL.glDrawBuffer(GL.GL_COLOR_ATTACHMENT0)  # 只写颜色附件零。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 检查完整性。
        raise RuntimeError("浮点颜色帧缓冲不完整")  # 中文错误。
    return fbo, texture  # 返回编号。


def make_sky_map(width: int, height: int) -> tuple[int, int]:
    """创建等距柱状天空贴图与只用于渲染它的帧缓冲；采样端用二维纹理。"""
    fbo, texture = make_color_target(width, height)  # 复用浮点颜色目标。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)  # 环境光需要多级。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)  # 水平方向接缝平铺。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 垂直方向不到头顶以下。
    GL.glGenerateMipmap(GL.GL_TEXTURE_2D)  # 先建立完整的层级，避免采样未定义。
    return fbo, texture  # 返回。


def make_texture_3d(size: int, data: bytes) -> int:
    """把原始 RGBA 字节上传成平铺的三维纹理。"""
    texture = GL.glGenTextures(1)  # 三维纹理。
    GL.glBindTexture(GL.GL_TEXTURE_3D, texture)  # 绑定。
    GL.glTexImage3D(GL.GL_TEXTURE_3D, 0, GL.GL_RGBA8, size, size, size, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, data)  # 上传体素。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 体积云需要平滑插值。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也平滑。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)  # 平铺。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)  # 平铺。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_R, GL.GL_REPEAT)  # 平铺。
    return texture  # 返回编号。


def make_texture_2d(size: int, data: bytes) -> int:
    """把原始 RGBA 字节上传成平铺的二维纹理。"""
    texture = GL.glGenTextures(1)  # 二维纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA8, size, size, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, data)  # 上传。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 线性缩小。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 线性放大。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)  # 平铺。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)  # 平铺。
    return texture  # 返回编号。


def make_blue_noise() -> int:
    """生成与库约定一致的六十四像素蓝噪声纹理。"""
    import bluenoise  # 世界示例里的蓝噪声生成器，纯标准库。

    data = bluenoise.texture_data()  # 原始八位数据。
    texture = GL.glGenTextures(1)  # 纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_R8, 64, 64, 0, GL.GL_RED, GL.GL_UNSIGNED_BYTE, data)  # 单通道。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 蓝噪声不能插值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 最近值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)  # 平铺。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)  # 平铺。
    return texture  # 返回编号。


def make_atmosphere_lut(raw: bytes) -> int:
    """把 iterationT 的预计算大气表上传成 512×128×33 的 RGBA32F 三维纹理。"""
    expected = 512 * 128 * 33 * 4 * 4  # 每像素四个 float。
    if len(raw) != expected:  # 文件不完整时直接报错，不用一张错位的表算天空。
        raise RuntimeError(f"大气表长度不符：{len(raw)}，应为 {expected}")
    texture = GL.glGenTextures(1)  # 纹理。
    GL.glBindTexture(GL.GL_TEXTURE_3D, texture)  # 绑定三维纹理。
    GL.glTexImage3D(GL.GL_TEXTURE_3D, 0, GL.GL_RGBA32F, 512, 128, 33, 0, GL.GL_RGBA, GL.GL_FLOAT, raw)  # 原始浮点数据。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 查表需要三线性插值。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也插值。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 不越界。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 不越界。
    GL.glTexParameteri(GL.GL_TEXTURE_3D, GL.GL_TEXTURE_WRAP_R, GL.GL_CLAMP_TO_EDGE)  # 不越界。
    return texture  # 返回编号。


def smootherstep01(x: float) -> float:
    """零到一的平滑曲线，和 iterationT 的 `curve` 相同。"""
    x = min(max(x, 0.0), 1.0)  # 输入夹到零到一。
    return x * x * (3.0 - 2.0 * x)  # 三次平滑。


def smoothstep_range(edge0: float, edge1: float, x: float) -> float:
    """GLSL 的 smoothstep，两端导数为零。"""
    if edge0 == edge1:  # 退化区间没有过渡。
        return 1.0 if x >= edge1 else 0.0
    t = (x - edge0) / (edge1 - edge0)  # 归一化。
    t = min(max(t, 0.0), 1.0)  # 夹到零到一。
    return t * t * (3.0 - 2.0 * t)  # 三次平滑。


class AtmosphereTable:
    """在 CPU 上复算 iterationT 的太阳与天空辐照度，避免每个像素采样三维表。"""

    def __init__(self, raw: bytes) -> None:
        """保存原始浮点表与常数，采样时直接读字节。"""
        self.raw = raw  # 512×128×33 的 RGBA32F。
        self.bottom_radius = 6360.0  # 行星底半径，公里。
        self.top_radius = 6420.0  # 大气层顶，公里。
        self.sun_angular_radius = 0.005  # 太阳视半径。
        self.solar = (1.68194, 1.85149, 1.91198)  # 太阳光谱。
        self.transmittance_width = 256.0  # 透过率子图宽度。
        self.transmittance_height = 64.0  # 透过率子图高度。
        self.combined_width = 512.0  # 拼合大图宽度。
        self.combined_height = 128.0  # 拼合大图高度。
        self.irradiance_width = 64.0  # 辐照度子图宽度。
        self.irradiance_height = 16.0  # 辐照度子图高度。
        self.lms_rows = ((1.6858, -0.4624, -0.0069), (-0.0374, 1.0598, -0.0742), (-0.0283, -0.1119, 1.0491))  # 色适应矩阵的三行。

    def sample(self, u: float, v: float, z: int) -> tuple[float, float, float]:
        """在指定的深度层上做双线性采样，深度方向不插值。"""
        x = u * 512.0 - 0.5  # 纹理坐标换成像素坐标。
        y = v * 128.0 - 0.5
        x0 = int(x // 1)  # 左列。
        y0 = int(y // 1)  # 下行。
        fx = x - x0  # 横向小数。
        fy = y - y0  # 纵向小数。
        x0 = min(max(x0, 0), 511)  # 夹进纹理。
        y0 = min(max(y0, 0), 127)
        x1 = min(x0 + 1, 511)  # 右列。
        y1 = min(y0 + 1, 127)  # 上行。
        base = (z * 128 + y0) * 512  # 下行的起始像素。
        i00 = (base + x0) * 16  # 每个像素十六字节。
        i10 = (base + x1) * 16
        topBase = (z * 128 + y1) * 512  # 上一行的起始像素；y1 已经夹在纹理内。
        i01 = (topBase + x0) * 16
        i11 = (topBase + x1) * 16
        values = []  # 三个通道。
        for channel in range(3):
            offset = channel * 4  # 每个通道一个 float。
            v00 = struct.unpack_from("<f", self.raw, i00 + offset)[0]  # 左下。
            v10 = struct.unpack_from("<f", self.raw, i10 + offset)[0]  # 右下。
            v01 = struct.unpack_from("<f", self.raw, i01 + offset)[0]  # 左上。
            v11 = struct.unpack_from("<f", self.raw, i11 + offset)[0]  # 右上。
            low = v00 + (v10 - v00) * fx  # 横向插值。
            high = v01 + (v11 - v01) * fx
            values.append(low + (high - low) * fy)  # 纵向插值。
        return values[0], values[1], values[2]

    def texel_center(self, x: float, size: float) -> float:
        """把零到一映射到贴图像素中心，避免采到子图边界。"""
        return 0.5 / size + x * (1.0 - 1.0 / size)

    def combined_coord(self, x: float, original: float, combined: float) -> float:
        """把子图内部比例映射到拼合大图坐标。"""
        return 0.5 / combined + x * (original / combined - 1.0 / combined)

    def distance_to_top(self, r: float, mu: float) -> float:
        """视线到大气层顶的远交点距离。"""
        discriminant = r * r * (mu * mu - 1.0) + self.top_radius * self.top_radius  # 球面判别式。
        return max(-r * mu + math.sqrt(max(discriminant, 0.0)), 0.0)

    def transmittance_to_top(self, r: float, mu: float) -> tuple[float, float, float]:
        """查某点朝某个方向到层顶的透过率。"""
        h = math.sqrt(self.top_radius * self.top_radius - self.bottom_radius * self.bottom_radius)  # 层顶水平距离。
        rho = math.sqrt(max(r * r - self.bottom_radius * self.bottom_radius, 0.0))  # 水平投影。
        d = self.distance_to_top(r, mu)  # 到层顶的距离。
        d_min = self.top_radius - r  # 距离下限。
        d_max = rho + h  # 距离上限。
        x_mu = (d - d_min) / (d_max - d_min)  # 高度角方向比例。
        x_r = rho / h  # 半径方向比例。
        u = self.combined_coord(x_mu, self.transmittance_width, self.combined_width)  # 横坐标。
        v = self.combined_coord(x_r, self.transmittance_height, self.combined_height)  # 纵坐标。
        return self.sample(u, v, 32)  # 透过率在第三十二层。

    def transmittance_to_sun(self, r: float, mu_s: float) -> tuple[float, float, float]:
        """某点朝太阳方向的透过率，贴地时按太阳视半径渐隐。"""
        sin_theta_h = self.bottom_radius / r  # 地平线俯角正弦。
        cos_theta_h = -math.sqrt(max(1.0 - sin_theta_h * sin_theta_h, 0.0))  # 地平线余弦。
        base = self.transmittance_to_top(r, mu_s)  # 基础透过率。
        edge = smoothstep_range(-sin_theta_h * self.sun_angular_radius,
                                sin_theta_h * self.sun_angular_radius,
                                mu_s - cos_theta_h)  # 太阳圆面过渡。
        return base[0] * edge, base[1] * edge, base[2] * edge

    def irradiance(self, r: float, mu_s: float) -> tuple[float, float, float]:
        """查某高度朝上接到的太阳与环境辐照度。"""
        x_r = (r - self.bottom_radius) / (self.top_radius - self.bottom_radius)  # 半径比例。
        x_mu_s = mu_s * 0.5 + 0.5  # 太阳高度角比例。
        u = self.combined_coord(x_mu_s, self.irradiance_width, self.combined_width)  # 横坐标。
        v = self.combined_coord(x_r, self.irradiance_height, self.combined_height) + self.transmittance_height / self.combined_height  # 跳过透过率子图。
        return self.sample(u, v, 32)  # 辐照度也在第三十二层。

    def lms(self, color: tuple[float, float, float]) -> tuple[float, float, float]:
        """乘色适应矩阵；行序与着色器的 `ogxApplyRows` 相同。"""
        return tuple(sum(color[i] * row[i] for i in range(3)) for row in self.lms_rows)  # 三个点积。

    def sun_and_sky(self, sun_direction: tuple[float, float, float]) -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]:
        """返回太阳直射辐照度、天空辐照度与太阳透过率。"""
        r = self.bottom_radius + 0.063  # 相机高度六十三米，单位公里。
        mu_s = sun_direction[1]  # 相机在行星正上方，太阳高度角余弦就是 y 分量。
        transmittance = self.transmittance_to_sun(r, mu_s)  # 太阳透过率。
        sun = self.lms(tuple(self.solar[i] * transmittance[i] for i in range(3)))  # 太阳光谱乘透过率再转色适应空间。
        sky = self.lms(self.irradiance(r, mu_s))  # 天空辐照度。
        return sun, sky, transmittance


def make_iterationt_cloud_noise() -> tuple[int, int]:
    """加载 iterationT 的 128 立方基础云噪声与 32 立方细节噪声。"""
    base = CLOUD_NOISE_PATH.read_bytes()  # RGBA8，128 立方。
    if len(base) != 128 * 128 * 128 * 4:  # 长度不对说明不是这张纹理。
        raise RuntimeError(f"基础云噪声长度不符：{len(base)}")
    detail_raw = CLOUD_DETAIL_PATH.read_bytes()  # RGB8，32 立方。
    if len(detail_raw) != 32 * 32 * 32 * 3:  # 长度不对说明不是这张纹理。
        raise RuntimeError(f"细节云噪声长度不符：{len(detail_raw)}")
    detail = bytearray(32 * 32 * 32 * 4)  # 补成 RGBA8，纹理格式统一。
    detail[0::4] = detail_raw[0::3]  # 红通道。
    detail[1::4] = detail_raw[1::3]  # 绿通道。
    detail[2::4] = detail_raw[2::3]  # 蓝通道。
    detail[3::4] = b"\xff" * (32 * 32 * 32)  # 透明通道填满，采样端不会读它。
    return make_texture_3d(128, base), make_texture_3d(32, bytes(detail))  # 两张纹理。


def location(program: int, name: str) -> int:
    """取 uniform 位置；不存在时返回负一，OpenGL 会忽略对应写入。"""
    return GL.glGetUniformLocation(program, name)


def set_uniform(program: int, name: str, value) -> None:
    """按 Python 类型选择写入函数，缺少的 uniform 直接跳过。"""
    where = location(program, name)  # uniform 位置。
    if where < 0:  # 编译器优化掉了。
        return  # 直接返回。
    if isinstance(value, bool):  # 布尔。
        GL.glUniform1i(where, 1 if value else 0)  # 用整数写。
    elif isinstance(value, int):  # 整数。
        GL.glUniform1i(where, value)  # 写整数。
    elif isinstance(value, float):  # 浮点。
        GL.glUniform1f(where, value)  # 写浮点。
    elif isinstance(value, (list, tuple)):  # 向量或矩阵。
        if len(value) == 2:  # 二维。
            GL.glUniform2f(where, *value)  # 写二维。
        elif len(value) == 3:  # 三维。
            GL.glUniform3f(where, *value)  # 写三维。
        elif len(value) == 4:  # 四维。
            GL.glUniform4f(where, *value)  # 写四维。
        elif len(value) == 16:  # 四乘四矩阵。
            GL.glUniformMatrix4fv(where, 1, GL.GL_FALSE, value)  # 列主序。
        else:  # 未知长度。
            raise ValueError(f"不支持的 uniform 长度：{name} {len(value)}")  # 明确报错。
    else:  # 未知类型。
        raise TypeError(f"不支持的 uniform 类型：{name} {type(value)}")  # 明确报错。


def set_uniforms(program: int, values: dict) -> None:
    """一次写入一组 uniform。"""
    for name, value in values.items():  # 逐项。
        set_uniform(program, name, value)  # 写入。


def multiply(a: list[float], b: list[float]) -> list[float]:
    """列主序四乘四矩阵相乘，返回 a 乘 b。"""
    result = [0.0] * 16  # 输出。
    for column in range(4):  # 逐列。
        for row in range(4):  # 逐行。
            result[column * 4 + row] = sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))  # 点积。
    return result  # 返回矩阵。


def orthographic(left: float, right: float, bottom: float, top: float, near: float, far: float) -> list[float]:
    """列主序正交投影矩阵，方向光没有透视。"""
    return [
        2.0 / (right - left), 0.0, 0.0, 0.0,  # 横向缩放。
        0.0, 2.0 / (top - bottom), 0.0, 0.0,  # 纵向缩放。
        0.0, 0.0, -2.0 / (far - near), 0.0,  # 深度缩放。
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,  # 平移。
    ]  # 返回列主序矩阵。


def perspective_inverse(fov: float, aspect: float, near: float, far: float) -> list[float]:
    """列主序透视逆投影矩阵，把屏幕深度还原成视空间位置。"""
    f = 1.0 / math.tan(math.radians(fov) * 0.5)  # 视场角一半的余切。
    depth_scale = (near - far) / (2.0 * far * near)  # 深度缩放。
    depth_bias = (far + near) / (2.0 * far * near)  # 深度平移。
    return [
        aspect / f, 0.0, 0.0, 0.0,  # 横向。
        0.0, 1.0 / f, 0.0, 0.0,  # 纵向。
        0.0, 0.0, 0.0, depth_scale,  # 深度。
        0.0, 0.0, -1.0, depth_bias,  # 平移。
    ]  # 返回矩阵。


def percentile(values: list[float], fraction: float) -> float:
    """返回排序后指定分位的值。"""
    ordered = sorted(values)  # 排序。
    index = min(len(ordered) - 1, max(0, int(len(ordered) * fraction)))  # 分位下标。
    return ordered[index]  # 返回。


def make_multi_color_target(width: int, height: int, count: int) -> tuple[int, list[int]]:
    """创建多张线性过滤的颜色附件，供全局光与反弹双目标使用。"""
    fbo = GL.glGenFramebuffers(1)  # 帧缓冲。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 绑定。
    textures = []  # 颜色纹理。
    attachments = []  # 绘制缓冲列表。
    for index in range(count):  # 每个附件。
        texture = GL.glGenTextures(1)  # 颜色纹理。
        GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
        GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA16F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)  # 浮点。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 历史需要线性取样。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 线性。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 不重复。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 不重复。
        attachment = GL.GL_COLOR_ATTACHMENT0 + index  # 附件编号。
        GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, attachment, GL.GL_TEXTURE_2D, texture, 0)  # 挂载。
        textures.append(texture)  # 保存。
        attachments.append(attachment)  # 保存。
    GL.glDrawBuffers(len(attachments), attachments)  # 一次写全部附件。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 完整性。
        raise RuntimeError("多颜色帧缓冲不完整")  # 中文错误。
    return fbo, textures  # 返回。


class World:
    """验证场景的显卡资源与每帧绘制顺序。"""

    def __init__(self, width: int, height: int, tonemap: int, exposure_key: float) -> None:
        """创建窗口、程序、几何、纹理与离屏目标。"""
        self.output_width = width  # 最终输出宽度。
        self.output_height = height  # 最终输出高度。
        self.width = max(1, int(round(width * RENDER_SCALE)))  # 内部渲染宽度；后期放大到输出尺寸。
        self.height = max(1, int(round(height * RENDER_SCALE)))  # 内部渲染高度。
        self.half_width = max(1, self.width // 2)  # 半分辨率宽度，用于全局光。
        self.half_height = max(1, self.height // 2)  # 半分辨率高度。
        self.cloud_width = max(1, int(round(self.width * 0.75)))  # 体积云用四分之三分辨率，云边比半分辨率清楚，成本仍低于全分辨率。
        self.cloud_height = max(1, int(round(self.height * 0.75)))  # 四分之三分辨率高度。
        self.reflection_width = max(1, width // REFLECTION_SCALE)  # 反射宽度。
        self.reflection_height = max(1, height // REFLECTION_SCALE)  # 反射高度。
        self.tonemap = tonemap  # 色调映射。
        self.exposure_key = exposure_key  # 曝光目标。
        self.window = gl.init_window(self.output_width, self.output_height, "omni-gfx 光影验证场景", visible=False)  # 隐藏窗口截图。
        self.sun = camera.normalize(list(SUN_DIRECTION))  # 太阳方向。
        self.device = gl.device_info()  # 显卡信息。
        self.fullscreen = gl.fullscreen_vao()  # 全屏三角形。
        # 每个阶段一个程序，避免共享 uniform 状态。
        self.sky_program = make_program("天空", "fullscreen.vert", "sky.frag")  # 天空与立方体。
        self.cloud_program = make_program("体积云", "fullscreen.vert", "cloud.frag")  # 云步进。
        self.cloud_blur_program = make_program("云模糊", "fullscreen.vert", "cloud_blur.frag")  # 云纹理高斯模糊。
        self.cloud_shadow_program = make_program("云影", "fullscreen.vert", "cloud_shadow.frag")  # 云影贴图。
        self.surface_program = make_program("地表", "surface.vert", "surface.frag")  # 地形与物体。
        self.shadow_program = make_program("阴影", "shadow.vert", "shadow.frag")  # 深度。
        self.water_program = make_program("水面", "water.vert", "water.frag")  # 湖面。
        self.gi_program = make_program("全局光", "fullscreen.vert", "gi_lighting.frag")  # 遮蔽与反弹。
        self.composite_program = make_program("合成", "fullscreen.vert", "composite.frag")  # 直射与间接。
        self.fog_program = make_program("体积雾", "fullscreen.vert", "fog.frag")  # 雾与光柱。
        self.taa_program = make_program("时间抗锯齿", "fullscreen.vert", "taa.frag")  # 抗锯齿。
        self.bloom_program = make_program("泛光", "fullscreen.vert", "bloom.frag")  # 泛光。
        self.exposure_program = make_program("曝光", "fullscreen.vert", "exposure.frag")  # 曝光统计。
        self.post_program = make_program("后期", "fullscreen.vert", "post.frag")  # 最终显示。
        self.copy_program = make_program("场景拷贝", "fullscreen.vert", "copy.frag")  # 水面拷贝。

        scene = geometry.build()  # 构建地形、物体与水面。
        self.field = scene["field"]  # 高度场。
        self.camera_ground = scene["cameraGround"]  # 相机脚下高度。
        self.terrain_triangles = scene["terrainTriangles"]  # 地形三角形数。
        self.object_triangles = scene["objectTriangles"]  # 物体三角形数。
        self.water_triangles = scene["waterTriangles"]  # 水面三角形数。
        self.terrain_vao, self.terrain_vbo = upload_mesh(scene["terrain"], [(0, 3, 0), (1, 3, 12), (2, 3, 24), (3, 1, 36), (4, 1, 40)])  # 地形顶点。
        self.object_vao, self.object_vbo = upload_mesh(scene["objects"], [(0, 3, 0), (1, 3, 12), (2, 3, 24), (3, 1, 36), (4, 1, 40)])  # 物体顶点。
        self.water_vao, self.water_vbo = upload_mesh(scene["water"], [(0, 2, 0)])  # 水面顶点。
        self.textures = {}  # 场景纹理集合。
        noise = cloudnoise.ensure()  # 二维扰动纹理仍用本地生成器。
        self.noise_base, self.noise_detail = make_iterationt_cloud_noise()  # 云噪声直接用 iterationT 的同一份数据。
        self.noise_curl = make_texture_2d(cloudnoise.CURL_SIZE, noise["curl"])  # 二维扰动。
        self.blue_noise = make_blue_noise()  # 蓝噪声。
        self.atmo_bytes = ATMO_LUT_PATH.read_bytes()[:ATMO_LUT_SIZE]  # 只取纹理部分，末尾多出的字节丢弃。
        self.atmo_table = AtmosphereTable(self.atmo_bytes)  # CPU 侧的太阳与天空辐照度。
        self.atmo_lut = make_atmosphere_lut(self.atmo_bytes)  # iterationT 的预计算大气表。
        self.sky_fbo, self.sky_map = make_sky_map(*SKY_MAP_SIZE)  # 等距柱状天空贴图。
        GL.glEnable(GL.GL_TEXTURE_CUBE_MAP_SEAMLESS)  # 立方体边缘不出现接缝；本场景不采样立方体，保留不影响结果。
        self.shadow_fbos = []  # 级联帧缓冲。
        self.shadow_depths = []  # 级联深度纹理。
        for _ in range(CASCADE_COUNT):  # 每级一张。
            fbo, depth = make_depth_target(CASCADE_SIZE)  # 创建深度目标。
            self.shadow_fbos.append(fbo)  # 保存。
            self.shadow_depths.append(depth)  # 保存。
        self.scene_fbo, scene_colors, self.scene_depth = gl.multi_color_depth_target(width, height, 4)  # 四张场景附件。
        self.scene_direct, self.scene_indirect = scene_colors[0], scene_colors[1]  # 直射与间接。
        self.scene_normal, self.scene_albedo = scene_colors[2], scene_colors[3]  # 法线与反照率。
        self.reflection_fbo, self.reflection_color, self.reflection_depth = gl.color_depth_target(
            self.reflection_width, self.reflection_height)  # 反射目标。
        # 反射纹理要带 mipmap：水面在掠射角会把地平线附近的高频明暗直接放大成白黑相间的碎条，
        # 预过滤后的低层级只保留山体与天空的大块颜色，粗糙水面才不会像一张揉皱的锡纸。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_color)  # 绑定反射颜色。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)  # 缩小取 mip。
        GL.glGenerateMipmap(GL.GL_TEXTURE_2D)  # 先建立层级，避免采样到未定义的内存。
        self.lit_fbo, self.lit_color = make_color_target(width, height)  # 合成后的不透明颜色。
        self.water_fbo, self.water_color, self.water_depth = gl.color_depth_target(width, height)  # 水面目标。
        self.fog_fbo, self.fog_color = make_color_target(width, height)  # 雾合成目标。
        self.cloud_raw_fbo, self.cloud_raw = make_color_target(self.cloud_width, self.cloud_height)  # 本帧云与时间累积目标零。
        self.cloud_accum_fbo, self.cloud_accum = make_color_target(self.cloud_width, self.cloud_height)  # 时间累积目标一，与目标零双缓冲。
        self.cloud_temp_fbo, self.cloud_temp = make_color_target(self.cloud_width, self.cloud_height)  # 横向模糊中间结果。
        self.cloud_blur_fbo, self.cloud_blur = make_color_target(self.cloud_width, self.cloud_height)  # 最终云纹理。
        self.cloud_shadow_size = CLOUD_SHADOW_SIZE  # 云影尺寸。
        self.cloud_shadow_fbo, self.cloud_shadow = make_color_target(CLOUD_SHADOW_SIZE, CLOUD_SHADOW_SIZE)  # 云影贴图。
        self.gi_fbo = []  # 全局光目标。
        self.gi_targets = []  # 两张附件纹理。
        for _ in range(2):  # 双缓冲。
            fbo, textures = make_multi_color_target(self.half_width, self.half_height, 2)  # 遮蔽与反弹。
            self.gi_fbo.append(fbo)  # 保存。
            self.gi_targets.append(textures)  # 保存。
        self.taa_fbo = []  # 抗锯齿历史。
        self.taa_color = []  # 抗锯齿纹理。
        for _ in range(2):  # 双缓冲。
            fbo, texture = make_color_target(width, height)  # 创建。
            self.taa_fbo.append(fbo)  # 保存。
            self.taa_color.append(texture)  # 保存。
        self.bloom_fbo, self.bloom_color = make_color_target(*BLOOM_SIZE)  # 细泛光。
        self.bloom_coarse_fbo, self.bloom_coarse_color = make_color_target(*BLOOM_COARSE_SIZE)  # 粗泛光。
        self.bloom_combine_fbo, self.bloom_combine_color = make_color_target(*BLOOM_SIZE)  # 合并泛光。
        self.lum_tile_fbo, self.lum_tile = make_color_target(*LUMINANCE_SIZE)  # 曝光第一级。
        self.lum_final_fbo, self.lum_final = make_color_target(1, 1)  # 曝光最终。
        self.gi_index = 0  # 全局光历史下标。
        self.taa_index = 0  # 抗锯齿历史下标。
        self.cloud_index = 0  # 云时间累积的双缓冲下标。
        self.jitter = (0.0, 0.0)  # 本帧抖动。
        self.tonemap = tonemap  # 色调映射。
        self.bloom_strength = BLOOM_STRENGTH  # 泛光强度。
        self.profile = False  # 是否输出每阶段耗时。
        self.water_debug = 0  # 水面调试模式，零正常，一法线，二反射，三折射，四高光。
        self.surface_debug = 0  # 地表调试模式，零正常，一反照率。
        self.fog_debug = 0  # 雾调试模式，零正常，一太阳可见度，二只输出雾散射。
        self.scene_time = 0.0  # 场景时间。
        self.static_signature = None  # 相机、太阳与时间的签名；不变时阴影、云影和倒影都不用重画。
        self.camera = camera.Camera([geometry.CAMERA_START[0], self.camera_ground + EYE_HEIGHT, geometry.CAMERA_START[1]], fov=FOV)  # 站立相机。
        self.camera.look_at(list(geometry.LOOK_TARGET))  # 看向湖对岸。
        self.light_matrices = self.build_light_matrices()  # 三级阴影矩阵。
        self.previous_view_projection = self.view_projection()  # 首帧没有历史。
        self.display_color = self.taa_color[0]  # 当前显示纹理。
        self.keys: set[int] = set()  # 按键状态。
        self.first_mouse = True  # 首帧鼠标。
        self.last_mouse = (0.0, 0.0)  # 上次鼠标位置。
        self.screenshot_request = False  # F12 截图请求。
        self.render_cloud_shadow_program = self.cloud_shadow_program  # 方便调试时引用。
        self.render_sky_map(0, 0.0)  # 预生成一次天空立方体。

    def build_light_matrices(self) -> list[list[float]]:
        """构造三级方向光的视图投影矩阵；每级覆盖不同大小的区域。"""
        forward = self.camera.forward()  # 相机前方向。
        matrices = []  # 输出矩阵。
        for index, extent in enumerate(CASCADE_EXTENTS):  # 每级。
            center = [self.camera.position[i] + forward[i] * (extent * 0.45) for i in range(3)]  # 中心随范围前移。
            eye = [center[i] + self.sun[i] * 500.0 for i in range(3)]  # 光源相机放在太阳方向，距离够近以保住深度精度。
            light_camera = camera.Camera(eye)  # 临时相机。
            light_camera.look_at(center)  # 看向中心。
            view = light_camera.view_matrix()  # 光源视图。
            projection = orthographic(-extent, extent, -extent, extent, 1.0, 1000.0)  # 正交投影；深度范围一千米，一米差约千分之一。
            matrices.append(multiply(projection, view))  # 光源视图投影。
        return matrices  # 返回三级矩阵。

    def basis(self) -> tuple[list[float], list[float], list[float], float, float]:
        """返回主相机的前、右、上与视场参数。"""
        return (self.camera.forward(), self.camera.right(), self.camera.up(),
                math.tan(math.radians(self.camera.fov) * 0.5), self.width / self.height)  # 组合返回。

    def projection(self) -> list[float]:
        """返回带次像素抖动的投影矩阵。"""
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 基础投影。
        projection[8] += self.jitter[0] * 2.0 / self.width  # 横向抖动。
        projection[9] += self.jitter[1] * 2.0 / self.height  # 纵向抖动。
        return projection  # 返回。

    def view_projection(self) -> list[float]:
        """返回带抖动的视图投影矩阵。"""
        return multiply(self.projection(), self.camera.view_matrix())  # 投影乘视图。

    def jitter_uv(self) -> list[float]:
        """返回本帧抖动在纹理坐标上的偏移。"""
        return [self.jitter[0] / self.width, self.jitter[1] / self.height]  # 归一化。

    def install_input(self) -> None:
        """显示窗口并安装键鼠回调。"""
        glfw.show_window(self.window)  # 显示窗口。
        glfw.set_input_mode(self.window, glfw.CURSOR, glfw.CURSOR_DISABLED)  # 锁定鼠标。
        glfw.set_key_callback(self.window, self.on_key)  # 键盘。
        glfw.set_cursor_pos_callback(self.window, self.on_cursor)  # 鼠标。

    def on_key(self, window, key: int, scancode: int, action: int, mods: int) -> None:
        """记录按键；退出键关闭，F12 保存截图。"""
        if action == glfw.PRESS:  # 按下。
            self.keys.add(key)  # 记录。
            if key == glfw.KEY_ESCAPE:  # 退出。
                glfw.set_window_should_close(window, True)  # 关闭。
            if key == glfw.KEY_F12:  # 截图。
                self.screenshot_request = True  # 请求。
        elif action == glfw.RELEASE:  # 松开。
            self.keys.discard(key)  # 移除。

    def on_cursor(self, window, x: float, y: float) -> None:
        """鼠标位移换成相机转向。"""
        if self.first_mouse:  # 首帧只记录位置。
            self.first_mouse = False  # 清除标记。
            self.last_mouse = (x, y)  # 记录。
            return  # 返回。
        delta_x = x - self.last_mouse[0]  # 横向位移。
        delta_y = y - self.last_mouse[1]  # 纵向位移。
        self.last_mouse = (x, y)  # 更新。
        self.camera.turn(delta_x, delta_y)  # 转向。

    def bind_common(self, program: int, frame: int, scene_time: float) -> None:
        """写入所有阶段共用的太阳、相机、时间、云影参数与大气表。"""
        set_uniforms(program, {
            "uSunDirection": self.sun, "uSunColor": list(SUN_COLOR), "uSunIrradiance": SUN_IRRADIANCE,
            "uSkyIntensity": SKY_INTENSITY, "uTime": scene_time, "uFrame": float(frame),
            "uWaterLevel": geometry.WATER_LEVEL, "uCameraPosition": self.camera.position,
            "uCloudShadowRect": [self.camera.position[0], self.camera.position[2], CLOUD_SHADOW_RANGE, 1.0],
        })  # 通用参数。
        sun, sky, transmittance = self.atmo_table.sun_and_sky(self.sun)  # 太阳与天空辐照度每帧算一次。
        fade = 1.0 - smootherstep01(min(max((1.0 - min(max(self.sun[1], 0.0), 1.0)) * 30.0 - 29.0, 0.0), 1.0))  # 太阳贴地时淡出。
        set_uniforms(program, {"uSunLight": [component * fade for component in sun], "uSkyLight": sky,
                               "uSunTransmittance": transmittance})  # 预计算光照，片元阶段不再采大气表。
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 二号单元在所有阶段都不放别的输入。
        GL.glBindTexture(GL.GL_TEXTURE_3D, self.atmo_lut)  # 预计算大气表，只给天空背景与水天线用。
        GL.glUniform1i(location(program, "uAtmoLut"), 2)  # 采样器。

    def bind_shadows(self, program: int) -> None:
        """绑定三级阴影矩阵、分界与深度图。"""
        for index in range(CASCADE_COUNT):  # 每级。
            set_uniform(program, f"uShadowMatrix{index}", self.light_matrices[index])  # 矩阵。
            GL.glActiveTexture(GL.GL_TEXTURE0 + 3 + index)  # 纹理单元三到五，避开场景颜色与噪声。
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.shadow_depths[index])  # 深度图。
            GL.glUniform1i(location(program, f"uShadowMap{index}"), 3 + index)  # 采样器。
        set_uniforms(program, {"uCascadeSplits": list(CASCADE_SPLITS), "uCascadeBlend": CASCADE_BLEND,
                               "uShadowTexel": 1.0 / CASCADE_SIZE})  # 分界与纹素。

    def bind_noise(self, program: int) -> None:
        """绑定三维噪声、二维扰动、云影与蓝噪声。"""
        for unit, texture, target in ((7, self.noise_base, GL.GL_TEXTURE_3D), (8, self.noise_detail, GL.GL_TEXTURE_3D),
                                      (9, self.noise_curl, GL.GL_TEXTURE_2D), (10, self.cloud_shadow, GL.GL_TEXTURE_2D),
                                      (11, self.blue_noise, GL.GL_TEXTURE_2D)):  # 逐个绑定。
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)  # 选单元。
            GL.glBindTexture(target, texture)  # 绑定。
            GL.glUniform1i(location(program, "uCloudBase" if unit == 7 else "uCloudDetail" if unit == 8 else
                                    "uCloudCurl" if unit == 9 else "uCloudShadowMap" if unit == 10 else "uBlueNoise"), unit)  # 采样器。

    def bind_sky_map(self, program: int) -> None:
        """把等距柱状天空贴图绑到单元六。"""
        GL.glActiveTexture(GL.GL_TEXTURE6)  # 单元六。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_map)  # 绑定。
        GL.glUniform1i(location(program, "uSkyMap"), 6)  # 采样器。

    def render_shadow(self, frame: int, scene_time: float) -> None:
        """从太阳方向渲染三级深度；固定机位只烘一次，移动时远景级每两帧更新。"""
        GL.glEnable(GL.GL_DEPTH_TEST)  # 打开深度。
        GL.glDepthMask(GL.GL_TRUE)  # 写深度。
        GL.glDisable(GL.GL_CULL_FACE)  # 地形与盒子都按朝外绕序，关闭剔除更稳。
        GL.glEnable(GL.GL_POLYGON_OFFSET_FILL)  # 减少自阴影条纹。
        GL.glPolygonOffset(0.5, 1.5)  # 低阳时阴影贴图的深度斜率很大，偏移过大会让树影落不到地面；只留很小的偏移。
        for index, matrix in enumerate(self.light_matrices):  # 每级。
            if index == 2 and frame % 2 == 1:  # 最远一级每两帧更新，远景阴影滞后一帧看不出来。
                continue  # 保留上一帧深度。
            GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.shadow_fbos[index])  # 深度目标。
            GL.glViewport(0, 0, CASCADE_SIZE, CASCADE_SIZE)  # 视口。
            GL.glClear(GL.GL_DEPTH_BUFFER_BIT)  # 清深度。
            GL.glUseProgram(self.shadow_program)  # 阴影程序。
            set_uniform(self.shadow_program, "uLightViewProjection", matrix)  # 光源矩阵。
            GL.glBindVertexArray(self.terrain_vao)  # 地形。
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 绘制。
            if index < 2:  # 远景级省掉小物体，它们在第三级只占几像素。
                GL.glBindVertexArray(self.object_vao)  # 物体。
                GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.object_triangles * 3)  # 绘制。
        GL.glDisable(GL.GL_POLYGON_OFFSET_FILL)  # 关闭偏移。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 回到默认。

    def render_cloud_shadow(self, frame: int, scene_time: float) -> None:
        """把云影烘到一张以相机为中心的贴图。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.cloud_shadow_fbo)  # 云影目标。
        GL.glViewport(0, 0, CLOUD_SHADOW_SIZE, CLOUD_SHADOW_SIZE)  # 视口。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.cloud_shadow_program)  # 云影程序。
        self.bind_common(self.cloud_shadow_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.cloud_shadow_program, {"uResolution": [float(CLOUD_SHADOW_SIZE)] * 2, "uRange": CLOUD_SHADOW_RANGE})  # 范围。
        self.bind_noise(self.cloud_shadow_program)  # 噪声。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制。

    def render_sky_map(self, frame: int, scene_time: float) -> None:
        """把天空与体积云渲染到等距柱状贴图，供环境光与反射。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_fbo)  # 天空帧缓冲。
        GL.glViewport(0, 0, SKY_MAP_SIZE[0], SKY_MAP_SIZE[1])  # 视口。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空没有深度。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.sky_program)  # 天空程序。
        self.bind_common(self.sky_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.sky_program, {"uResolution": [float(SKY_MAP_SIZE[0]), float(SKY_MAP_SIZE[1])],
                                        "uSceneTarget": 0, "uSkyMode": 1, "uUseCloudTexture": 0,
                                        "uCloudTexel": [1.0 / self.cloud_width, 1.0 / self.cloud_height]})  # 等距柱状模式。
        self.bind_noise(self.sky_program)  # 云噪声。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制整张天空。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 先解绑，避免生成 mipmap 时读写同一张纹理。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_map)  # 绑定贴图。
        GL.glGenerateMipmap(GL.GL_TEXTURE_2D)  # 生成环境光层级。

    def render_clouds(self, frame: int, scene_time: float) -> None:
        """半分辨率步进体积云，再做时间累积与可分离模糊。"""
        forward, right, up, tan_half, aspect = self.basis()  # 相机基。
        target = self.cloud_index  # 本帧写入的累积目标。
        targets = (self.cloud_raw, self.cloud_accum)  # 两张轮换纹理。
        target_fbos = (self.cloud_raw_fbo, self.cloud_accum_fbo)  # 与纹理对应的帧缓冲。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, target_fbos[target])  # 本帧云目标。
        GL.glViewport(0, 0, self.cloud_width, self.cloud_height)  # 半分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.cloud_program)  # 云程序。
        self.bind_common(self.cloud_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.cloud_program, {"uResolution": [float(self.cloud_width), float(self.cloud_height)],
                                          "uForward": forward, "uRight": right, "uUp": up,
                                          "uTanHalfFov": tan_half, "uAspect": aspect, "uCloudSteps": CLOUD_STEPS,
                                          "uCloudBlend": 1.0 if frame < 2 else CLOUD_BLEND})  # 相机、步数与累积权重。
        self.bind_noise(self.cloud_program)  # 噪声。
        GL.glActiveTexture(GL.GL_TEXTURE14)  # 上一帧云。
        GL.glBindTexture(GL.GL_TEXTURE_2D, targets[1 - target])  # 另一张累积纹理。
        GL.glUniform1i(location(self.cloud_program, "uCloudHistory"), 14)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 步进并累积。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.cloud_temp_fbo)  # 横向模糊目标。
        GL.glViewport(0, 0, self.cloud_width, self.cloud_height)  # 半分辨率。
        GL.glUseProgram(self.cloud_blur_program)  # 模糊程序。
        set_uniforms(self.cloud_blur_program, {"uResolution": [float(self.cloud_width), float(self.cloud_height)],
                                               "uDirection": [1.0, 0.0]})  # 横向。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, targets[target])  # 本帧累积云。
        GL.glUniform1i(location(self.cloud_blur_program, "uSource"), 0)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 横向模糊。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.cloud_blur_fbo)  # 纵向模糊目标。
        GL.glViewport(0, 0, self.cloud_width, self.cloud_height)  # 半分辨率。
        set_uniforms(self.cloud_blur_program, {"uResolution": [float(self.cloud_width), float(self.cloud_height)],
                                               "uDirection": [0.0, 1.0]})  # 纵向。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.cloud_temp)  # 横向结果。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 纵向模糊。
        self.cloud_index = 1 - target  # 下一帧写另一张。

    def render_scene(self, frame: int, scene_time: float) -> None:
        """铺天空，再画地形与物体；输出直射、间接、法线与反照率。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.scene_fbo)  # 场景目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDepthMask(GL.GL_TRUE)  # 清深度前必须打开写掩码，否则深度不会被清。
        GL.glClearColor(0.0, 0.0, 0.0, 0.0)  # 清黑。
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)  # 清颜色与深度。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空不测深度。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        forward, right, up, tan_half, aspect = self.basis()  # 相机基。
        GL.glUseProgram(self.sky_program)  # 天空程序。
        self.bind_common(self.sky_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.sky_program, {"uResolution": [float(self.width), float(self.height)],
                                        "uForward": forward, "uRight": right, "uUp": up,
                                        "uTanHalfFov": tan_half, "uAspect": aspect, "uSkyMode": 0,
                                        "uSceneTarget": 1, "uUseCloudTexture": 1,
                                        "uCloudTexel": [1.0 / self.cloud_width, 1.0 / self.cloud_height]})  # 主画面模式。
        GL.glActiveTexture(GL.GL_TEXTURE12)  # 云纹理。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.cloud_blur)  # 模糊后的云。
        GL.glUniform1i(location(self.sky_program, "uCloudTexture"), 12)  # 采样器。
        self.bind_noise(self.sky_program)  # 其他噪声。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 天空。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 几何测深度。
        GL.glDepthMask(GL.GL_TRUE)  # 写深度。
        GL.glUseProgram(self.surface_program)  # 地表程序。
        self.bind_common(self.surface_program, frame, scene_time)  # 通用参数。
        self.bind_shadows(self.surface_program)  # 阴影。
        self.bind_sky_map(self.surface_program)  # 天空环境光。
        self.bind_noise(self.surface_program)  # 云影与蓝噪声。
        set_uniforms(self.surface_program, {"uViewProjection": self.view_projection(), "uIsTerrain": 1,
                                            "uReflectionPass": 0, "uAerialStrength": 0.25, "uDebugMode": self.surface_debug})  # 地形参数。
        GL.glBindVertexArray(self.terrain_vao)  # 地形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 绘制。
        set_uniforms(self.surface_program, {"uIsTerrain": 0, "uAerialStrength": 0.5, "uDebugMode": self.surface_debug})  # 物体参数。
        GL.glBindVertexArray(self.object_vao)  # 物体。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.object_triangles * 3)  # 绘制。

    def reflection_view_projection(self) -> tuple[list[float], list[float], list[float], list[float]]:
        """返回镜像相机的视图投影、位置与前右上去向。"""
        forward = self.camera.forward()  # 主相机前方向。
        right = self.camera.right()  # 右方向。
        up = self.camera.up()  # 上方向。
        mirrored_forward = [forward[0], -forward[1], forward[2]]  # 纵向翻转。
        mirrored_right = [right[0], -right[1], right[2]]  # 纵向翻转。
        mirrored_up = [up[0], -up[1], up[2]]  # 纵向翻转。
        position = [self.camera.position[0], 2.0 * geometry.WATER_LEVEL - self.camera.position[1], self.camera.position[2]]  # 关于水面镜像。
        view = [
            mirrored_right[0], mirrored_up[0], -mirrored_forward[0], 0.0,  # 第一列。
            mirrored_right[1], mirrored_up[1], -mirrored_forward[1], 0.0,  # 第二列。
            mirrored_right[2], mirrored_up[2], -mirrored_forward[2], 0.0,  # 第三列。
            -sum(mirrored_right[i] * position[i] for i in range(3)),  # 横向平移。
            -sum(mirrored_up[i] * position[i] for i in range(3)),  # 纵向平移。
            sum(mirrored_forward[i] * position[i] for i in range(3)),  # 深度平移。
            1.0,
        ]  # 镜像视图矩阵。
        matrix = multiply(self.projection(), view)  # 与主画面同一投影，反射纹素与屏幕对齐。
        return matrix, position, mirrored_forward, mirrored_right, mirrored_up  # 返回。

    def render_reflection(self, frame: int, scene_time: float) -> None:
        """用镜像相机渲染半分辨率倒影，包含天空、地形与物体。"""
        matrix, position, forward, right, up = self.reflection_view_projection()  # 镜像相机。
        tan_half = math.tan(math.radians(self.camera.fov) * 0.5)  # 视场角。
        aspect = self.width / self.height  # 宽高比。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.reflection_fbo)  # 反射目标。
        GL.glViewport(0, 0, self.reflection_width, self.reflection_height)  # 四分之一分辨率。
        GL.glDepthMask(GL.GL_TRUE)  # 清深度前打开写掩码。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 先画天空。
        GL.glClearColor(0.0, 0.0, 0.0, 1.0)  # 清黑。
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)  # 清颜色与深度。
        GL.glUseProgram(self.sky_program)  # 天空程序。
        self.bind_common(self.sky_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.sky_program, {"uResolution": [float(self.reflection_width), float(self.reflection_height)],
                                        "uForward": forward, "uRight": right, "uUp": up,
                                        "uTanHalfFov": tan_half, "uAspect": aspect, "uSkyMode": 2,
                                        "uSceneTarget": 0, "uUseCloudTexture": 0,
                                        "uCloudTexel": [1.0 / self.cloud_width, 1.0 / self.cloud_height]})  # 反射天空模式。
        self.bind_sky_map(self.sky_program)  # 采样已有天空立方体。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 天空。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 几何。
        GL.glDepthMask(GL.GL_TRUE)  # 写深度。
        GL.glUseProgram(self.surface_program)  # 地表程序。
        self.bind_common(self.surface_program, frame, scene_time)  # 通用参数。相机位置随后覆盖。
        self.bind_shadows(self.surface_program)  # 阴影。
        self.bind_sky_map(self.surface_program)  # 环境光。
        self.bind_noise(self.surface_program)  # 云影与蓝噪声。
        set_uniforms(self.surface_program, {"uViewProjection": matrix, "uIsTerrain": 1,
                                            "uReflectionPass": 1, "uAerialStrength": 0.35,
                                            "uCameraPosition": position})  # 反射地形。
        GL.glBindVertexArray(self.terrain_vao)  # 地形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 绘制。
        set_uniforms(self.surface_program, {"uIsTerrain": 0})  # 物体。
        GL.glBindVertexArray(self.object_vao)  # 物体。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.object_triangles * 3)  # 绘制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 解绑后才能安全生成 mipmap。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_color)  # 反射颜色。
        GL.glGenerateMipmap(GL.GL_TEXTURE_2D)  # 更新倒影的模糊层级。

    def render_gi(self, frame: int, scene_time: float) -> None:
        """半分辨率算环境光遮蔽、接触阴影与颜色反弹。"""
        target = 1 - self.gi_index  # 新历史目标。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.gi_fbo[target])  # 全局光目标。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.gi_program)  # 全局光程序。
        self.bind_common(self.gi_program, frame, scene_time)  # 通用参数。
        self.bind_noise(self.gi_program)  # 蓝噪声与云影。
        forward, right, up, tan_half, aspect = self.basis()  # 相机基。
        set_uniforms(self.gi_program, {
            "uResolution": [float(self.half_width), float(self.half_height)],
            "uFullResolution": [float(self.width), float(self.height)],
            "uProjection": self.projection(), "uProjectionInverse": perspective_inverse(FOV, aspect, NEAR, FAR),
            "uPreviousViewProjection": self.previous_view_projection, "uForward": forward, "uRight": right,
            "uUp": up, "uJitter": self.jitter_uv(), "uBlend": 1.0 if frame < 2 else GI_BLEND,
            "uAoStrength": AO_STRENGTH, "uContactStrength": CONTACT_STRENGTH,
        })  # 参数。
        for unit, texture, name in ((0, self.scene_depth, "uDepth"), (1, self.scene_normal, "uNormalDepth"),
                                    (2, self.scene_albedo, "uAlbedoRough"), (3, self.gi_targets[self.gi_index][0], "uHistoryAo"),
                                    (4, self.gi_targets[self.gi_index][1], "uHistoryBounce")):  # 输入纹理。
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)  # 选单元。
            GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
            GL.glUniform1i(location(self.gi_program, name), unit)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 计算。
        self.gi_index = target  # 更新历史。

    def render_composite(self, frame: int, scene_time: float) -> None:
        """把直射、间接、遮蔽与反弹合成到不透明颜色。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lit_fbo)  # 合成目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.composite_program)  # 合成程序。
        self.bind_common(self.composite_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.composite_program, {"uResolution": [float(self.width), float(self.height)],
                                              "uAOTexel": [1.0 / self.half_width, 1.0 / self.half_height],
                                              "uAoStrength": 1.0, "uContactStrength": CONTACT_STRENGTH,
                                              "uBounceStrength": BOUNCE_STRENGTH})  # 参数。
        for unit, texture, name in ((0, self.scene_direct, "uDirect"), (1, self.scene_indirect, "uIndirect"),
                                    (2, self.scene_normal, "uNormalDepth"), (3, self.scene_albedo, "uAlbedoRough"),
                                    (4, self.scene_depth, "uDepth"), (5, self.gi_targets[self.gi_index][0], "uAoContact"),
                                    (6, self.gi_targets[self.gi_index][1], "uBounce")):  # 输入。
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)  # 单元。
            GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
            GL.glUniform1i(location(self.composite_program, name), unit)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 合成。

    def render_water(self, frame: int, scene_time: float) -> None:
        """复制不透明颜色，再画水面；水面写入自己的深度供雾使用。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.water_fbo)  # 水面目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 先拷贝颜色。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.copy_program)  # 拷贝程序。
        set_uniform(self.copy_program, "uResolution", [float(self.width), float(self.height)])  # 尺寸。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lit_color)  # 不透明颜色。
        GL.glUniform1i(location(self.copy_program, "uSource"), 0)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 拷贝。
        GL.glBindFramebuffer(GL.GL_READ_FRAMEBUFFER, self.scene_fbo)  # 读场景深度。
        GL.glBindFramebuffer(GL.GL_DRAW_FRAMEBUFFER, self.water_fbo)  # 写水面深度。
        GL.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height,
                             GL.GL_DEPTH_BUFFER_BIT, GL.GL_NEAREST)  # 深度复制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.water_fbo)  # 继续画水面。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 水面被岸上地形遮挡。
        GL.glDepthMask(GL.GL_TRUE)  # 写水面深度。
        GL.glDisable(GL.GL_BLEND)  # 水面不透明写入。
        GL.glUseProgram(self.water_program)  # 水面程序。
        self.bind_common(self.water_program, frame, scene_time)  # 通用参数。
        self.bind_shadows(self.water_program)  # 地形与树冠也会在水面投下影子。
        self.bind_sky_map(self.water_program)  # 天空反射兜底。
        self.bind_noise(self.water_program)  # 泡沫用的二维扰动图。
        set_uniforms(self.water_program, {"uViewProjection": self.view_projection(),
                                          "uResolution": [float(self.width), float(self.height)],
                                          "uNear": NEAR, "uFar": FAR, "uWaterDebug": self.water_debug,
                                          "uReflectionTexel": [1.0 / self.reflection_width, 1.0 / self.reflection_height]})  # 水面参数。
        for unit, texture, name in ((13, self.reflection_color, "uReflection"), (14, self.lit_color, "uSceneColor"),
                                    (15, self.scene_depth, "uSceneDepth")):  # 输入。
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)  # 单元。
            GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
            GL.glUniform1i(location(self.water_program, name), unit)  # 采样器。
        GL.glBindVertexArray(self.water_vao)  # 水面。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.water_triangles * 3)  # 绘制。

    def render_fog(self, frame: int, scene_time: float) -> None:
        """按阴影贴图步进体积雾，合成到水面颜色。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.fog_fbo)  # 雾目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.fog_program)  # 雾程序。
        self.bind_common(self.fog_program, frame, scene_time)  # 通用参数。
        forward, right, up, tan_half, aspect = self.basis()  # 相机基。
        set_uniforms(self.fog_program, {"uResolution": [float(self.width), float(self.height)],
                                        "uForward": forward, "uRight": right, "uUp": up,
                                        "uTanHalfFov": tan_half, "uAspect": aspect, "uNear": NEAR, "uFar": FAR,
                                        "uFogDensity": FOG_DENSITY, "uFogHeight": FOG_HEIGHT,
                                        "uFogScatter": FOG_SCATTER, "uFogAmbient": FOG_AMBIENT,
                                        "uFogDebug": self.fog_debug})  # 雾参数。
        self.bind_shadows(self.fog_program)  # 阴影，用于光柱；先绑，避免覆盖场景颜色与深度。
        self.bind_sky_map(self.fog_program)  # 天光。
        self.bind_noise(self.fog_program)  # 雾噪声。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)  # 水面颜色。
        GL.glUniform1i(location(self.fog_program, "uSceneColor"), 0)  # 采样器。
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_depth)  # 水面深度。
        GL.glUniform1i(location(self.fog_program, "uDepth"), 1)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 雾。

    def render_taa(self, frame: int) -> None:
        """把雾结果与历史混合，输出抗锯齿颜色。"""
        target = 1 - self.taa_index  # 新历史。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.taa_fbo[target])  # 目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.taa_program)  # 抗锯齿程序。
        self.bind_common(self.taa_program, frame, self.scene_time)  # 通用参数。
        forward, right, up, _tan_half, aspect = self.basis()  # 相机基。
        set_uniforms(self.taa_program, {"uResolution": [float(self.width), float(self.height)],
                                        "uProjectionInverse": perspective_inverse(FOV, aspect, NEAR, FAR),
                                        "uPreviousViewProjection": self.previous_view_projection,
                                        "uCameraPos": self.camera.position, "uRight": right, "uUp": up,
                                        "uForward": forward, "uBlend": 1.0 if frame < 2 else TAA_BLEND,
                                        "uFar": FAR, "uJitter": self.jitter_uv()})  # 参数。
        for unit, texture, name in ((13, self.fog_color, "uCurrent"), (14, self.taa_color[self.taa_index], "uHistory"),
                                    (15, self.water_depth, "uDepth")):  # 输入。
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)  # 单元。
            GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定。
            GL.glUniform1i(location(self.taa_program, name), unit)  # 采样器。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 重投影。
        self.taa_index = target  # 更新历史。
        self.display_color = self.taa_color[target]  # 显示最新结果。

    def render_bloom(self) -> None:
        """三遍泛光：筛选降采样、再降一级、升采样合并。"""
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glUseProgram(self.bloom_program)  # 泛光程序。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_fbo)  # 细一级。
        GL.glViewport(0, 0, *BLOOM_SIZE)  # 视口。
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(self.width), float(self.height)],
                                          "uMode": 0, "uThreshold": 1.4})  # 筛选。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)  # 当前颜色。
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)  # 采样器。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_coarse_fbo)  # 粗一级。
        GL.glViewport(0, 0, *BLOOM_COARSE_SIZE)  # 视口。
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uMode": 1})  # 降采样。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)  # 细一级。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_combine_fbo)  # 合并目标。
        GL.glViewport(0, 0, *BLOOM_SIZE)  # 视口。
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uMode": 2})  # 合并。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 细一级。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)  # 绑定。
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)  # 采样器。
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 粗一级。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_coarse_color)  # 绑定。
        GL.glUniform1i(location(self.bloom_program, "uSmall"), 1)  # 采样器。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制。

    def render_exposure(self) -> None:
        """两级缩小，把几何画面压成一个平均对数亮度。"""
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.exposure_program)  # 曝光程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lit_color)  # 不透明场景颜色；水面不参与曝光，亮湖面不会把地面压黑。
        GL.glUniform1i(location(self.exposure_program, "uSource"), 0)  # 采样器。
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)  # 不透明场景深度；天空仍被排除。
        GL.glUniform1i(location(self.exposure_program, "uDepth"), 1)  # 采样器。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_tile_fbo)  # 第一级。
        GL.glViewport(0, 0, *LUMINANCE_SIZE)  # 视口。
        set_uniforms(self.exposure_program, {"uResolution": [float(LUMINANCE_SIZE[0]), float(LUMINANCE_SIZE[1])], "uMode": 0})  # 参数。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 绘制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_final_fbo)  # 最终。
        GL.glViewport(0, 0, 1, 1)  # 一像素。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_tile)  # 第一级。
        set_uniforms(self.exposure_program, {"uResolution": [1.0, 1.0], "uMode": 1})  # 参数。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 缩小。
        GL.glDepthMask(GL.GL_TRUE)  # 恢复深度写。

    def render_post(self, frame: int, scene_time: float) -> None:
        """曝光、泛光、AgX、调色与抖动，输出到屏幕。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 默认帧缓冲。
        GL.glViewport(0, 0, self.output_width, self.output_height)  # 输出分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 全屏。
        GL.glUseProgram(self.post_program)  # 后期程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)  # 抗锯齿颜色。
        GL.glUniform1i(location(self.post_program, "uColor"), 0)  # 采样器。
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 泛光。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_combine_color)  # 泛光。
        GL.glUniform1i(location(self.post_program, "uBloom"), 1)  # 采样器。
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 曝光。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)  # 曝光。
        GL.glUniform1i(location(self.post_program, "uExposure"), 2)  # 采样器。
        self.bind_common(self.post_program, frame, scene_time)  # 通用参数。
        set_uniforms(self.post_program, {"uResolution": [float(self.output_width), float(self.output_height)],
                                         "uExposureKey": self.exposure_key, "uTonemap": self.tonemap,
                                         "uAspect": self.output_width / self.output_height, "uBloomStrength": self.bloom_strength})  # 参数。
        GL.glBindVertexArray(self.fullscreen)  # 全屏。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 输出。

    def draw(self, frame: int, scene_time: float) -> None:
        """按固定顺序绘制一帧。"""
        self.frame = frame  # 当前帧。
        self.scene_time = scene_time  # 场景时间。
        pattern = JITTER_SEQUENCE[frame % len(JITTER_SEQUENCE)]  # 次像素抖动。
        self.jitter = (pattern[0] - 0.5, pattern[1] - 0.5)  # 居中。
        # 相机、太阳与时间都不变时，阴影、云影、天空贴图和倒影完全是上一帧的结果。
        # 固定机位截图里跳过这些重复计算，省下的时间留给云、雾、水面与时间抗锯齿。
        forward = self.camera.forward()  # 相机朝向参与签名，转身时阴影级联要重算。
        signature = (round(scene_time, 2), *[round(value, 3) for value in self.camera.position],
                     *[round(value, 3) for value in forward], *[round(value, 3) for value in self.sun])  # 场景签名。
        static_update = signature != self.static_signature  # 只有场景变化才更新静态资源。
        stages = (
            ("shadow", lambda: self.render_shadow(frame, scene_time) if static_update else None),  # 静态场景只烘一次阴影。
            ("cloudShadow", lambda: self.render_cloud_shadow(frame, scene_time) if static_update else None),  # 云影。
            ("skyCube", lambda: self.render_sky_map(frame, scene_time) if static_update else None),  # 天空立方体。
            ("clouds", lambda: self.render_clouds(frame, scene_time)),  # 体积云。
            ("scene", lambda: self.render_scene(frame, scene_time)),  # 不透明场景。
            ("reflection", lambda: self.render_reflection(frame, scene_time) if static_update else None),  # 平面反射。
            ("gi", lambda: self.render_gi(frame, scene_time)),  # 遮蔽与反弹。
            ("composite", lambda: self.render_composite(frame, scene_time)),  # 直射与间接合成。
            ("water", lambda: self.render_water(frame, scene_time)),  # 水面。
            ("fog", lambda: self.render_fog(frame, scene_time)),  # 体积雾。
            ("taa", lambda: self.render_taa(frame)),  # 抗锯齿。
            ("bloom", lambda: self.render_bloom()),  # 泛光。
            ("exposure", lambda: self.render_exposure()),  # 曝光。
            ("post", lambda: self.render_post(frame, scene_time)),  # 显示。
        )
        for name, stage in stages:  # 逐阶段。
            started = time.perf_counter()  # 开始计时。
            stage()  # 执行。
            if self.profile:  # 开发性能。
                GL.glFinish()  # 等待显卡。
                print(f"{name:>10}: {(time.perf_counter() - started) * 1000.0:6.2f} ms")  # 输出。
        self.static_signature = signature  # 记录这一帧的场景状态。
        self.previous_view_projection = self.view_projection()  # 保存历史矩阵。
        self.frame = frame  # 保留。

    def exposure_value(self) -> float:
        """读回一个像素的平均对数亮度。"""
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)  # 绑定。
        data = GL.glGetTexImage(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, GL.GL_FLOAT)  # 读回。
        values = array("f")  # 浮点数组。
        values.frombytes(bytes(data))  # 打包字节。
        return float(values[0])  # 红通道。

    def screenshot(self, path: Path) -> None:
        """读回默认帧缓冲并写成 PNG。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 默认帧缓冲。
        GL.glReadBuffer(GL.GL_BACK)  # 后缓冲。
        pixels = GL.glReadPixels(0, 0, self.output_width, self.output_height, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)  # 读像素。
        rgb = bytearray(self.output_width * self.output_height * 3)  # 三通道输出。
        for index in range(self.output_width * self.output_height):  # 逐像素。
            source = index * 4  # 输入偏移。
            target = index * 3  # 输出偏移。
            rgb[target:target + 3] = pixels[source:source + 3]  # 去掉透明通道。
        path.parent.mkdir(parents=True, exist_ok=True)  # 创建目录。
        png.write_rgb(path, self.output_width, self.output_height, bytes(rgb))  # 写 PNG。

    def close(self) -> None:
        """释放显卡对象与窗口。"""
        for program in (self.sky_program, self.cloud_program, self.cloud_blur_program, self.cloud_shadow_program,
                        self.surface_program, self.shadow_program, self.water_program, self.gi_program,
                        self.composite_program, self.fog_program, self.taa_program, self.bloom_program,
                        self.exposure_program, self.post_program, self.copy_program):  # 全部程序。
            GL.glDeleteProgram(program)  # 删除。
        GL.glDeleteVertexArrays(4, [self.fullscreen, self.terrain_vao, self.object_vao, self.water_vao])  # 顶点数组。
        GL.glDeleteBuffers(3, [self.terrain_vbo, self.object_vbo, self.water_vbo])  # 缓冲。
        textures = [self.noise_base, self.noise_detail, self.noise_curl, self.blue_noise, self.sky_map, self.atmo_lut,
                    self.scene_direct, self.scene_indirect, self.scene_normal, self.scene_albedo, self.scene_depth,
                    self.reflection_color, self.reflection_depth, self.lit_color, self.water_color, self.water_depth,
                    self.fog_color, self.cloud_raw, self.cloud_accum, self.cloud_temp, self.cloud_blur, self.cloud_shadow, self.lum_tile, self.lum_final,
                    self.bloom_color, self.bloom_coarse_color, self.bloom_combine_color]  # 单张纹理。
        textures.extend(self.shadow_depths)  # 阴影。
        textures.extend(self.taa_color)  # 抗锯齿历史。
        for pair in self.gi_targets:  # 全局光附件。
            textures.extend(pair)  # 加入。
        GL.glDeleteTextures(textures)  # 删除纹理。
        fbos = [self.scene_fbo, self.reflection_fbo, self.lit_fbo, self.water_fbo, self.fog_fbo,
                self.cloud_raw_fbo, self.cloud_accum_fbo, self.cloud_shadow_fbo, self.lum_tile_fbo, self.lum_final_fbo,
                self.bloom_fbo, self.bloom_coarse_fbo, self.bloom_combine_fbo, self.sky_fbo]  # 帧缓冲。
        fbos.extend(self.shadow_fbos)  # 阴影。
        fbos.extend(self.taa_fbo)  # 抗锯齿。
        fbos.extend(self.gi_fbo)  # 全局光。
        GL.glDeleteFramebuffers(len(fbos), fbos)  # 删除。
        glfw.destroy_window(self.window)  # 销毁窗口。
        glfw.terminate()  # 释放 GLFW。


def run(args) -> None:
    """按参数运行截图或交互模式，并写出性能记录。"""
    world = World(args.width, args.height, args.tonemap, args.exposure_key)  # 构建场景。
    world.bloom_strength = args.bloom  # 泛光强度。
    world.profile = args.profile  # 性能分析。
    world.water_debug = args.water_debug  # 水面调试模式。
    world.surface_debug = args.surface_debug  # 地表调试模式。
    world.fog_debug = args.fog_debug  # 雾调试模式。
    output = Path(args.screenshot)  # 截图路径。
    perf_path = Path(args.perf)  # 性能记录路径。
    try:
        if args.window:  # 交互模式。
            world.install_input()  # 显示窗口。
            start = time.perf_counter()  # 起始时间。
            frame = 0  # 帧号。
            while not glfw.window_should_close(world.window):  # 主循环。
                now = time.perf_counter()  # 当前时间。
                delta = now - start  # 场景时间。
                world.camera.move(world.keys, max(0.0, min(0.05, 1.0 / 60.0)), glfw)  # 移动相机。
                world.draw(frame, delta)  # 绘制。
                if world.screenshot_request:  # 截图请求。
                    world.screenshot(output)  # 保存。
                    world.screenshot_request = False  # 清除。
                    print(f"截图：{output}")  # 提示。
                glfw.swap_buffers(world.window)  # 交换。
                glfw.poll_events()  # 事件。
                frame += 1  # 下一帧。
            return  # 交互模式结束。
        for frame in range(args.warmup):  # 预热，让云、TAA 与曝光收敛。
            world.draw(frame, args.time)  # 绘制。
        GL.glFinish()  # 等显卡完成。
        times = []  # 帧时。
        for frame in range(args.frames):  # 计时帧。
            started = time.perf_counter()  # 开始。
            world.draw(args.warmup + frame, args.time)  # 绘制。
            GL.glFinish()  # 同步，测量真实帧时。
            times.append((time.perf_counter() - started) * 1000.0)  # 毫秒。
        world.screenshot(output)  # 保存截图。
        average = sum(times) / len(times)  # 平均。
        average_log = world.exposure_value()  # 平均对数亮度。
        report = {
            "width": args.width, "height": args.height, "frames": args.frames, "warmup": args.warmup,
            "internalWidth": world.width, "internalHeight": world.height, "renderScale": RENDER_SCALE,
            "averageMs": average, "medianMs": percentile(times, 0.5), "p95Ms": percentile(times, 0.95),
            "minMs": min(times), "maxMs": max(times), "fps": 1000.0 / average,
            "device": world.device, "terrainTriangles": world.terrain_triangles,
            "objectTriangles": world.object_triangles, "waterTriangles": world.water_triangles,
            "shadowMapSize": CASCADE_SIZE, "shadowCascades": CASCADE_COUNT,
            "cloudResolution": [world.cloud_width, world.cloud_height], "cloudSteps": CLOUD_STEPS,
            "averageLogLuminance": average_log, "averageLuminance": 2.0 ** average_log,
            "camera": world.camera.position, "target": list(geometry.LOOK_TARGET),
            "sun": world.sun, "time": args.time, "tonemap": args.tonemap,
            "sunIrradiance": SUN_IRRADIANCE, "skyIntensity": SKY_INTENSITY,
            "exposureKey": args.exposure_key, "bloomStrength": args.bloom,
        }
        perf_path.parent.mkdir(parents=True, exist_ok=True)  # 创建目录。
        perf_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")  # 写记录。
        print(f"截图：{output}")  # 提示。
        print(f"帧时：平均 {average:.2f} 毫秒，中位 {report['medianMs']:.2f}，95 分位 {report['p95Ms']:.2f}，"
              f"最小 {report['minMs']:.2f}，最大 {report['maxMs']:.2f}，约 {report['fps']:.1f} 帧每秒")  # 帧时。
        print(f"三角形：地形 {report['terrainTriangles']}，物体 {report['objectTriangles']}，水面 {report['waterTriangles']}")  # 规模。
        print(f"设备：{world.device['renderer']} / {world.device['version']}")  # 设备。
        print(f"记录：{perf_path}")  # 路径。
    finally:
        world.close()  # 释放。


def main() -> None:
    """解析参数并启动验证场景。"""
    parser = argparse.ArgumentParser(description="omni-gfx 光影验证场景")  # 中文帮助。
    parser.add_argument("--width", type=int, default=WIDTH, help="画面宽度")  # 宽度。
    parser.add_argument("--height", type=int, default=HEIGHT, help="画面高度")  # 高度。
    parser.add_argument("--frames", type=int, default=120, help="计时帧数")  # 帧数。
    parser.add_argument("--warmup", type=int, default=30, help="预热帧数")  # 预热。
    parser.add_argument("--screenshot", default=str(ROOT / ".dev/omni-gfx/world-lighting.png"), help="截图路径")  # 截图。
    parser.add_argument("--perf", default=str(ROOT / ".dev/omni-gfx/perf-lighting.json"), help="性能记录路径")  # 记录。
    parser.add_argument("--window", action="store_true", help="打开可交互窗口")  # 交互。
    parser.add_argument("--time", type=float, default=14.0, help="固定场景时间，秒")  # 时间。
    parser.add_argument("--exposure-key", type=float, default=EXPOSURE_KEY, help="自动曝光目标亮度")  # 曝光。
    parser.add_argument("--tonemap", type=int, default=0, choices=(0, 1, 2), help="零 AgX，一 ACES，二无压缩")  # 曲线。
    parser.add_argument("--bloom", type=float, default=BLOOM_STRENGTH, help="泛光强度")  # 泛光。
    parser.add_argument("--water-debug", type=int, default=0, help="水面调试：零正常，一法线，二反射，三折射，四高光")  # 水面调试。
    parser.add_argument("--surface-debug", type=int, default=0, help="地表调试：零正常，二反照率")  # 地表调试。
    parser.add_argument("--fog-debug", type=int, default=0, choices=(0, 1, 2), help="雾调试：零正常，一可见度，二散射")  # 雾调试。
    parser.add_argument("--profile", action="store_true", help="输出每阶段耗时，仅用于性能分析")  # 分析。
    args = parser.parse_args()  # 解析。
    run(args)  # 运行。


if __name__ == "__main__":
    main()  # 入口。
