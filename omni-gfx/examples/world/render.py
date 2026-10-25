"""不启动 Minecraft 的程序化测试世界：体素地形、天空、体积云、方向光阴影、水面与后期。

调用位置：`python omni-gfx/build.py demo` 或直接运行本文件。
调用示例：
    python omni-gfx/examples/world/render.py --frames 120 --screenshot .dev/omni-gfx/world-final.png
    python omni-gfx/examples/world/render.py --window
设计原因与取舍：
    测试世界是独立消费者：它只读取 `shaders/omni-gfx` 里生成的 GLSL，
    因此能证明产物真的能编译、能出图，而不是只在生成器里看起来正确。
    场景全部程序化生成，不依赖 Minecraft 存档、材质包或网络资源。
    体积云在半分辨率计算并做时间累积，地形阴影改用方向光阴影贴图，
    这样在集成显卡上也能跑到三十帧以上；每一步都保留可以单独关闭的边界。
    默认隐藏窗口出图并计时；加窗口参数才进入可移动相机的交互模式。
"""
from __future__ import annotations

import argparse  # 命令行参数，截图与交互共用一套入口。
import ctypes  # 顶点属性偏移必须用空指针包装，否则会被当成 Python 对象地址。
import json  # 性能记录写成机器可读文件。
import math  # 视场角与矩阵计算。
import sys  # 调整工具目录的搜索路径。
import time  # 帧时测量。
from array import array  # 读回一像素曝光统计时解码浮点。
from pathlib import Path  # 输出路径。

import glfw  # 窗口与输入。
from OpenGL import GL  # 绘制调用。

HERE = Path(__file__).resolve().parent  # 测试世界目录。
LIB = HERE.parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用上下文与着色器工具。
sys.path.insert(0, str(HERE))  # 导入同目录的地形、相机与图片模块。

import bluenoise  # 启动时生成一次蓝噪声贴图。
import camera  # 相机与矩阵。
import gl  # OpenGL 小工具。
import png  # 无依赖图片写入。
import terrain  # 高度图与网格。
import vegetation  # 树、草叶、花与散落岩石。

TERRAIN_SIZE = 128  # 地形边长，单位为方块。
CASCADE_COUNT = 3  # 方向光级联数，近景一级、整岛一级、远景一级。
CASCADE_SIZE = 1024  # 每级阴影贴图边长，三级合计与原来一张两千零四十八相当。
CASCADE_EXTENTS = (46.0, 92.0, 184.0)  # 每级正交视锥的半边长，米。
CASCADE_SPLITS = (42.0, 105.0, 280.0)  # 按视深度选级的分界，米。
CASCADE_BLEND = 8.0  # 级联交界的过渡宽度，米。
SKY_CUBE_SIZE = 128  # 反射立方体贴图的边长；反射本身会被波纹打散，一百二十八已经够。
WATER_RADIUS = 1800.0  # 水面半径，米；肉眼地平线在五公里内，两万米足够，还能保住深度精度。
WATER_RINGS = 96  # 水面径向分格，越靠外格越宽。
WATER_SEGMENTS = 160  # 水面环向分格，决定岸边弧线的圆滑程度。
NEAR = 0.3  # 投影近平面；再小会浪费远处的深度精度，岸边容易与水面闪烁。
FAR = 30000.0  # 投影远平面要盖住水面远端，太远会牺牲深度精度。
DEFAULT_SUN = [0.72, 0.52, 0.46]  # 默认太阳方向：右前方三十一度，岛正面受光，树影落在左侧地面上。
DEFAULT_CAMERA = [126.0, 31.0, 142.0]  # 固定机位：岛外水面上方一百米，前景留下反光水面与倒影。
DEFAULT_TARGET = [58.0, 16.0, 58.0]  # 看向岛的中心偏上，树线与天空各占一半。
BLUE_NOISE_SIZE = 64  # 蓝噪声贴图边长，必须与生成库里的平铺周期一致。
LUMINANCE_SIZE = (64, 36)  # 曝光统计第一级的尺寸，十六比九的小图。
BLOOM_SIZE = (320, 180)  # 泛光最细一级的尺寸，四分之一分辨率。
BLOOM_COARSE_SIZE = (160, 90)  # 泛光最粗一级的尺寸。
GI_BLEND = 0.20  # 遮蔽时间累积里本帧的权重，其余来自历史。
SKY_STEPS = 6  # 半分辨率天空的大气积分段数。
CLOUD_STEPS = 14  # 半分辨率体积云的沿视线步数，时间累积会把台阶抹平。
CUBE_SKY_STEPS = 4  # 反射立方体贴图的大气段数，反射看不出这么多细节。
CUBE_CLOUD_STEPS = 4  # 反射立方体贴图的云步数，反射里只看到模糊团块。
SKY_HISTORY_BLEND = 0.14  # 时间累积里本帧样本的权重，其余来自历史。
SUN_STRENGTH = 2.8  # 太阳辐照度倍率，地面与水面使用；再高叶绿会被压成黄白。
CLOUD_SUN_STRENGTH = 1.35  # 云的太阳强度比地面低，逆光云才不会整片死白。
SKY_STRENGTH = 0.62  # 天空环境光的整体倍率。
WIND_STRENGTH = 1.0  # 风摆幅度倍率，零可以完全关掉动画。
WETNESS = 0.85  # 近水沙地的湿润程度，影响反光与颜色深浅。
WATER_LEVEL = terrain.SEA_LEVEL + 0.035  # 水面比整格沙滩高一点，避免和方块顶面同高产生闪烁。
JITTER_SEQUENCE = ((0.5, 0.5), (0.25, 0.75), (0.75, 0.25), (0.125, 0.375), (0.625, 0.875),
                   (0.375, 0.125), (0.875, 0.625), (0.0625, 0.5625))  # 八相位的次像素抖动，按帧循环。


def make_program(name: str, vertex: str, fragment: str) -> int:
    """编译测试世界的一个着色器程序，返回程序编号。

    `name` 只用于错误信息；顶点与片元路径相对本目录的着色器文件夹。
    """
    return gl.build_program(HERE / "shaders" / vertex, HERE / "shaders" / fragment)  # 引用展开交给共用工具。


def upload_mesh(vertices, attributes: list[tuple[int, int, int]]) -> tuple[int, int]:
    """把交错顶点数组上传到显卡，返回顶点数组与缓冲编号。

    `attributes` 每项是位置、通道数与字节偏移；调用方保证偏移与顶点着色器一致。
    """
    vao = GL.glGenVertexArrays(1)  # 顶点数组保存属性布局。
    vbo = GL.glGenBuffers(1)  # 顶点缓冲保存数据。
    GL.glBindVertexArray(vao)  # 先绑定数组，后面的属性设置会记在它上面。
    GL.glBindBuffer(GL.GL_ARRAY_BUFFER, vbo)  # 再绑定数据缓冲。
    GL.glBufferData(GL.GL_ARRAY_BUFFER, vertices.tobytes(), GL.GL_STATIC_DRAW)  # 场景构建后不再改动。
    stride = sum(count for _, count, _ in attributes) * 4  # 每个顶点的字节数。
    for location_index, count, offset in attributes:  # 逐属性启用并指定格式。
        GL.glEnableVertexAttribArray(location_index)  # 打开这个通道。
        # 偏移必须包成空指针，否则会被解释成 Python 对象地址，顶点会全部飞走。
        GL.glVertexAttribPointer(location_index, count, GL.GL_FLOAT, GL.GL_FALSE, stride, ctypes.c_void_p(offset))
    return vao, vbo  # 调用方负责释放。


def make_depth_target(size: int) -> tuple[int, int]:
    """创建只有深度附件的帧缓冲，返回帧缓冲与深度纹理。

    阴影贴图不写颜色，所以显式关闭颜色读写，驱动不会分配无用的颜色缓冲。
    """
    texture = GL.glGenTextures(1)  # 深度纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 后续设置作用于这张纹理。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_DEPTH_COMPONENT24, size, size, 0,
                    GL.GL_DEPTH_COMPONENT, GL.GL_FLOAT, None)  # 二十四位深度足够覆盖全岛。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 深度不做插值，取样精确到纹素。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 放大同样用最近值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 范围外不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 范围外不重复。
    fbo = GL.glGenFramebuffers(1)  # 渲染阴影时挂载。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 之后的附件设置作用于它。
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_ATTACHMENT, GL.GL_TEXTURE_2D, texture, 0)  # 只挂深度。
    GL.glDrawBuffer(GL.GL_NONE)  # 不写颜色。
    GL.glReadBuffer(GL.GL_NONE)  # 也不读颜色。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 驱动不支持时尽早报错。
        raise RuntimeError("阴影帧缓冲不完整")
    return fbo, texture  # 调用方负责释放。


def make_color_target(width: int, height: int) -> tuple[int, int]:
    """创建只有颜色附件的十六位浮点目标，返回帧缓冲与纹理。

    天空采样、时间累积与曝光统计都不需要深度，单独建目标比复用带深度的目标省显存。
    """
    texture = GL.glGenTextures(1)  # 颜色纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定后分配。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA16F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)  # 十六位浮点保留高动态范围。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 升采样用线性。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也用线性。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    fbo = GL.glGenFramebuffers(1)  # 绘制时挂载。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 之后的附件设置作用于它。
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0, GL.GL_TEXTURE_2D, texture, 0)  # 挂颜色。
    GL.glDrawBuffer(GL.GL_COLOR_ATTACHMENT0)  # 只写这一个附件。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 驱动不支持时尽早报错。
        raise RuntimeError("浮点颜色帧缓冲不完整")
    return fbo, texture  # 调用方负责释放。


def make_sky_cube() -> tuple[int, int]:
    """创建天空立方体贴图与只用于渲染它的帧缓冲。"""
    texture = GL.glGenTextures(1)  # 反射用的立方体贴图。
    GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, texture)  # 绑定后逐个面分配。
    for face in range(6):  # 六个面使用同一尺寸与格式，采样时不用再判断面类型。
        GL.glTexImage2D(GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, 0, GL.GL_RGBA16F, SKY_CUBE_SIZE, SKY_CUBE_SIZE,
                        0, GL.GL_RGBA, GL.GL_FLOAT, None)  # 十六位浮点，保留云与太阳高光。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)  # 反射按距离选低分辨率层级。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也平滑。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_R, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    fbo = GL.glGenFramebuffers(1)  # 渲染每个面时临时挂载。
    return texture, fbo  # 调用方负责释放。


def make_blue_noise() -> int:
    """把启动时算好的蓝噪声上传成单通道纹理，返回纹理编号。"""
    data = bluenoise.texture_data()  # 纯 Python 生成，十六毫秒左右。
    texture = GL.glGenTextures(1)  # 抖动纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 绑定后上传。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_R8, BLUE_NOISE_SIZE, BLUE_NOISE_SIZE, 0,
                    GL.GL_RED, GL.GL_UNSIGNED_BYTE, data)  # 单通道八位，够六十四个抖动级别。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 抖动值必须精确读取，不能插值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 放大也用最近值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)  # 平铺到整幅画面。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)  # 平铺到整幅画面。
    return texture  # 调用方负责删除。


def location(program: int, name: str) -> int:
    """取 uniform 位置；不存在时返回负一，OpenGL 会忽略对应写入。"""
    return GL.glGetUniformLocation(program, name)


def set_uniform(program: int, name: str, value) -> None:
    """按 Python 类型选择写入函数，减少每个阶段重复的样板。

    位置为负说明这一段着色器没有用到该名字，直接跳过，避免为了删一个 uniform 改多处。
    """
    where = location(program, name)  # 先取位置。
    if where < 0:  # 没用到的 uniform 不用写。
        return
    if isinstance(value, bool):  # 布尔量按整数传，着色器里用 int 接收。
        GL.glUniform1i(where, 1 if value else 0)
    elif isinstance(value, int):  # 整数走 1i。
        GL.glUniform1i(where, value)
    elif isinstance(value, float):  # 浮点走 1f。
        GL.glUniform1f(where, value)
    elif isinstance(value, (list, tuple)):  # 向量与矩阵按长度分派。
        if len(value) == 2:
            GL.glUniform2f(where, *value)
        elif len(value) == 3:
            GL.glUniform3f(where, *value)
        elif len(value) == 4:
            GL.glUniform4f(where, *value)
        elif len(value) == 16:  # 列主序四乘四矩阵，上传时不转置。
            GL.glUniformMatrix4fv(where, 1, GL.GL_FALSE, value)
        else:
            raise ValueError(f"不支持的 uniform 长度：{name} {len(value)}")


def set_uniforms(program: int, values: dict) -> None:
    """一次写入一组 uniform，调用方按名字给值，顺序不影响结果。"""
    for name, value in values.items():  # 逐项交给类型分派。
        set_uniform(program, name, value)


def multiply(a: list[float], b: list[float]) -> list[float]:
    """列主序四乘四矩阵相乘，返回 a 乘 b。

    OpenGL 的矩阵按列存放；这里按同一约定计算，上传时不需要转置。
    """
    result = [0.0] * 16  # 结果矩阵。
    for column in range(4):  # 遍历结果的每一列。
        for row in range(4):  # 遍历每一行。
            result[column * 4 + row] = sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))  # 点积。
    return result  # 可直接上传。


def orthographic(left: float, right: float, bottom: float, top: float, near: float, far: float) -> list[float]:
    """列主序正交投影矩阵，方向光没有透视，用正交投影覆盖全岛。"""
    return [
        2.0 / (right - left), 0.0, 0.0, 0.0,  # 横向缩放。
        0.0, 2.0 / (top - bottom), 0.0, 0.0,  # 纵向缩放。
        0.0, 0.0, -2.0 / (far - near), 0.0,  # 深度映射到负一到一。
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,  # 平移项。
    ]


def perspective_inverse(fov: float, aspect: float, near: float, far: float) -> list[float]:
    """列主序透视逆投影矩阵，用来把屏幕深度还原成视空间位置。

    只按解析式填写非零项：生成库的深度反解只读第二列第三行与第三列第三行，
    视空间位置还原读第一、二列的对角与第四列的平移，其他项本来就不参与。
    """
    f = 1.0 / math.tan(math.radians(fov) * 0.5)  # 视场角一半的正切倒数。
    depth_scale = (near - far) / (2.0 * far * near)  # 深度反解的斜率项。
    depth_bias = (far + near) / (2.0 * far * near)  # 深度反解的常数项。
    return [
        aspect / f, 0.0, 0.0, 0.0,  # 第一列。
        0.0, 1.0 / f, 0.0, 0.0,  # 第二列。
        0.0, 0.0, 0.0, depth_scale,  # 第三列，只有第四行参与深度反解。
        0.0, 0.0, -1.0, depth_bias,  # 第四列，平移与深度常数。
    ]


def percentile(values: list[float], fraction: float) -> float:
    """返回排序后指定分位的值，用于报告慢帧。"""
    ordered = sorted(values)  # 不改动原列表。
    index = min(len(ordered) - 1, max(0, int(len(ordered) * fraction)))  # 分位落在有效范围内。
    return ordered[index]  # 返回该位置的值。


class World:
    """测试世界的全部显卡资源与绘制顺序。"""

    def __init__(self, width: int, height: int, tonemap: int, cloud_cover: float, sun: list[float],
                 exposure_key: float) -> None:
        """创建窗口、程序、网格与离屏目标，之后可反复绘制。"""
        self.width = width  # 画面宽度。
        self.height = height  # 画面高度。
        self.half_width = max(1, width // 2)  # 天空与云的半分辨率宽度。
        self.half_height = max(1, height // 2)  # 天空与云的半分辨率高度。
        self.tonemap = tonemap  # 后期曲线编号。
        self.cloud_cover = cloud_cover  # 云量。
        self.exposure_key = exposure_key  # 自动曝光的目标亮度。
        self.sun = camera.normalize(sun)  # 太阳方向。
        self.window = gl.init_window(width, height, "omni-gfx 测试世界", visible=False)  # 先隐藏，交互模式再显示。
        self.device = gl.device_info()  # 设备信息随性能记录保存。
        self.fullscreen = gl.fullscreen_vao()  # 全屏三角形共用的空顶点数组。
        # 每个阶段一个程序，互不共享 uniform 状态，改一处不会影响另一处。
        self.sky_program = make_program("天空", "fullscreen.vert", "sky.frag")
        self.accum_program = make_program("累积", "fullscreen.vert", "sky_accum.frag")
        self.composite_program = make_program("合成", "fullscreen.vert", "sky_composite.frag")
        self.terrain_program = make_program("地形", "terrain.vert", "terrain.frag")
        self.shadow_program = make_program("阴影", "shadow.vert", "shadow.frag")
        self.water_program = make_program("水面", "water.vert", "water.frag")
        self.reflection_program = make_program("反射", "water.vert", "reflection.frag")
        self.denoise_program = make_program("反射降噪", "fullscreen.vert", "reflection_denoise.frag")
        self.gi_program = make_program("全局光", "fullscreen.vert", "gi.frag")
        self.taa_program = make_program("时间抗锯齿", "fullscreen.vert", "taa.frag")
        self.bloom_program = make_program("泛光", "fullscreen.vert", "bloom.frag")
        self.exposure_program = make_program("曝光", "fullscreen.vert", "exposure.frag")
        self.post_program = make_program("后期", "fullscreen.vert", "post.frag")
        self.copy_program = make_program("场景拷贝", "fullscreen.vert", "copy.frag")  # 水面之前复制场景颜色。
        heights = terrain.heightmap(TERRAIN_SIZE)  # 固定种子，画面可重复。
        vertices, self.terrain_triangles = terrain.build_mesh(heights, TERRAIN_SIZE)  # 顶面与侧墙。
        self.terrain_triangles += vegetation.add_vegetation(vertices, heights, TERRAIN_SIZE)  # 树、草、花与石块。
        self.terrain_vao, self.terrain_vbo = upload_mesh(  # 位置、法线、颜色、遮蔽、材质、风摆。
            vertices, [(0, 3, 0), (1, 3, 12), (2, 3, 24), (3, 1, 36), (4, 1, 40), (5, 1, 44)])
        water_vertices, self.water_triangles = terrain.water_disc(WATER_RADIUS, WATER_RINGS, WATER_SEGMENTS)  # 一直铺到地平线之外。
        self.water_vao, self.water_vbo = upload_mesh(water_vertices, [(0, 2, 0)])
        self.blue_noise = make_blue_noise()  # 云步进与雾的抖动来源。
        self.shadow_fbos = []  # 三级阴影各一个帧缓冲。
        self.shadow_depths = []  # 三级阴影各一张深度纹理。
        for _ in range(CASCADE_COUNT):  # 每级单独一张贴图，采样时只能按分支选择。
            fbo, depth = make_depth_target(CASCADE_SIZE)
            self.shadow_fbos.append(fbo)
            self.shadow_depths.append(depth)
        self.scene_fbo, scene_colors, self.scene_depth = gl.multi_color_depth_target(width, height, 2)  # 颜色与法线两张附件。
        self.scene_color, self.scene_normal = scene_colors[0], scene_colors[1]  # 分开保存便于绑定。
        self.water_fbo, self.water_color, self.water_depth = gl.color_depth_target(width, height)  # 水面合成结果。
        self.reflection_fbo, reflection_colors, _ = gl.multi_color_depth_target(self.half_width, self.half_height, 3)  # 反射颜色、深度、法线。
        self.reflection_color, self.reflection_depth, self.reflection_normal = reflection_colors  # 三个附件分开保存。
        self.denoised_fbo, self.denoised_color = make_color_target(self.half_width, self.half_height)  # 降噪后的反射。
        self.gi_fbo = []  # 两张遮蔽历史交替读写。
        self.gi_color = []  # 遮蔽纹理。
        for _ in range(2):  # 乒乓缓冲避免读写同一张纹理。
            fbo, texture = make_color_target(self.half_width, self.half_height)
            self.gi_fbo.append(fbo)
            self.gi_color.append(texture)
        self.taa_fbo = []  # 两张抗锯齿历史交替读写。
        self.taa_color = []  # 抗锯齿纹理。
        for _ in range(2):  # 本帧写一张、读另一张。
            fbo, texture = make_color_target(width, height)  # 抗锯齿只要颜色，不需要深度附件。
            self.taa_fbo.append(fbo)
            self.taa_color.append(texture)
        self.bloom_fbo, self.bloom_color = make_color_target(BLOOM_SIZE[0], BLOOM_SIZE[1])  # 泛光较细一级。
        self.bloom_coarse_fbo, self.bloom_coarse_color = make_color_target(BLOOM_COARSE_SIZE[0], BLOOM_COARSE_SIZE[1])  # 泛光较粗一级。
        self.bloom_combine_fbo, self.bloom_combine_color = make_color_target(BLOOM_SIZE[0], BLOOM_SIZE[1])  # 合并结果，避免读写同一张。
        self.sky_sample_fbo, self.sky_sample = make_color_target(self.half_width, self.half_height)  # 本帧天空样本。
        self.sky_history_fbo = []  # 两张历史缓冲交替读写。
        self.sky_history = []  # 历史纹理编号。
        for _ in range(2):  # 乒乓缓冲避免读写同一张纹理。
            fbo, texture = make_color_target(self.half_width, self.half_height)
            self.sky_history_fbo.append(fbo)
            self.sky_history.append(texture)
        self.lum_tile_fbo, self.lum_tile = make_color_target(LUMINANCE_SIZE[0], LUMINANCE_SIZE[1])  # 第一级曝光统计。
        self.lum_final_fbo, self.lum_final = make_color_target(1, 1)  # 一个像素的平均对数亮度。
        self.sky_cube, self.sky_fbo = make_sky_cube()  # 反射用天空。
        self.history_index = 0  # 当前可读的历史缓冲。
        self.gi_index = 0  # 当前可读的遮蔽历史。
        self.taa_index = 0  # 当前可读的抗锯齿历史。
        self.velocity = [0.0, 0.0]  # 整屏位移，静止机位下为零。
        self.prev_basis = None  # 上一帧相机基向量，重投影用。
        self.jitter = (0.0, 0.0)  # 本帧次像素抖动，单位是像素。
        self.camera = camera.Camera(list(DEFAULT_CAMERA), fov=55.0)  # 初始相机，站在岛外水面上方。
        self.camera.look_at(list(DEFAULT_TARGET))  # 略微俯视，岛、树线与倒影都进入画面。
        self.light_matrices = self.build_light_matrix()  # 三级方向光矩阵只与太阳有关，建一次即可。
        self.previous_view_projection = self.view_projection()  # 上一帧视图投影，第一帧用当前值。
        self.display_color = self.water_color  # 抗锯齿前的画面来源，第一帧先指向水面结果。
        self.keys: set[int] = set()  # 交互模式按下的键。
        self.first_mouse = True  # 第一帧鼠标位置只记录不转向。
        self.last_mouse = (0.0, 0.0)  # 上一帧鼠标位置。
        self.screenshot_request = False  # 交互模式按 F12 时置位。

    def build_light_matrix(self) -> list[list[float]]:
        """构造三级方向光的视图投影矩阵，每一级覆盖不同大小的区域。

        为什么用级联：近景那级只覆盖四十米，每米有二十五个纹素，墙根与树叶的投影才清楚；
        远景那级覆盖一百六十米，纹素变粗但只用于远处，近处不会浪费分辨率。
        三级都以岛中心为原点：测试世界里唯一的投影物就是这座岛，跟着相机移动不会带来额外细节。
        """
        center = [TERRAIN_SIZE * 0.5, 8.0, TERRAIN_SIZE * 0.5]  # 阴影覆盖的中心。
        eye = [center[i] + self.sun[i] * 300.0 for i in range(3)]  # 光源放在太阳方向三百米外。
        light_camera = camera.Camera(eye)  # 借相机算视图矩阵。
        light_camera.look_at(center)  # 看向岛中心。
        view = light_camera.view_matrix()  # 光源视图矩阵，三级共用。
        matrices = []  # 每级一个视图投影矩阵。
        for extent in CASCADE_EXTENTS:  # 逐级放大正交视锥。
            projection = orthographic(-extent, extent, -extent, extent, 1.0, 700.0)  # 深度范围要包住整岛，包括山脊与树冠。
            matrices.append(multiply(projection, view))  # 投影乘视图。
        return matrices  # 顺序从近到远。

    def basis(self) -> tuple[list[float], list[float], list[float], float, float]:
        """返回当前相机的前、右、上方向与视场参数，天空相关阶段共用。"""
        return (self.camera.forward(), self.camera.right(), self.camera.up(),
                math.tan(math.radians(self.camera.fov) * 0.5), self.width / self.height)

    def view_projection(self) -> list[float]:
        """返回当前相机带次像素抖动的视图投影矩阵，用来给下一帧做屏幕重投影。"""
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.projection()  # 带抖动的投影矩阵。
        return multiply(projection, view)  # 先视图后投影。

    def projection(self) -> list[float]:
        """返回带次像素抖动的投影矩阵。

        为什么要在投影矩阵里抖动：时间抗锯齿需要每一帧的采样点落在像素内的不同位置，
        历史帧叠起来才能把边缘锯齿抹平。抖动只加在横向与纵向的平移项上，
        深度的解析反解只读第三、四列，因此不受影响。
        """
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 基础投影。
        projection[8] += self.jitter[0] * 2.0 / self.width  # 次像素换算成裁剪空间平移。
        projection[9] += self.jitter[1] * 2.0 / self.height  # 纵向同理。
        return projection  # 可直接上传。

    def jitter_uv(self) -> list[float]:
        """返回本帧抖动在纹理坐标上的偏移，供还原视空间位置时减掉。"""
        return [self.jitter[0] / self.width, self.jitter[1] / self.height]  # 半像素以内的偏移。

    def install_input(self) -> None:
        """把窗口设为可见并安装键盘与鼠标回调。"""
        glfw.show_window(self.window)  # 隐藏窗口不能接收输入。
        glfw.set_input_mode(self.window, glfw.CURSOR, glfw.CURSOR_DISABLED)  # 锁定鼠标，持续转向。
        glfw.set_key_callback(self.window, self.on_key)
        glfw.set_cursor_pos_callback(self.window, self.on_cursor)

    def on_key(self, window, key: int, scancode: int, action: int, mods: int) -> None:
        """记录按键状态；退出键关闭窗口，截图键保存画面。"""
        if action == glfw.PRESS:
            self.keys.add(key)
            if key == glfw.KEY_ESCAPE:
                glfw.set_window_should_close(window, True)
            if key == glfw.KEY_F12:
                self.screenshot_request = True
        elif action == glfw.RELEASE:
            self.keys.discard(key)

    def on_cursor(self, window, x: float, y: float) -> None:
        """把鼠标位移换成相机转向；第一帧只记录位置。"""
        if self.first_mouse:
            self.first_mouse = False
            self.last_mouse = (x, y)
            return
        delta_x = x - self.last_mouse[0]
        delta_y = y - self.last_mouse[1]
        self.last_mouse = (x, y)
        self.camera.turn(delta_x, delta_y)  # 俯仰限制在相机内部处理。

    def render_shadow(self, scene_time: float) -> None:
        """从太阳方向渲染三级地形深度，得到方向光级联阴影贴图。"""
        GL.glEnable(GL.GL_DEPTH_TEST)  # 深度测试决定最终写入哪一个深度。
        GL.glDepthMask(GL.GL_TRUE)  # 允许写深度。
        GL.glEnable(GL.GL_POLYGON_OFFSET_FILL)  # 抬一点深度，减少自遮挡条纹。
        GL.glPolygonOffset(2.0, 4.0)  # 斜率与常量偏置同时生效。
        GL.glUseProgram(self.shadow_program)  # 切到阴影程序。
        set_uniforms(self.shadow_program, {"uTime": scene_time, "uWind": WIND_STRENGTH})  # 树冠摆动要与主画面一致。
        GL.glBindVertexArray(self.terrain_vao)  # 复用地形顶点数据。
        for index, matrix in enumerate(self.light_matrices):  # 每级画一次。
            GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.shadow_fbos[index])  # 只写深度。
            GL.glViewport(0, 0, CASCADE_SIZE, CASCADE_SIZE)  # 使用该级的阴影贴图分辨率。
            GL.glClear(GL.GL_DEPTH_BUFFER_BIT)  # 每帧重建。
            set_uniform(self.shadow_program, "uLightViewProjection", matrix)  # 该级的光源矩阵。
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 全部三角形一次画完。
        GL.glDisable(GL.GL_POLYGON_OFFSET_FILL)  # 后续阶段不需要偏置。

    def render_sky_cube(self, frame: int, scene_time: float) -> None:
        """把天空与云渲染到立方体贴图的六个面，供水面反射与地形环境光。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_fbo)  # 离屏渲染，不影响主画面。
        GL.glViewport(0, 0, SKY_CUBE_SIZE, SKY_CUBE_SIZE)  # 小尺寸足够做反射与环境光。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空在无限远处，不需要深度。
        GL.glUseProgram(self.sky_program)  # 天空程序同时支持屏幕与立方体模式。
        set_uniforms(self.sky_program, {
            "uSunDirection": self.sun, "uCameraPos": self.camera.position, "uTime": scene_time,
            "uCloudCover": self.cloud_cover, "uResolution": [float(SKY_CUBE_SIZE)] * 2,
            "uFrame": float(frame), "uCloudSteps": CUBE_CLOUD_STEPS, "uSkySteps": CUBE_SKY_STEPS,
            "uCloudSun": CLOUD_SUN_STRENGTH,
        })  # 六个面共用的参数只写一次。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 蓝噪声固定在零号单元。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.blue_noise)
        GL.glUniform1i(location(self.sky_program, "uBlueNoise"), 0)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形覆盖每个面。
        for face in range(6):  # 每个面单独挂到帧缓冲再绘制。
            GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0,
                                      GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, self.sky_cube, 0)  # 换到当前面。
            set_uniform(self.sky_program, "uFace", face)  # 告诉着色器当前是哪个面。
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 画满整个面。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)  # 六个面都画完后生成多级纹理。
        GL.glGenerateMipmap(GL.GL_TEXTURE_CUBE_MAP)  # 反射按距离取低分辨率层级，减少闪烁。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 回到默认帧缓冲。

    def render_sky_sample(self, frame: int, scene_time: float) -> None:
        """在半分辨率上算本帧的天空与体积云。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_sample_fbo)  # 只写颜色。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率，像素少四分之三。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空不参与深度。
        GL.glUseProgram(self.sky_program)  # 与立方体贴图共用程序。
        forward, right, up, tan_half, aspect = self.basis()  # 当前相机基向量。
        set_uniforms(self.sky_program, {
            "uForward": forward, "uRight": right, "uUp": up, "uTanHalfFov": tan_half, "uAspect": aspect,
            "uResolution": [float(self.half_width), float(self.half_height)], "uFace": -1,
            "uSunDirection": self.sun, "uCameraPos": self.camera.position, "uTime": scene_time,
            "uCloudCover": self.cloud_cover, "uFrame": float(frame),
            "uCloudSteps": CLOUD_STEPS, "uSkySteps": SKY_STEPS, "uCloudSun": CLOUD_SUN_STRENGTH,
        })  # 全部参数一次写入。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 蓝噪声。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.blue_noise)
        GL.glUniform1i(location(self.sky_program, "uBlueNoise"), 0)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 铺满半分辨率画面。

    def accumulate_sky(self, frame: int) -> None:
        """把本帧天空样本与历史混合，写进另一张历史缓冲。"""
        target = 1 - self.history_index  # 写另一张，读当前这张。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_history_fbo[target])  # 累积目标。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glUseProgram(self.accum_program)  # 累积程序。
        forward, right, up, tan_half, aspect = self.basis()  # 本帧相机基向量。
        if self.prev_basis is None:  # 第一帧没有历史，直接采用本帧样本。
            self.prev_basis = (forward, right, up, tan_half, aspect)
        prev_forward, prev_right, prev_up, prev_tan, prev_aspect = self.prev_basis  # 上一帧基向量。
        blend = 1.0 if frame == 0 else min(1.0, 1.0 / max(1.0, float(frame + 1)) * 4.0)  # 前几帧快速收敛，之后固定权重。
        blend = max(blend, SKY_HISTORY_BLEND)  # 权重不低于设定下限，云移动时及时跟上。
        set_uniforms(self.accum_program, {
            "uResolution": [float(self.half_width), float(self.half_height)],
            "uForward": forward, "uRight": right, "uUp": up, "uTanHalfFov": tan_half, "uAspect": aspect,
            "uPrevForward": prev_forward, "uPrevRight": prev_right, "uPrevUp": prev_up,
            "uPrevTanHalfFov": prev_tan, "uPrevAspect": prev_aspect, "uBlend": blend,
        })  # 本帧与上一帧的相机参数都要传。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 本帧样本。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_sample)
        GL.glUniform1i(location(self.accum_program, "uCurrent"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 历史累积结果。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_history[self.history_index])
        GL.glUniform1i(location(self.accum_program, "uHistory"), 1)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 一次写满。
        self.history_index = target  # 下一帧读这一张。

    def render_scene(self, frame: int, scene_time: float) -> None:
        """把升采样后的天空铺成背景，再画地形。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.scene_fbo)  # 场景目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glClearColor(0.0, 0.0, 0.0, 1.0)  # 背景全部由天空覆盖，清成黑色便于发现漏画。
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)  # 深度清零，地形才能正常遮挡。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 背景不参与深度。
        GL.glDepthMask(GL.GL_FALSE)  # 背景不写深度。
        GL.glUseProgram(self.composite_program)  # 天空合成程序。
        forward, right, up, tan_half, aspect = self.basis()  # 相机基向量。
        set_uniforms(self.composite_program, {
            "uResolution": [float(self.width), float(self.height)],
            "uSkyResolution": [float(self.half_width), float(self.half_height)],
            "uForward": forward, "uRight": right, "uUp": up, "uTanHalfFov": tan_half, "uAspect": aspect,
            "uSunDirection": self.sun, "uSunStrength": SUN_STRENGTH,
        })  # 太阳圆盘与升采样参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 累积后的半分辨率天空。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_history[self.history_index])
        GL.glUniform1i(location(self.composite_program, "uSky"), 0)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 铺满背景。
        # 背景的法线附件也要有定义值，否则后面的遮蔽会读到未初始化的内容。
        GL.glUseProgram(self.terrain_program)  # 切到地形程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.projection()  # 带次像素抖动的投影矩阵，时间抗锯齿靠它采样不同位置。
        view_projection = multiply(projection, view)  # 视图投影，调试与拾取要用。
        set_uniforms(self.terrain_program, {
            "uViewProjection": view_projection, "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uCascadeSplits": list(CASCADE_SPLITS),
            "uCascadeBlend": CASCADE_BLEND, "uWaterLevel": WATER_LEVEL, "uTime": scene_time, "uFrame": float(frame),
            "uCloudCover": self.cloud_cover, "uSunStrength": SUN_STRENGTH, "uSkyStrength": SKY_STRENGTH,
            "uWind": WIND_STRENGTH, "uWetness": WETNESS,
        })  # 光照、级联、风与雾的参数。
        for index in range(CASCADE_COUNT):  # 三级阴影矩阵与贴图逐级绑定。
            set_uniform(self.terrain_program, f"uShadowMatrix{index}", self.light_matrices[index])
            GL.glActiveTexture(GL.GL_TEXTURE0 + index)  # 三级各占一个纹理单元。
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.shadow_depths[index])
            GL.glUniform1i(location(self.terrain_program, f"uShadowMap{index}"), index)
        GL.glActiveTexture(GL.GL_TEXTURE3)  # 天空立方体贴图，用作环境光。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glUniform1i(location(self.terrain_program, "uSkyCube"), 3)
        GL.glEnable(GL.GL_DEPTH_TEST)  # 地形开始写深度。
        GL.glDepthMask(GL.GL_TRUE)  # 允许写深度。
        GL.glBindVertexArray(self.terrain_vao)  # 地形顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 全部三角形一次画完。

    def render_reflection(self, frame: int, scene_time: float) -> None:
        """在半分辨率上追踪水面反射，写入颜色、深度与法线三张附件。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.reflection_fbo)  # 反射目标。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率，追踪成本降到四分之一。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 反射目标是单层水面，不需要深度测试，也不读上一帧残留的深度。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glClearColor(0.0, 0.0, 0.0, 0.0)  # 反射目标清成零，未写到的像素可信度为零，水面会退回天空反射。
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)  # 每帧清空三张附件，避免读到上一帧内容。
        GL.glDisable(GL.GL_BLEND)  # 反射阶段直接覆盖，不混合。
        GL.glUseProgram(self.reflection_program)  # 反射程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.projection()  # 与场景同一份抖动投影，命中点才能对到同一个像素。
        inverse = perspective_inverse(self.camera.fov, self.width / self.height, NEAR, FAR)  # 逆投影。
        set_uniforms(self.reflection_program, {
            "uViewProjection": multiply(projection, view), "uProjectionInverse": inverse,
            "uCameraPos": self.camera.position, "uSunDirection": self.sun, "uTime": scene_time,
            "uForward": self.camera.forward(), "uResolution": [float(self.half_width), float(self.half_height)],
            "uNear": NEAR, "uFar": FAR, "uSunStrength": SUN_STRENGTH,
        })  # 追踪需要的矩阵与场景参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 天空兜底。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glUniform1i(location(self.reflection_program, "uSky"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 场景颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.reflection_program, "uSceneColor"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 场景深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.reflection_program, "uSceneDepth"), 2)
        GL.glBindVertexArray(self.water_vao)  # 海面顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.water_triangles * 3)  # 画一遍海面，只为了取水面像素。

    def denoise_reflection(self, frame: int) -> None:
        """在反射图上做九点邻域滤波，按法线与深度剔除不属于同一水面的邻居。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.denoised_fbo)  # 降噪目标。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glUseProgram(self.denoise_program)  # 降噪程序。
        inverse = perspective_inverse(self.camera.fov, self.width / self.height, NEAR, FAR)  # 逆投影。
        set_uniforms(self.denoise_program, {
            "uResolution": [float(self.half_width), float(self.half_height)],
            "uProjectionInverse": inverse, "uFrame": float(frame),
        })  # 降噪参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 反射颜色与可信度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_color)
        GL.glUniform1i(location(self.denoise_program, "uReflection"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 反射阶段写下的深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_depth)
        GL.glUniform1i(location(self.denoise_program, "uReflectionDepth"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 反射阶段写下的法线。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_normal)
        GL.glUniform1i(location(self.denoise_program, "uReflectionNormal"), 2)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 一次写满。

    def render_global_illumination(self, frame: int) -> None:
        """在半分辨率上算地平线遮蔽与多弹射，并与历史混合。"""
        target = 1 - self.gi_index  # 写另一张，读当前这张。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.gi_fbo[target])  # 遮蔽目标。
        GL.glViewport(0, 0, self.half_width, self.half_height)  # 半分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glUseProgram(self.gi_program)  # 遮蔽程序。
        forward, right, up, tan_half, aspect = self.basis()  # 相机基向量。
        projection = self.projection()  # 带抖动的投影矩阵。
        inverse = perspective_inverse(self.camera.fov, aspect, NEAR, FAR)  # 逆投影。
        blend = 1.0 if frame == 0 else GI_BLEND  # 第一帧没有历史，直接采用本帧。
        set_uniforms(self.gi_program, {
            "uResolution": [float(self.half_width), float(self.half_height)],
            "uFullResolution": [float(self.width), float(self.height)],
            "uProjection": projection, "uProjectionInverse": inverse, "uForward": forward,
            "uAspect": aspect, "uFrame": float(frame), "uBlend": blend, "uJitter": self.jitter_uv(),
        })  # 遮蔽参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 场景深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.gi_program, "uDepth"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 法线与线性深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_normal)
        GL.glUniform1i(location(self.gi_program, "uNormalDepth"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 场景颜色，用来估计底色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.gi_program, "uColor"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)  # 上一帧遮蔽。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.gi_color[self.gi_index])
        GL.glUniform1i(location(self.gi_program, "uHistory"), 3)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 一次写满。
        self.gi_index = target  # 下一帧读这一张。

    def render_taa(self, frame: int) -> None:
        """把本帧画面与历史混合，并乘上全局光遮蔽。"""
        target = 1 - self.taa_index  # 写另一张，读当前这张。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.taa_fbo[target])  # 抗锯齿目标。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glUseProgram(self.taa_program)  # 抗锯齿程序。
        inverse = perspective_inverse(self.camera.fov, self.width / self.height, NEAR, FAR)  # 逆投影。
        forward, right, up, _tan_half, _aspect = self.basis()  # 重投影需要相机基向量。
        blend = 1.0 if frame < 2 else 0.12  # 前两帧快速收敛，之后用较小权重抑制噪点。
        set_uniforms(self.taa_program, {
            "uResolution": [float(self.width), float(self.height)],
            "uAOTexel": [1.0 / self.half_width, 1.0 / self.half_height],
            "uProjectionInverse": inverse, "uBlend": blend, "uFar": FAR,
            "uPreviousViewProjection": self.previous_view_projection,
            "uCameraPos": self.camera.position, "uRight": right, "uUp": up, "uForward": forward,
            "uJitter": self.jitter_uv(),
        })  # 抗锯齿参数、重投影用的相机基向量与次像素抖动。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 本帧颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)
        GL.glUniform1i(location(self.taa_program, "uCurrent"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 上一帧结果。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.taa_color[self.taa_index])
        GL.glUniform1i(location(self.taa_program, "uHistory"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 本帧深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.taa_program, "uDepth"), 2)  # 水面不写深度，直接用场景深度。
        GL.glActiveTexture(GL.GL_TEXTURE3)  # 遮蔽图。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.gi_color[self.gi_index])
        GL.glUniform1i(location(self.taa_program, "uAO"), 3)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 一次写满。
        self.taa_index = target  # 下一帧读这一张。
        self.display_color = self.taa_color[target]  # 后续阶段读本帧结果。

    def render_bloom(self) -> None:
        """三遍泛光：亮度筛选降采样、再降一级、升采样合并。"""
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glUseProgram(self.bloom_program)  # 泛光程序。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        # 第一遍：从抗锯齿结果筛出亮部并降到四分之一。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_fbo)
        GL.glViewport(0, 0, BLOOM_SIZE[0], BLOOM_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(self.width), float(self.height)],
                                          "uMode": 0, "uThreshold": 1.8})  # 亮度阈值只让太阳与亮云发光。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源纹理。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        # 第二遍：再降一级。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_coarse_fbo)
        GL.glViewport(0, 0, BLOOM_COARSE_SIZE[0], BLOOM_COARSE_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uMode": 1})  # 只降采样。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 上一级泛光。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        # 第三遍：粗一级升回来，与细一级相加。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_combine_fbo)
        GL.glViewport(0, 0, BLOOM_SIZE[0], BLOOM_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uMode": 2})  # 升采样合并。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 本级来源。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 更粗一级。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_coarse_color)
        GL.glUniform1i(location(self.bloom_program, "uSmall"), 1)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)

    def render_water(self, frame: int, scene_time: float) -> None:
        """把场景深度与颜色拷进水面目标，再叠加水面，避免读写的画面是同一张。"""
        GL.glBindFramebuffer(GL.GL_READ_FRAMEBUFFER, self.scene_fbo)  # 读取场景深度。
        GL.glBindFramebuffer(GL.GL_DRAW_FRAMEBUFFER, self.water_fbo)  # 写到水面目标。
        GL.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height,
                             GL.GL_DEPTH_BUFFER_BIT, GL.GL_NEAREST)  # 只拷深度，水面靠它被地形遮挡。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.water_fbo)  # 之后都在水面目标上绘制。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 拷贝阶段不参与深度。
        GL.glDepthMask(GL.GL_FALSE)  # 拷贝不写深度。
        GL.glDisable(GL.GL_BLEND)  # 直接覆盖。
        GL.glUseProgram(self.copy_program)  # 拷贝程序。
        set_uniforms(self.copy_program, {"uResolution": [float(self.width), float(self.height)]})  # 目标尺寸。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放场景颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.copy_program, "uSource"), 0)
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 一次写满整个目标。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 水面仍要被地形遮挡。
        GL.glDepthMask(GL.GL_FALSE)  # 水面不写深度，避免遮住后面的水面。
        GL.glEnable(GL.GL_BLEND)  # 水面完全不透明：折射色已经在着色器里取过，再混一次会重复计亮度。
        GL.glBlendFuncSeparate(GL.GL_ONE, GL.GL_ZERO, GL.GL_ONE, GL.GL_ZERO)  # 颜色直接覆盖，透明通道写成水面标记零。
        GL.glUseProgram(self.water_program)  # 切到水面程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 投影矩阵。
        set_uniforms(self.water_program, {
            "uViewProjection": multiply(projection, view), "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uTime": scene_time, "uFrame": float(frame),
            "uWaterLevel": WATER_LEVEL, "uResolution": [float(self.width), float(self.height)],
            "uNear": NEAR, "uFar": FAR, "uSunStrength": SUN_STRENGTH,
        })  # 水面参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放天空。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)  # 兜底反射纹理。
        GL.glUniform1i(location(self.water_program, "uSky"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 一号单元放降噪后的反射。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.denoised_color)
        GL.glUniform1i(location(self.water_program, "uReflection"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 二号单元放场景颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)  # 折射颜色。
        GL.glUniform1i(location(self.water_program, "uSceneColor"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)  # 三号单元放场景深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)  # 水深计算。
        GL.glUniform1i(location(self.water_program, "uSceneDepth"), 3)
        GL.glBindVertexArray(self.water_vao)  # 海面顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.water_triangles * 3)  # 一次画完海面。
        GL.glDisable(GL.GL_BLEND)  # 后续阶段不需要混合。
        GL.glDepthMask(GL.GL_TRUE)  # 恢复深度写入。

    def render_exposure(self) -> None:
        """两级缩小，把整幅画面压成一个像素的平均对数亮度。"""
        GL.glDisable(GL.GL_DEPTH_TEST)  # 二维处理。
        GL.glDepthMask(GL.GL_FALSE)  # 不写深度。
        GL.glUseProgram(self.exposure_program)  # 曝光统计程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 来源纹理。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)
        GL.glUniform1i(location(self.exposure_program, "uSource"), 0)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_tile_fbo)  # 第一级目标。
        GL.glViewport(0, 0, LUMINANCE_SIZE[0], LUMINANCE_SIZE[1])  # 六十四乘三十六。
        set_uniforms(self.exposure_program, {
            "uResolution": [float(LUMINANCE_SIZE[0]), float(LUMINANCE_SIZE[1])], "uMode": 0,
        })  # 每个小图像素取四个样本。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 写满小图。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_final_fbo)  # 第二级目标。
        GL.glViewport(0, 0, 1, 1)  # 只画一个像素。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 换成上一级的小图。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_tile)
        set_uniforms(self.exposure_program, {"uResolution": [1.0, 1.0], "uMode": 1})  # 八乘八共六十四个样本。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 得到一个像素。
        GL.glDepthMask(GL.GL_TRUE)  # 恢复默认状态。

    def render_post(self, frame: int, scene_time: float) -> None:
        """把抗锯齿结果压到屏幕，完成一帧。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 最后输出到窗口。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 后期是二维处理。
        GL.glUseProgram(self.post_program)  # 后期程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放抗锯齿结果。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)  # 线性场景颜色。
        GL.glUniform1i(location(self.post_program, "uColor"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 一号单元放曝光统计。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)  # 一个像素。
        GL.glUniform1i(location(self.post_program, "uExposure"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 二号单元放泛光。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_combine_color)
        GL.glUniform1i(location(self.post_program, "uBloom"), 2)
        set_uniforms(self.post_program, {
            "uResolution": [float(self.width), float(self.height)], "uExposureKey": self.exposure_key,
            "uTonemap": self.tonemap, "uFrame": float(frame), "uTime": scene_time,
            "uAspect": self.width / self.height, "uBloomStrength": 0.35,
        })  # 曝光、曲线、泛光与颗粒参数。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 输出最终画面。

    def draw(self, frame: int, scene_time: float) -> None:
        """按固定顺序绘制一帧：阴影、反射、天空、场景、遮蔽、水面、抗锯齿、泛光、曝光、后期。"""
        pattern = JITTER_SEQUENCE[frame % len(JITTER_SEQUENCE)]  # 八相位循环，覆盖像素内的不同位置。
        self.jitter = (pattern[0] - 0.5, pattern[1] - 0.5)  # 换算成像素偏移，最大半像素。
        self.render_shadow(scene_time)  # 三级方向光阴影贴图。
        self.render_sky_cube(frame, scene_time)  # 反射与环境光用的天空。
        self.render_sky_sample(frame, scene_time)  # 半分辨率天空与云。
        self.accumulate_sky(frame)  # 时间累积。
        self.render_scene(frame, scene_time)  # 背景与地形。
        self.render_global_illumination(frame)  # 半分辨率遮蔽与多弹射。
        self.render_reflection(frame, scene_time)  # 半分辨率反射追踪。
        self.denoise_reflection(frame)  # 反射九点降噪。
        self.render_water(frame, scene_time)  # 水面合成。
        self.render_taa(frame)  # 时间抗锯齿。
        self.render_bloom()  # 两级泛光。
        self.render_exposure()  # 曝光统计。
        self.render_post(frame, scene_time)  # 输出到窗口。
        self.previous_view_projection = self.view_projection()  # 下一帧重投影使用，含本帧抖动。
        forward, right, up, tan_half, aspect = self.basis()  # 记录本帧基向量。
        self.prev_basis = (forward, right, up, tan_half, aspect)  # 下一帧天空累积使用。

    def exposure_value(self) -> float:
        """读回一个像素的平均对数亮度，写进性能记录方便核对曝光。"""
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)  # 绑定曝光统计纹理。
        data = GL.glGetTexImage(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, GL.GL_FLOAT)  # 四通道浮点。
        values = array("f")  # 复用浮点解码。
        values.frombytes(bytes(data))  # 一像素只有十六字节。
        return float(values[0])  # 红色通道是平均对数亮度。

    def screenshot(self, path: Path) -> None:
        """读回默认帧缓冲并写成图片。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 默认帧缓冲。
        GL.glReadBuffer(GL.GL_BACK)  # 读后台缓冲，交换前仍是这一帧。
        pixels = GL.glReadPixels(0, 0, self.width, self.height, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)  # 八位即可保存。
        rgb = bytearray(self.width * self.height * 3)  # 图片只保留三个颜色通道。
        for index in range(self.width * self.height):  # 丢弃透明通道。
            source = index * 4
            target = index * 3
            rgb[target:target + 3] = pixels[source:source + 3]
        path.parent.mkdir(parents=True, exist_ok=True)  # 首次输出时创建目录。
        png.write_rgb(path, self.width, self.height, bytes(rgb))  # 无依赖写入 PNG。

    def close(self) -> None:
        """释放显卡对象与窗口。"""
        for program in (self.sky_program, self.accum_program, self.composite_program, self.terrain_program,
                        self.shadow_program, self.water_program, self.reflection_program, self.denoise_program,
                        self.gi_program, self.taa_program, self.bloom_program, self.exposure_program,
                        self.post_program, self.copy_program):
            GL.glDeleteProgram(program)  # 逐个删除程序。
        GL.glDeleteVertexArrays(3, [self.fullscreen, self.terrain_vao, self.water_vao])  # 顶点数组。
        GL.glDeleteBuffers(2, [self.terrain_vbo, self.water_vbo])  # 顶点缓冲。
        textures = [self.blue_noise, self.scene_color, self.scene_normal, self.scene_depth, self.water_color,
                    self.water_depth, self.sky_cube, self.sky_sample, self.lum_tile, self.lum_final,
                    self.reflection_color, self.reflection_depth, self.reflection_normal, self.denoised_color,
                    self.bloom_color, self.bloom_coarse_color, self.bloom_combine_color]
        textures.extend(self.shadow_depths)  # 三级阴影深度。
        textures.extend(self.sky_history)  # 两张天空历史缓冲。
        textures.extend(self.gi_color)  # 两张遮蔽历史。
        textures.extend(self.taa_color)  # 两张抗锯齿历史。
        GL.glDeleteTextures(textures)  # 纹理一次性删除。
        fbos = [self.scene_fbo, self.water_fbo, self.sky_fbo, self.sky_sample_fbo, self.lum_tile_fbo,
                self.lum_final_fbo, self.reflection_fbo, self.denoised_fbo, self.bloom_fbo, self.bloom_coarse_fbo, self.bloom_combine_fbo]
        fbos.extend(self.shadow_fbos)  # 三级阴影帧缓冲。
        fbos.extend(self.sky_history_fbo)  # 天空历史的帧缓冲。
        fbos.extend(self.gi_fbo)  # 遮蔽帧缓冲。
        fbos.extend(self.taa_fbo)  # 抗锯齿帧缓冲。
        GL.glDeleteFramebuffers(len(fbos), fbos)  # 帧缓冲一次性删除。
        glfw.destroy_window(self.window)  # 关闭窗口。
        glfw.terminate()  # 反初始化 GLFW。

def run(args) -> None:
    """按参数运行截图或交互模式，并写出性能记录。"""
    world = World(args.width, args.height, args.tonemap, args.cloud_cover, args.sun, args.exposure_key)  # 场景只建一次。
    world.camera.position = list(args.camera)  # 固定机位。
    world.camera.look_at(args.target)
    output = Path(args.screenshot)
    perf_path = Path(args.perf)
    try:
        if args.window:  # 交互模式：持续绘制，按退出键结束，按截图键保存画面。
            world.install_input()
            start = time.perf_counter()
            frame = 0
            while not glfw.window_should_close(world.window):
                now = time.perf_counter()
                delta = now - start
                world.camera.move(world.keys, max(0.0, min(0.05, 1.0 / 60.0)), glfw)
                world.draw(frame, delta)
                if world.screenshot_request:
                    world.screenshot(output)
                    world.screenshot_request = False
                    print(f"截图：{output}")
                glfw.swap_buffers(world.window)
                glfw.poll_events()
                frame += 1
            return
        for frame in range(args.warmup):  # 预热，避免首帧着色器编译混进计时。
            world.draw(frame, args.time)
        GL.glFinish()
        times = []  # 每帧耗时，单位毫秒。
        for frame in range(args.frames):  # 计时循环，固定场景与固定时间。
            start = time.perf_counter()
            world.draw(args.warmup + frame, args.time)
            GL.glFinish()  # 等显卡真正完成，否则测到的是提交命令的时间。
            times.append((time.perf_counter() - start) * 1000.0)
        world.screenshot(output)  # 最后一帧保存为图片。
        average = sum(times) / len(times)  # 平均帧时。
        average_log = world.exposure_value()  # 读回曝光统计。
        report = {
            "width": args.width,
            "height": args.height,
            "frames": args.frames,
            "warmup": args.warmup,
            "averageMs": average,
            "medianMs": percentile(times, 0.5),
            "p95Ms": percentile(times, 0.95),
            "minMs": min(times),
            "maxMs": max(times),
            "fps": 1000.0 / average,
            "device": world.device,
            "terrainTriangles": world.terrain_triangles,
            "waterTriangles": world.water_triangles,
            "shadowMapSize": CASCADE_SIZE,
            "shadowCascades": CASCADE_COUNT,
            "cloudSteps": CLOUD_STEPS,
            "cloudResolution": [world.half_width, world.half_height],
            "cloudCubeSteps": CUBE_CLOUD_STEPS,
            "skySteps": SKY_STEPS,
            "historyBlend": SKY_HISTORY_BLEND,
            "averageLogLuminance": average_log,
            "averageLuminance": 2.0 ** average_log,
            "camera": args.camera,
            "target": args.target,
            "sun": args.sun,
            "time": args.time,
            "tonemap": args.tonemap,
        }
        perf_path.parent.mkdir(parents=True, exist_ok=True)  # 记录目录。
        perf_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"截图：{output}")
        print(f"帧时：平均 {average:.2f} 毫秒，中位 {report['medianMs']:.2f}，95 分位 {report['p95Ms']:.2f}，"
              f"最小 {report['minMs']:.2f}，最大 {report['maxMs']:.2f}，约 {report['fps']:.1f} 帧每秒")
        print(f"设备：{world.device['renderer']} / {world.device['version']}")
        print(f"记录：{perf_path}")
    finally:
        world.close()  # 无论成功失败都释放窗口与显存。


def main() -> None:
    """解析参数并启动测试世界。"""
    parser = argparse.ArgumentParser(description="omni-gfx 程序化测试世界")
    parser.add_argument("--width", type=int, default=1280, help="画面宽度")
    parser.add_argument("--height", type=int, default=720, help="画面高度")
    parser.add_argument("--frames", type=int, default=120, help="计时帧数")
    parser.add_argument("--warmup", type=int, default=20, help="预热帧数")
    parser.add_argument("--screenshot", default=str(ROOT / ".dev/omni-gfx/world-complete.png"), help="截图路径")
    parser.add_argument("--perf", default=str(ROOT / ".dev/omni-gfx/perf-complete.json"), help="性能记录路径")
    parser.add_argument("--window", action="store_true", help="打开可交互窗口")
    parser.add_argument("--camera", type=float, nargs=3, default=DEFAULT_CAMERA, help="相机位置")
    parser.add_argument("--target", type=float, nargs=3, default=DEFAULT_TARGET, help="看向的目标")
    parser.add_argument("--sun", type=float, nargs=3, default=DEFAULT_SUN, help="太阳方向")
    parser.add_argument("--time", type=float, default=12.0, help="固定场景时间")
    parser.add_argument("--cloud-cover", type=float, default=0.52, help="云量零到一")
    parser.add_argument("--exposure-key", type=float, default=0.30, help="自动曝光的目标亮度")
    parser.add_argument("--tonemap", type=int, default=0, choices=(0, 1, 2), help="零 ACES，一 AgX，二无压缩")
    args = parser.parse_args()  # 解析失败时参数解析器自行退出。
    run(args)


if __name__ == "__main__":
    main()
