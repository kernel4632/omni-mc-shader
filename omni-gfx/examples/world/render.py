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

TERRAIN_SIZE = 96  # 地形边长，单位为方块。
SHADOW_SIZE = 2048  # 方向光阴影贴图边长，覆盖全岛约每米二十一个纹素。
SKY_CUBE_SIZE = 160  # 反射立方体贴图的边长，越大云与太阳高光越清楚。
WATER_RADIUS = 80000.0  # 水面半径，米；远大于肉眼地平线，天与海的接缝因此不会露出黑带。
WATER_RINGS = 88  # 水面径向分格，越靠外格越宽。
WATER_SEGMENTS = 144  # 水面环向分格，决定岸边弧线的圆滑程度。
NEAR = 0.2  # 投影近平面。
FAR = 120000.0  # 投影远平面要盖住水面远端，否则远处海面会被裁掉。
DEFAULT_SUN = [0.58, 0.42, 0.32]  # 默认太阳方向，侧上方来光，地形有清楚的投影和受光面。
BLUE_NOISE_SIZE = 64  # 蓝噪声贴图边长，必须与生成库里的平铺周期一致。
LUMINANCE_SIZE = (64, 36)  # 曝光统计第一级的尺寸，十六比九的小图。
SKY_STEPS = 6  # 半分辨率天空的大气积分段数。
CLOUD_STEPS = 12  # 半分辨率体积云的沿视线步数，时间累积会把台阶抹平。
CUBE_SKY_STEPS = 4  # 反射立方体贴图的大气段数，反射看不出这么多细节。
CUBE_CLOUD_STEPS = 8  # 反射立方体贴图的云步数。
SKY_HISTORY_BLEND = 0.10  # 时间累积里本帧样本的权重，其余来自历史。
SUN_STRENGTH = 3.2  # 太阳辐照度倍率，地面与水面使用。
CLOUD_SUN_STRENGTH = 1.8  # 云的太阳强度比地面低，逆光云才不会整片死白。
SKY_STRENGTH = 0.75  # 天空环境光的整体倍率。


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
        self.exposure_program = make_program("曝光", "fullscreen.vert", "exposure.frag")
        self.post_program = make_program("后期", "fullscreen.vert", "post.frag")
        heights = terrain.heightmap(TERRAIN_SIZE)  # 固定种子，画面可重复。
        vertices, self.terrain_triangles = terrain.build_mesh(heights, TERRAIN_SIZE)  # 顶面与侧墙。
        self.terrain_vao, self.terrain_vbo = upload_mesh(vertices, [(0, 3, 0), (1, 3, 12), (2, 3, 24), (3, 1, 36)])
        water_vertices, self.water_triangles = terrain.water_disc(WATER_RADIUS, WATER_RINGS, WATER_SEGMENTS)  # 一直铺到地平线之外。
        self.water_vao, self.water_vbo = upload_mesh(water_vertices, [(0, 2, 0)])
        self.blue_noise = make_blue_noise()  # 云步进与雾的抖动来源。
        self.shadow_fbo, self.shadow_depth = make_depth_target(SHADOW_SIZE)  # 方向光阴影。
        self.scene_fbo, self.scene_color, self.scene_depth = gl.color_depth_target(width, height)  # 天空与地形。
        self.water_fbo, self.water_color, self.water_depth = gl.color_depth_target(width, height)  # 水面合成结果。
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
        self.prev_basis = None  # 上一帧相机基向量，重投影用。
        self.camera = camera.Camera([48.0, 17.0, 140.0], fov=55.0)  # 初始相机，站在岛外一百米的水面上方。
        self.camera.look_at([48.0, 16.0, 40.0])  # 略微平视，岛与它的倒影都进入画面。
        self.light_matrix = self.build_light_matrix()  # 方向光矩阵只与太阳有关，建一次即可。
        self.keys: set[int] = set()  # 交互模式按下的键。
        self.first_mouse = True  # 第一帧鼠标位置只记录不转向。
        self.last_mouse = (0.0, 0.0)  # 上一帧鼠标位置。
        self.screenshot_request = False  # 交互模式按 F12 时置位。

    def build_light_matrix(self) -> list[float]:
        """构造方向光的视图投影矩阵，覆盖整座岛与它周围的水面。

        岛只有九十六米见方，一个正交视锥就够，不需要多级级联：
        多级只在大世界里有收益，这里反而会让阴影贴图的分辨率被浪费。
        """
        center = [TERRAIN_SIZE * 0.5, 8.0, TERRAIN_SIZE * 0.5]  # 阴影覆盖的中心。
        eye = [center[i] + self.sun[i] * 260.0 for i in range(3)]  # 光源放在太阳方向两百六十米外。
        light_camera = camera.Camera(eye)  # 借相机算视图矩阵。
        light_camera.look_at(center)  # 看向岛中心。
        view = light_camera.view_matrix()  # 光源视图矩阵。
        # 深度范围只包住岛：范围越窄，深度精度越高，自遮挡条纹越少。
        projection = orthographic(-72.0, 72.0, -72.0, 72.0, 215.0, 300.0)  # 一百四十四米见方、八十五米深的视锥。
        return multiply(projection, view)  # 上传给阴影与地形两段着色器。

    def basis(self) -> tuple[list[float], list[float], list[float], float, float]:
        """返回当前相机的前、右、上方向与视场参数，天空相关阶段共用。"""
        return (self.camera.forward(), self.camera.right(), self.camera.up(),
                math.tan(math.radians(self.camera.fov) * 0.5), self.width / self.height)

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

    def render_shadow(self) -> None:
        """从太阳方向渲染地形深度，得到方向光阴影贴图。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.shadow_fbo)  # 只写深度。
        GL.glViewport(0, 0, SHADOW_SIZE, SHADOW_SIZE)  # 使用阴影贴图分辨率。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 深度测试决定最终写入哪一个深度。
        GL.glDepthMask(GL.GL_TRUE)  # 允许写深度。
        GL.glClear(GL.GL_DEPTH_BUFFER_BIT)  # 每帧重建。
        GL.glEnable(GL.GL_POLYGON_OFFSET_FILL)  # 抬一点深度，减少自遮挡条纹。
        GL.glPolygonOffset(2.0, 4.0)  # 斜率与常量偏置同时生效。
        GL.glUseProgram(self.shadow_program)  # 切到阴影程序。
        set_uniform(self.shadow_program, "uLightViewProjection", self.light_matrix)  # 光源矩阵。
        GL.glBindVertexArray(self.terrain_vao)  # 复用地形顶点数据。
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
        GL.glEnable(GL.GL_DEPTH_TEST)  # 地形开始写深度。
        GL.glDepthMask(GL.GL_TRUE)  # 允许写深度。
        GL.glUseProgram(self.terrain_program)  # 切到地形程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 投影矩阵。
        set_uniforms(self.terrain_program, {
            "uViewProjection": multiply(projection, view), "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uShadowMatrix": self.light_matrix, "uShadowTexel": 1.0 / SHADOW_SIZE,
            "uTime": scene_time, "uFrame": float(frame), "uCloudCover": self.cloud_cover,
            "uSunStrength": SUN_STRENGTH, "uSkyStrength": SKY_STRENGTH,
        })  # 光照、阴影与雾的参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 阴影贴图。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.shadow_depth)
        GL.glUniform1i(location(self.terrain_program, "uShadowMap"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 天空立方体贴图，用作环境光。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glUniform1i(location(self.terrain_program, "uSkyCube"), 1)
        GL.glBindVertexArray(self.terrain_vao)  # 地形顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 全部三角形一次画完。

    def render_water(self, frame: int, scene_time: float) -> None:
        """把场景复制到水面目标，再叠加水面，避免读写的画面是同一张。"""
        GL.glBindFramebuffer(GL.GL_READ_FRAMEBUFFER, self.scene_fbo)  # 读取天空与地形。
        GL.glBindFramebuffer(GL.GL_DRAW_FRAMEBUFFER, self.water_fbo)  # 写到水面目标。
        GL.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height,
                             GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT, GL.GL_NEAREST)  # 颜色与深度一起复制。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.water_fbo)  # 之后都在水面目标上绘制。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 水面仍要被地形遮挡。
        GL.glDepthMask(GL.GL_FALSE)  # 水面不写深度，避免遮住后面的水面。
        GL.glEnable(GL.GL_BLEND)  # 半透明水面与场景混合。
        GL.glBlendFunc(GL.GL_SRC_ALPHA, GL.GL_ONE_MINUS_SRC_ALPHA)  # 标准透明度混合。
        GL.glUseProgram(self.water_program)  # 切到水面程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 投影矩阵。
        forward = self.camera.forward()  # 屏幕空间步进要按视线方向算深度。
        set_uniforms(self.water_program, {
            "uViewProjection": multiply(projection, view), "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uForward": forward, "uTime": scene_time, "uFrame": float(frame),
            "uWaterLevel": terrain.SEA_LEVEL, "uResolution": [float(self.width), float(self.height)],
            "uNear": NEAR, "uFar": FAR, "uSunStrength": SUN_STRENGTH,
        })  # 水面参数。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放天空。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)  # 反射纹理。
        GL.glUniform1i(location(self.water_program, "uSky"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 一号单元放场景颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)  # 反射命中与折射颜色。
        GL.glUniform1i(location(self.water_program, "uSceneColor"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 二号单元放场景深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)  # 反射步进与水深计算。
        GL.glUniform1i(location(self.water_program, "uSceneDepth"), 2)
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
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)
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

    def render_post(self, frame: int) -> None:
        """把水面结果压到屏幕，完成一帧。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 最后输出到窗口。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 后期是二维处理。
        GL.glUseProgram(self.post_program)  # 后期程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放水面结果。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)  # 线性场景颜色。
        GL.glUniform1i(location(self.post_program, "uColor"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 一号单元放曝光统计。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)  # 一个像素。
        GL.glUniform1i(location(self.post_program, "uExposure"), 1)
        set_uniforms(self.post_program, {
            "uResolution": [float(self.width), float(self.height)], "uExposureKey": self.exposure_key,
            "uTonemap": self.tonemap, "uFrame": float(frame),
        })  # 曝光与曲线参数。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 输出最终画面。

    def draw(self, frame: int, scene_time: float) -> None:
        """按固定顺序绘制一帧：阴影、反射、天空、累积、场景、水面、曝光、后期。"""
        self.render_shadow()  # 方向光阴影贴图。
        self.render_sky_cube(frame, scene_time)  # 反射与环境光用的天空。
        self.render_sky_sample(frame, scene_time)  # 半分辨率天空与云。
        self.accumulate_sky(frame)  # 时间累积。
        self.render_scene(frame, scene_time)  # 背景与地形。
        self.render_water(frame, scene_time)  # 水面。
        self.render_exposure()  # 曝光统计。
        self.render_post(frame)  # 输出到窗口。
        forward, right, up, tan_half, aspect = self.basis()  # 记录本帧基向量。
        self.prev_basis = (forward, right, up, tan_half, aspect)  # 下一帧重投影使用。

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
                        self.shadow_program, self.water_program, self.exposure_program, self.post_program):
            GL.glDeleteProgram(program)  # 逐个删除程序。
        GL.glDeleteVertexArrays(3, [self.fullscreen, self.terrain_vao, self.water_vao])  # 顶点数组。
        GL.glDeleteBuffers(2, [self.terrain_vbo, self.water_vbo])  # 顶点缓冲。
        textures = [self.blue_noise, self.shadow_depth, self.scene_color, self.scene_depth, self.water_color,
                    self.water_depth, self.sky_cube, self.sky_sample, self.lum_tile, self.lum_final]
        textures.extend(self.sky_history)  # 两张历史缓冲。
        GL.glDeleteTextures(textures)  # 纹理一次性删除。
        fbos = [self.shadow_fbo, self.scene_fbo, self.water_fbo, self.sky_fbo, self.sky_sample_fbo,
                self.lum_tile_fbo, self.lum_final_fbo]
        fbos.extend(self.sky_history_fbo)  # 历史缓冲的帧缓冲。
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
            "shadowMapSize": SHADOW_SIZE,
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
    parser.add_argument("--screenshot", default=str(ROOT / ".dev/omni-gfx/world-final.png"), help="截图路径")
    parser.add_argument("--perf", default=str(ROOT / ".dev/omni-gfx/perf-final.json"), help="性能记录路径")
    parser.add_argument("--window", action="store_true", help="打开可交互窗口")
    parser.add_argument("--camera", type=float, nargs=3, default=[48.0, 17.0, 140.0], help="相机位置")
    parser.add_argument("--target", type=float, nargs=3, default=[48.0, 16.0, 40.0], help="看向的目标")
    parser.add_argument("--sun", type=float, nargs=3, default=DEFAULT_SUN, help="太阳方向")
    parser.add_argument("--time", type=float, default=12.0, help="固定场景时间")
    parser.add_argument("--cloud-cover", type=float, default=0.40, help="云量零到一")
    parser.add_argument("--exposure-key", type=float, default=0.22, help="自动曝光的目标亮度")
    parser.add_argument("--tonemap", type=int, default=0, choices=(0, 1, 2), help="零 ACES，一 AgX，二无压缩")
    args = parser.parse_args()  # 解析失败时参数解析器自行退出。
    run(args)


if __name__ == "__main__":
    main()
