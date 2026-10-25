"""不启动 Minecraft 的照片级户外测试世界：连续山谷、湖面、树木、体积云与完整后期。

调用位置：`python omni-gfx/build.py demo` 或直接运行本文件。
调用示例：
    python omni-gfx/examples/world/render.py --frames 120 --screenshot .dev/omni-gfx/world-photoreal.png
    python omni-gfx/examples/world/render.py --window
设计原因与取舍：
    老版本是方块岛技术演示，轮廓一眼是体素。这一版把地形、材质与植被全部换掉：
    连续高度场、扫描 PBR 贴图、透明叶片卡片与草丛，目标是普通照片里的山谷草甸。
    测试世界是独立消费者：只读取 `shaders/omni-gfx` 生成的 GLSL，
    场景资源全部来自 `assets/` 的 CC0 贴图与本仓库的程序化卡片，不读 Minecraft 文件。
    体积云与遮蔽保持半分辨率，阴影三级级联，反射半分辨率；这些是保证集成显卡
    仍能超过三十帧的边界，调画面时先动材质与光照，不先加分辨率。
    默认隐藏窗口出图并计时；加 `--window` 才进入可移动相机的交互模式。
"""
from __future__ import annotations

import argparse  # 截图、计时与交互共用一套入口。
import ctypes  # 顶点属性偏移包装。
import json  # 性能记录写成机器可读文件。
import math  # 视场角与矩阵。
import sys  # 调整模块搜索路径。
import time  # 帧时测量。
from array import array  # 读回一像素曝光统计。
from pathlib import Path  # 输出路径。

import glfw  # 窗口与输入。
from OpenGL import GL  # 绘制调用。

HERE = Path(__file__).resolve().parent  # 测试世界目录。
LIB = HERE.parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用上下文与着色器工具。
sys.path.insert(0, str(HERE))  # 导入同目录的地形、植被、材质与相机。

import bluenoise  # 启动时生成一次蓝噪声贴图。
import camera  # 相机与矩阵。
import gl  # OpenGL 小工具。
import materials  # CC0 材质与植物卡片。
import png  # 无依赖图片写入。
import sky  # CC0 全景天空与太阳方向。
import terrain  # 连续高度场与湖面圆盘。
import vegetation  # 树干、树叶、草丛、野花与岩石。

CASCADE_COUNT = 3  # 方向光级联数。
CASCADE_SIZE = 512  # 每级阴影贴图边长；近景仍够用，缓存的软阴影由 PCSS 核补足。
CASCADE_EXTENTS = (60.0, 150.0, 350.0)  # 每级正交视锥半边长，米；近处约八纹素一米。
CASCADE_SPLITS = (60.0, 150.0, 330.0)  # 按视深度选级的分界，米。
CASCADE_BLEND = 12.0  # 级联交界过渡宽度，米。
CASCADE_CENTER = (0.0, 0.0, 120.0)  # 阴影覆盖中心：机位与湖面之间。
SKY_CUBE_SIZE = 128  # 反射与环境光用的天空立方体贴图边长；环境光会再模糊。
WATER_RADIUS = 2900.0  # 水面圆盘半径，米；地形在外圈遮住它。
WATER_RINGS = 128  # 水面径向分格。
WATER_SEGMENTS = 256  # 水面环向分格。
NEAR = 0.2  # 近平面；再小会牺牲远景深度精度。
FAR = 6000.0  # 远平面覆盖地形圆盘与天空。
FOV = 42.0  # 竖直视场角；比广角更接近风景照片的压缩感。
EYE_HEIGHT = 1.68  # 站立视高，米。
DEFAULT_SUN = [-0.50, 0.05, -0.86]  # 仅作说明；默认太阳方向从全景天空的亮斑求得。
DEFAULT_CAMERA_XZ = terrain.CAMERA_START  # 南岸草甸上的固定机位。
DEFAULT_TARGET = [0.0, 14.0, -230.0]  # 看向湖对岸的山脚，地平线略高于画面中心。
BLUE_NOISE_SIZE = 64  # 蓝噪声边长，与生成库的平铺周期一致。
LUMINANCE_SIZE = (64, 36)  # 曝光统计第一级尺寸。
BLOOM_SIZE = (320, 180)  # 泛光最细一级。
BLOOM_COARSE_SIZE = (160, 90)  # 泛光最粗一级。
GI_BLEND = 0.18  # 遮蔽时间累积里本帧权重。
SUN_STRENGTH = 6.0  # 下午太阳的辐照度倍率；斜射光让草坡有明暗。
SKY_STRENGTH = 0.50  # 天空环境光倍率；压低一点提升树冠与草坡的明暗对比。
WIND_STRENGTH = 0.8  # 风摆幅度倍率。
WATER_LEVEL = terrain.WATER_LEVEL  # 湖面高度。
JITTER_SEQUENCE = ((0.5, 0.5), (0.25, 0.75), (0.75, 0.25), (0.125, 0.375), (0.625, 0.875),
                   (0.375, 0.125), (0.875, 0.625), (0.0625, 0.5625))  # 八相位次像素抖动。


def make_program(name: str, vertex: str, fragment: str) -> int:
    """编译测试世界的一个着色器程序；`name` 只用于错误信息。"""
    return gl.build_program(HERE / "shaders" / vertex, HERE / "shaders" / fragment)


def upload_mesh(vertices, attributes: list[tuple[int, int, int]]) -> tuple[int, int]:
    """把交错顶点数组上传到显卡，返回顶点数组与缓冲编号。

    `attributes` 每项是位置、通道数与字节偏移；调用方保证偏移与顶点着色器一致。
    """
    vao = GL.glGenVertexArrays(1)
    vbo = GL.glGenBuffers(1)
    GL.glBindVertexArray(vao)
    GL.glBindBuffer(GL.GL_ARRAY_BUFFER, vbo)
    GL.glBufferData(GL.GL_ARRAY_BUFFER, vertices.tobytes(), GL.GL_STATIC_DRAW)
    stride = sum(count for _, count, _ in attributes) * 4  # 每个顶点的字节数。
    for location_index, count, offset in attributes:
        GL.glEnableVertexAttribArray(location_index)
        GL.glVertexAttribPointer(location_index, count, GL.GL_FLOAT, GL.GL_FALSE, stride, ctypes.c_void_p(offset))
    return vao, vbo


def make_depth_target(size: int) -> tuple[int, int]:
    """创建只有深度附件的帧缓冲，返回帧缓冲与深度纹理。"""
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_DEPTH_COMPONENT24, size, size, 0,
                    GL.GL_DEPTH_COMPONENT, GL.GL_FLOAT, None)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    fbo = GL.glGenFramebuffers(1)
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_ATTACHMENT, GL.GL_TEXTURE_2D, texture, 0)
    GL.glDrawBuffer(GL.GL_NONE)
    GL.glReadBuffer(GL.GL_NONE)
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:
        raise RuntimeError("阴影帧缓冲不完整")
    return fbo, texture


def make_color_target(width: int, height: int) -> tuple[int, int]:
    """创建只有颜色附件的十六位浮点目标，返回帧缓冲与纹理。"""
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA16F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    fbo = GL.glGenFramebuffers(1)
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0, GL.GL_TEXTURE_2D, texture, 0)
    GL.glDrawBuffer(GL.GL_COLOR_ATTACHMENT0)
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:
        raise RuntimeError("浮点颜色帧缓冲不完整")
    return fbo, texture


def make_sky_cube() -> tuple[int, int]:
    """创建天空立方体贴图与只用于渲染它的帧缓冲。"""
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, texture)
    for face in range(6):
        GL.glTexImage2D(GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, 0, GL.GL_RGBA16F, SKY_CUBE_SIZE, SKY_CUBE_SIZE,
                        0, GL.GL_RGBA, GL.GL_FLOAT, None)
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_R, GL.GL_CLAMP_TO_EDGE)
    fbo = GL.glGenFramebuffers(1)
    return texture, fbo


def make_blue_noise() -> int:
    """把启动时算好的蓝噪声上传成单通道纹理，返回纹理编号。"""
    data = bluenoise.texture_data()
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_R8, BLUE_NOISE_SIZE, BLUE_NOISE_SIZE, 0,
                    GL.GL_RED, GL.GL_UNSIGNED_BYTE, data)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_REPEAT)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_REPEAT)
    return texture


def location(program: int, name: str) -> int:
    """取 uniform 位置；不存在时返回负一，OpenGL 会忽略对应写入。"""
    return GL.glGetUniformLocation(program, name)


def set_uniform(program: int, name: str, value) -> None:
    """按 Python 类型选择写入函数，缺少的 uniform 直接跳过。"""
    where = location(program, name)
    if where < 0:
        return
    if isinstance(value, bool):
        GL.glUniform1i(where, 1 if value else 0)
    elif isinstance(value, int):
        GL.glUniform1i(where, value)
    elif isinstance(value, float):
        GL.glUniform1f(where, value)
    elif isinstance(value, (list, tuple)):
        if len(value) == 2:
            GL.glUniform2f(where, *value)
        elif len(value) == 3:
            GL.glUniform3f(where, *value)
        elif len(value) == 4:
            GL.glUniform4f(where, *value)
        elif len(value) == 16:
            GL.glUniformMatrix4fv(where, 1, GL.GL_FALSE, value)
        else:
            raise ValueError(f"不支持的 uniform 长度：{name} {len(value)}")
    else:
        raise TypeError(f"不支持的 uniform 类型：{name} {type(value)}")


def set_uniforms(program: int, values: dict) -> None:
    """一次写入一组 uniform，调用方按名字给值。"""
    for name, value in values.items():
        set_uniform(program, name, value)


def multiply(a: list[float], b: list[float]) -> list[float]:
    """列主序四乘四矩阵相乘，返回 a 乘 b。"""
    result = [0.0] * 16
    for column in range(4):
        for row in range(4):
            result[column * 4 + row] = sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))
    return result


def orthographic(left: float, right: float, bottom: float, top: float, near: float, far: float) -> list[float]:
    """列主序正交投影矩阵，方向光没有透视。"""
    return [
        2.0 / (right - left), 0.0, 0.0, 0.0,
        0.0, 2.0 / (top - bottom), 0.0, 0.0,
        0.0, 0.0, -2.0 / (far - near), 0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,
    ]


def perspective_inverse(fov: float, aspect: float, near: float, far: float) -> list[float]:
    """列主序透视逆投影矩阵，把屏幕深度还原成视空间位置。"""
    f = 1.0 / math.tan(math.radians(fov) * 0.5)
    depth_scale = (near - far) / (2.0 * far * near)
    depth_bias = (far + near) / (2.0 * far * near)
    return [
        aspect / f, 0.0, 0.0, 0.0,
        0.0, 1.0 / f, 0.0, 0.0,
        0.0, 0.0, 0.0, depth_scale,
        0.0, 0.0, -1.0, depth_bias,
    ]


def percentile(values: list[float], fraction: float) -> float:
    """返回排序后指定分位的值。"""
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(len(ordered) * fraction)))
    return ordered[index]


class World:
    """测试世界的显卡资源与绘制顺序。"""

    def __init__(self, width: int, height: int, tonemap: int, sun: list[float],
                 exposure_key: float) -> None:
        self.width = width
        self.height = height
        self.half_width = max(1, width // 2)
        self.half_height = max(1, height // 2)
        self.reflection_width = max(1, width // 4)  # 水面倒影用四分之一分辨率，水波与模糊会掩盖细节。
        self.reflection_height = max(1, height // 4)
        self.tonemap = tonemap
        self.exposure_key = exposure_key
        self.window = gl.init_window(width, height, "omni-gfx 照片级户外场景", visible=False)
        self.sky_texture, hdri_sun = sky.load_sky()  # CC0 全景天空与环境光来源。
        # 默认太阳取天空亮斑，保证直射光、阴影和背景里的太阳位置一致。
        self.sun = camera.normalize(sun if sun is not None else list(hdri_sun))
        self.device = gl.device_info()
        self.fullscreen = gl.fullscreen_vao()
        # 每个阶段一个程序，互不共享 uniform 状态。
        self.sky_program = make_program("天空", "fullscreen.vert", "sky.frag")
        self.terrain_program = make_program("地形", "terrain.vert", "terrain.frag")
        self.props_program = make_program("树干与岩石", "props.vert", "props.frag")
        self.card_program = make_program("植物卡片", "card.vert", "card.frag")
        self.shadow_program = make_program("阴影", "shadow.vert", "shadow.frag")
        self.shadow_card_program = make_program("叶片阴影", "shadow_card.vert", "shadow_card.frag")
        self.water_program = make_program("水面", "water.vert", "water.frag")
        self.gi_program = make_program("全局光", "fullscreen.vert", "gi.frag")
        self.taa_program = make_program("时间抗锯齿", "fullscreen.vert", "taa.frag")
        self.bloom_program = make_program("泛光", "fullscreen.vert", "bloom.frag")
        self.exposure_program = make_program("曝光", "fullscreen.vert", "exposure.frag")
        self.post_program = make_program("后期", "fullscreen.vert", "post.frag")
        self.copy_program = make_program("场景拷贝", "fullscreen.vert", "copy.frag")

        vertices, self.terrain_triangles = terrain.build_terrain(DEFAULT_CAMERA_XZ)
        self.terrain_vao, self.terrain_vbo = upload_mesh(vertices, [(0, 3, 0), (1, 3, 12)])
        plants = vegetation.build()
        self.vegetation = plants
        self.props_vao, self.props_vbo = upload_mesh(
            plants["props"], [(0, 3, 0), (1, 3, 12), (2, 2, 24), (3, 3, 32), (4, 1, 44), (5, 1, 48)])
        card_attributes = [(0, 3, 0), (1, 3, 12), (2, 2, 24), (3, 3, 32), (4, 1, 44)]
        self.leaf_vao, self.leaf_vbo = upload_mesh(plants["leaves"], card_attributes)
        self.grass_vao, self.grass_vbo = upload_mesh(plants["grass"], card_attributes)
        self.flower_vao, self.flower_vbo = upload_mesh(plants["flowers"], card_attributes)
        water_vertices, self.water_triangles = terrain.water_disc(WATER_RADIUS, WATER_RINGS, WATER_SEGMENTS)
        self.water_vao, self.water_vbo = upload_mesh(water_vertices, [(0, 2, 0)])
        self.textures = materials.load()
        self.blue_noise = make_blue_noise()

        self.shadow_fbos = []
        self.shadow_depths = []
        for _ in range(CASCADE_COUNT):
            fbo, depth = make_depth_target(CASCADE_SIZE)
            self.shadow_fbos.append(fbo)
            self.shadow_depths.append(depth)
        self.scene_fbo, scene_colors, self.scene_depth = gl.multi_color_depth_target(width, height, 2)
        self.scene_color, self.scene_normal = scene_colors[0], scene_colors[1]
        self.water_fbo, self.water_color, self.water_depth = gl.color_depth_target(width, height)
        self.reflection_fbo, reflection_colors, _ = gl.multi_color_depth_target(self.reflection_width, self.reflection_height, 3)
        self.reflection_color, self.reflection_depth, self.reflection_normal = reflection_colors
        self.gi_fbo = []
        self.gi_color = []
        for _ in range(2):
            fbo, texture = make_color_target(self.half_width, self.half_height)
            self.gi_fbo.append(fbo)
            self.gi_color.append(texture)
        self.taa_fbo = []
        self.taa_color = []
        for _ in range(2):
            fbo, texture = make_color_target(width, height)
            self.taa_fbo.append(fbo)
            self.taa_color.append(texture)
        self.bloom_fbo, self.bloom_color = make_color_target(BLOOM_SIZE[0], BLOOM_SIZE[1])
        self.bloom_coarse_fbo, self.bloom_coarse_color = make_color_target(BLOOM_COARSE_SIZE[0], BLOOM_COARSE_SIZE[1])
        self.bloom_combine_fbo, self.bloom_combine_color = make_color_target(BLOOM_SIZE[0], BLOOM_SIZE[1])
        self.lum_tile_fbo, self.lum_tile = make_color_target(LUMINANCE_SIZE[0], LUMINANCE_SIZE[1])
        self.lum_final_fbo, self.lum_final = make_color_target(1, 1)
        self.sky_cube, self.sky_fbo = make_sky_cube()
        self.gi_index = 0
        self.taa_index = 0
        self.jitter = (0.0, 0.0)
        ground = terrain.height_at(DEFAULT_CAMERA_XZ[0], DEFAULT_CAMERA_XZ[1])
        self.camera = camera.Camera([DEFAULT_CAMERA_XZ[0], ground + EYE_HEIGHT, DEFAULT_CAMERA_XZ[1]], fov=FOV)
        self.camera.look_at(list(DEFAULT_TARGET))
        self.light_matrices = self.build_light_matrix()
        self.previous_view_projection = self.view_projection()
        self.display_color = self.water_color
        self.keys: set[int] = set()
        self.first_mouse = True
        self.last_mouse = (0.0, 0.0)
        self.screenshot_request = False
        self.bloom_strength = 0.28  # 泛光强度，命令行可覆盖。
        self.profile = False  # 为真时每阶段同步计时，只用于开发性能分析。
        self.render_sky_cube(0, 0.0)  # 天空是静态全景，立方体贴图只生成一次。

    def build_light_matrix(self) -> list[list[float]]:
        """构造三级方向光的视图投影矩阵，每一级覆盖不同大小的区域。"""
        center = list(CASCADE_CENTER)
        eye = [center[i] + self.sun[i] * 700.0 for i in range(3)]
        light_camera = camera.Camera(eye)
        light_camera.look_at(center)
        view = light_camera.view_matrix()
        matrices = []
        for extent in CASCADE_EXTENTS:
            projection = orthographic(-extent, extent, -extent, extent, 1.0, 1500.0)
            matrices.append(multiply(projection, view))
        return matrices

    def basis(self) -> tuple[list[float], list[float], list[float], float, float]:
        """返回当前相机的前、右、上方向与视场参数。"""
        return (self.camera.forward(), self.camera.right(), self.camera.up(),
                math.tan(math.radians(self.camera.fov) * 0.5), self.width / self.height)

    def view_projection(self) -> list[float]:
        """返回当前相机带次像素抖动的视图投影矩阵。"""
        view = self.camera.view_matrix()
        projection = self.projection()
        return multiply(projection, view)

    def projection(self) -> list[float]:
        """返回带次像素抖动的投影矩阵。"""
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)
        projection[8] += self.jitter[0] * 2.0 / self.width
        projection[9] += self.jitter[1] * 2.0 / self.height
        return projection

    def jitter_uv(self) -> list[float]:
        """返回本帧抖动在纹理坐标上的偏移。"""
        return [self.jitter[0] / self.width, self.jitter[1] / self.height]

    def install_input(self) -> None:
        """把窗口设为可见并安装键盘与鼠标回调。"""
        glfw.show_window(self.window)
        glfw.set_input_mode(self.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
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
        self.camera.turn(delta_x, delta_y)

    def bind_scene_common(self, program: int, frame: int, scene_time: float) -> None:
        """写入场景阶段共用的相机、太阳、时间与雾参数。"""
        view = self.camera.view_matrix()
        projection = self.projection()
        set_uniforms(program, {
            "uViewProjection": multiply(projection, view), "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uSunStrength": SUN_STRENGTH, "uSkyStrength": SKY_STRENGTH,
            "uTime": scene_time, "uFrame": float(frame),
            "uWaterLevel": WATER_LEVEL, "uCascadeSplits": list(CASCADE_SPLITS),
            "uCascadeBlend": CASCADE_BLEND, "uWind": WIND_STRENGTH, "uReflectionPass": 0,
        })

    def bind_shadows(self, program: int) -> None:
        """把三级阴影矩阵与深度图绑到纹理单元三到五。"""
        for index in range(CASCADE_COUNT):
            set_uniform(program, f"uShadowMatrix{index}", self.light_matrices[index])
            GL.glActiveTexture(GL.GL_TEXTURE0 + 3 + index)
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.shadow_depths[index])
            GL.glUniform1i(location(program, f"uShadowMap{index}"), 3 + index)

    def bind_material_arrays(self, program: int) -> None:
        """把地面颜色、法线与粗糙度三个纹理数组绑到单元零到二。"""
        for unit, key in enumerate(("albedo", "normal", "rough")):
            GL.glActiveTexture(GL.GL_TEXTURE0 + unit)
            GL.glBindTexture(GL.GL_TEXTURE_2D_ARRAY, self.textures[key])
            GL.glUniform1i(location(program, "uAlbedo" if key == "albedo" else
                                    ("uNormal" if key == "normal" else "uRough")), unit)

    def bind_sky_cube(self, program: int) -> None:
        """把天空立方体贴图绑到单元六，供环境光与湿沙反射。"""
        GL.glActiveTexture(GL.GL_TEXTURE6)
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glUniform1i(location(program, "uSkyCube"), 6)

    def render_shadow(self, scene_time: float) -> None:
        """从太阳方向渲染三级深度，包含地形、树干、岩石与 alpha 裁切的植物卡片。"""
        GL.glEnable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_TRUE)
        GL.glDisable(GL.GL_CULL_FACE)  # 卡片双面，地形绕序也不依赖剔除。
        GL.glEnable(GL.GL_POLYGON_OFFSET_FILL)
        GL.glPolygonOffset(2.0, 4.0)
        for index, matrix in enumerate(self.light_matrices):
            GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.shadow_fbos[index])
            GL.glViewport(0, 0, CASCADE_SIZE, CASCADE_SIZE)
            GL.glClear(GL.GL_DEPTH_BUFFER_BIT)
            # 不透明几何：地形、树干、岩石。
            GL.glUseProgram(self.shadow_program)
            set_uniform(self.shadow_program, "uLightViewProjection", matrix)
            GL.glBindVertexArray(self.terrain_vao)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)
            GL.glBindVertexArray(self.props_vao)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.vegetation["propsTriangles"] * 3)
            # 透明卡片：近景草叶与树冠投影；中景只留树冠，远景不再为草叶付深度绘制。
            if index < 2:
                GL.glUseProgram(self.shadow_card_program)
                set_uniforms(self.shadow_card_program, {"uLightViewProjection": matrix, "uTime": scene_time,
                                                        "uWind": WIND_STRENGTH})
                card_sets = [(self.textures["leaf_card"], self.leaf_vao, self.vegetation["leafTriangles"])]
                for texture, vao, triangles in card_sets:
                    GL.glActiveTexture(GL.GL_TEXTURE0)
                    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
                    GL.glUniform1i(location(self.shadow_card_program, "uCard"), 0)
                    GL.glBindVertexArray(vao)
                    GL.glDrawArrays(GL.GL_TRIANGLES, 0, triangles * 3)
        GL.glDisable(GL.GL_POLYGON_OFFSET_FILL)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)

    def render_sky_cube(self, frame: int, scene_time: float) -> None:
        """把天空与云渲染到立方体贴图的六个面，供反射与环境光。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_fbo)
        GL.glViewport(0, 0, SKY_CUBE_SIZE, SKY_CUBE_SIZE)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glUseProgram(self.sky_program)
        set_uniforms(self.sky_program, {
            "uResolution": [float(SKY_CUBE_SIZE)] * 2,
            "uSkyRotation": sky.SKY_ROTATION, "uSkyBackground": sky.SKY_BACKGROUND,
            "uSkyAmbient": sky.SKY_STRENGTH,
        })
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_texture)
        GL.glUniform1i(location(self.sky_program, "uSkyHdri"), 0)
        GL.glBindVertexArray(self.fullscreen)
        for face in range(6):
            GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0,
                                      GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, self.sky_cube, 0)
            set_uniform(self.sky_program, "uFace", face)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glGenerateMipmap(GL.GL_TEXTURE_CUBE_MAP)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)

    def render_scene(self, frame: int, scene_time: float) -> None:
        """铺天空背景，再画地形、树干与岩石、树叶、草与野花。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.scene_fbo)
        GL.glViewport(0, 0, self.width, self.height)
        GL.glClearColor(0.0, 0.0, 0.0, 1.0)
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_FALSE)
        GL.glUseProgram(self.sky_program)
        forward, right, up, tan_half, aspect = self.basis()
        set_uniforms(self.sky_program, {
            "uResolution": [float(self.width), float(self.height)],
            "uForward": forward, "uRight": right, "uUp": up, "uTanHalfFov": tan_half, "uAspect": aspect,
            "uFace": -1, "uSkyRotation": sky.SKY_ROTATION, "uSkyBackground": sky.SKY_BACKGROUND,
            "uSkyAmbient": sky.SKY_STRENGTH,
        })
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.sky_texture)
        GL.glUniform1i(location(self.sky_program, "uSkyHdri"), 0)
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)

        GL.glEnable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_TRUE)
        # 地形：五种 PBR 材质混合。
        GL.glUseProgram(self.terrain_program)
        self.bind_scene_common(self.terrain_program, frame, scene_time)
        self.bind_material_arrays(self.terrain_program)
        self.bind_shadows(self.terrain_program)
        self.bind_sky_cube(self.terrain_program)
        GL.glBindVertexArray(self.terrain_vao)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)
        # 树干、树枝与岩石。
        GL.glUseProgram(self.props_program)
        self.bind_scene_common(self.props_program, frame, scene_time)
        self.bind_material_arrays(self.props_program)
        self.bind_shadows(self.props_program)
        self.bind_sky_cube(self.props_program)
        GL.glBindVertexArray(self.props_vao)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.vegetation["propsTriangles"] * 3)
        # 植物卡片：先树叶，再草，最后小花；都是 alpha 测试，写深度。
        GL.glUseProgram(self.card_program)
        self.bind_scene_common(self.card_program, frame, scene_time)
        self.bind_shadows(self.card_program)
        self.bind_sky_cube(self.card_program)
        for name, vao, triangles in (
                ("leaf_card", self.leaf_vao, self.vegetation["leafTriangles"]),
                ("grass_card", self.grass_vao, self.vegetation["grassTriangles"]),
                ("flower_card", self.flower_vao, self.vegetation["flowerTriangles"])):
            GL.glActiveTexture(GL.GL_TEXTURE0)
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.textures[name])
            GL.glUniform1i(location(self.card_program, "uCard"), 0)
            tint = (0.50, 0.60, 0.45) if name == "leaf_card" else ((0.78, 0.86, 0.66) if name == "grass_card" else (0.90, 0.90, 0.84))
            set_uniform(self.card_program, "uCardTint", list(tint))
            set_uniform(self.card_program, "uCardShadow", 1 if name == "leaf_card" else 0)
            GL.glBindVertexArray(vao)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, triangles * 3)

    def reflection_view_projection(self) -> list[float]:
        """返回水面平面反射的视图投影矩阵：把相机沿水面翻到另一侧。

        反射相机的位置取相机关于水面的镜像，视线方向的纵向分量取反；
        这样渲染出的半分辨率画面就是水面该看到的景物，不需要屏幕空间步进。
        """
        forward = self.camera.forward()
        mirrored_forward = [forward[0], -forward[1], forward[2]]
        mirrored_right = [self.camera.right()[0], -self.camera.right()[1], self.camera.right()[2]]
        mirrored_up = [self.camera.up()[0], -self.camera.up()[1], self.camera.up()[2]]
        position = [self.camera.position[0], 2.0 * WATER_LEVEL - self.camera.position[1], self.camera.position[2]]
        view = [
            mirrored_right[0], mirrored_up[0], -mirrored_forward[0], 0.0,
            mirrored_right[1], mirrored_up[1], -mirrored_forward[1], 0.0,
            mirrored_right[2], mirrored_up[2], -mirrored_forward[2], 0.0,
            -sum(mirrored_right[i] * position[i] for i in range(3)),
            -sum(mirrored_up[i] * position[i] for i in range(3)),
            sum(mirrored_forward[i] * position[i] for i in range(3)),
            1.0,
        ]
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)
        return multiply(projection, view)

    def render_reflection(self, frame: int, scene_time: float) -> None:
        """用镜像相机把水面以上的场景画进半分辨率目标，代替屏幕空间步进。

        为什么改成平面反射：屏幕空间追踪在细长山脊上会留下阶梯，远处倒影
        像被切成一条条横带。镜像相机只多一次半分辨率场景绘制，倒影轮廓准确，
        水面再用波纹法线做偏移与模糊，观感更接近真实湖面。
        """
        reflection_vp = self.reflection_view_projection()
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.reflection_fbo)
        GL.glViewport(0, 0, self.reflection_width, self.reflection_height)
        GL.glEnable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_TRUE)
        GL.glDisable(GL.GL_CULL_FACE)
        GL.glDisable(GL.GL_BLEND)
        GL.glClearColor(0.0, 0.0, 0.0, 0.0)
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)
        # 地形：水下部分在片元阶段被丢弃，只留下岸线与山体。
        GL.glUseProgram(self.terrain_program)
        self.bind_scene_common(self.terrain_program, frame, scene_time)
        set_uniforms(self.terrain_program, {"uViewProjection": reflection_vp, "uReflectionPass": 1})
        self.bind_material_arrays(self.terrain_program)
        self.bind_shadows(self.terrain_program)
        self.bind_sky_cube(self.terrain_program)
        GL.glBindVertexArray(self.terrain_vao)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)
        # 树干与岩石。
        GL.glUseProgram(self.props_program)
        self.bind_scene_common(self.props_program, frame, scene_time)
        set_uniforms(self.props_program, {"uViewProjection": reflection_vp, "uReflectionPass": 1})
        self.bind_material_arrays(self.props_program)
        self.bind_shadows(self.props_program)
        self.bind_sky_cube(self.props_program)
        GL.glBindVertexArray(self.props_vao)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.vegetation["propsTriangles"] * 3)
        # 树叶、草与野花：倒影里只保留树冠，草叶在四分之一分辨率里看不见却要付全价。
        GL.glUseProgram(self.card_program)
        self.bind_scene_common(self.card_program, frame, scene_time)
        set_uniforms(self.card_program, {"uViewProjection": reflection_vp, "uReflectionPass": 1})
        self.bind_shadows(self.card_program)
        self.bind_sky_cube(self.card_program)
        for name, vao, triangles in (
                ("leaf_card", self.leaf_vao, self.vegetation["leafTriangles"]),
        ):
            GL.glActiveTexture(GL.GL_TEXTURE0)
            GL.glBindTexture(GL.GL_TEXTURE_2D, self.textures[name])
            GL.glUniform1i(location(self.card_program, "uCard"), 0)
            tint = (0.50, 0.60, 0.45) if name == "leaf_card" else ((0.78, 0.86, 0.66) if name == "grass_card" else (0.90, 0.90, 0.84))
            set_uniform(self.card_program, "uCardTint", list(tint))
            set_uniform(self.card_program, "uCardShadow", 1 if name == "leaf_card" else 0)
            GL.glBindVertexArray(vao)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, triangles * 3)

    def render_global_illumination(self, frame: int) -> None:
        """在半分辨率上算地平线遮蔽与多弹射，并与历史混合。"""
        target = 1 - self.gi_index
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.gi_fbo[target])
        GL.glViewport(0, 0, self.half_width, self.half_height)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glUseProgram(self.gi_program)
        forward, right, up, tan_half, aspect = self.basis()
        projection = self.projection()
        inverse = perspective_inverse(self.camera.fov, aspect, NEAR, FAR)
        blend = 1.0 if frame == 0 else GI_BLEND
        set_uniforms(self.gi_program, {
            "uResolution": [float(self.half_width), float(self.half_height)],
            "uFullResolution": [float(self.width), float(self.height)],
            "uProjection": projection, "uProjectionInverse": inverse, "uForward": forward,
            "uAspect": aspect, "uFrame": float(frame), "uBlend": blend, "uJitter": self.jitter_uv(),
        })
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.gi_program, "uDepth"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_normal)
        GL.glUniform1i(location(self.gi_program, "uNormalDepth"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.gi_program, "uColor"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.gi_color[self.gi_index])
        GL.glUniform1i(location(self.gi_program, "uHistory"), 3)
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        self.gi_index = target

    def render_taa(self, frame: int) -> None:
        """把本帧画面与历史混合，并乘上半分辨率环境光遮蔽。"""
        target = 1 - self.taa_index
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.taa_fbo[target])
        GL.glViewport(0, 0, self.width, self.height)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glUseProgram(self.taa_program)
        inverse = perspective_inverse(self.camera.fov, self.width / self.height, NEAR, FAR)
        forward, right, up, _tan_half, _aspect = self.basis()
        blend = 1.0 if frame < 2 else 0.11
        set_uniforms(self.taa_program, {
            "uResolution": [float(self.width), float(self.height)],
            "uAOTexel": [1.0 / self.half_width, 1.0 / self.half_height],
            "uProjectionInverse": inverse, "uBlend": blend, "uFar": FAR,
            "uPreviousViewProjection": self.previous_view_projection,
            "uCameraPos": self.camera.position, "uRight": right, "uUp": up, "uForward": forward,
            "uJitter": self.jitter_uv(),
        })
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)
        GL.glUniform1i(location(self.taa_program, "uCurrent"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.taa_color[self.taa_index])
        GL.glUniform1i(location(self.taa_program, "uHistory"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.taa_program, "uDepth"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.gi_color[self.gi_index])
        GL.glUniform1i(location(self.taa_program, "uAO"), 3)
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        self.taa_index = target
        self.display_color = self.taa_color[target]

    def render_bloom(self) -> None:
        """三遍泛光：亮度筛选降采样、再降一级、升采样合并。"""
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glUseProgram(self.bloom_program)
        GL.glBindVertexArray(self.fullscreen)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_fbo)
        GL.glViewport(0, 0, BLOOM_SIZE[0], BLOOM_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(self.width), float(self.height)],
                                          "uMode": 0, "uThreshold": 2.0})
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_coarse_fbo)
        GL.glViewport(0, 0, BLOOM_COARSE_SIZE[0], BLOOM_COARSE_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uMode": 1})
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.bloom_combine_fbo)
        GL.glViewport(0, 0, BLOOM_SIZE[0], BLOOM_SIZE[1])
        set_uniforms(self.bloom_program, {"uResolution": [float(BLOOM_SIZE[0]), float(BLOOM_SIZE[1])],
                                          "uSourceResolution": [float(BLOOM_COARSE_SIZE[0]), float(BLOOM_COARSE_SIZE[1])],
                                          "uMode": 2})
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_color)
        GL.glUniform1i(location(self.bloom_program, "uSource"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_coarse_color)
        GL.glUniform1i(location(self.bloom_program, "uSmall"), 1)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)

    def render_water(self, frame: int, scene_time: float) -> None:
        """把场景颜色与深度拷进水面目标，再叠加湖面。"""
        GL.glBindFramebuffer(GL.GL_READ_FRAMEBUFFER, self.scene_fbo)
        GL.glBindFramebuffer(GL.GL_DRAW_FRAMEBUFFER, self.water_fbo)
        GL.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height,
                             GL.GL_DEPTH_BUFFER_BIT, GL.GL_NEAREST)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.water_fbo)
        GL.glViewport(0, 0, self.width, self.height)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_FALSE)
        GL.glDisable(GL.GL_BLEND)
        GL.glUseProgram(self.copy_program)
        set_uniform(self.copy_program, "uResolution", [float(self.width), float(self.height)])
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.copy_program, "uSource"), 0)
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glEnable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_FALSE)
        GL.glEnable(GL.GL_BLEND)
        GL.glBlendFuncSeparate(GL.GL_ONE, GL.GL_ZERO, GL.GL_ONE, GL.GL_ZERO)
        GL.glUseProgram(self.water_program)
        view = self.camera.view_matrix()
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)
        set_uniforms(self.water_program, {
            "uViewProjection": multiply(projection, view), "uCameraPos": self.camera.position,
            "uSunDirection": self.sun, "uTime": scene_time, "uFrame": float(frame),
            "uWaterLevel": WATER_LEVEL, "uResolution": [float(self.width), float(self.height)],
            "uNear": NEAR, "uFar": FAR, "uSunStrength": SUN_STRENGTH,
            "uReflectionTexel": [1.0 / self.reflection_width, 1.0 / self.reflection_height],
        })
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)
        GL.glUniform1i(location(self.water_program, "uSky"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.reflection_color)
        GL.glUniform1i(location(self.water_program, "uReflection"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)
        GL.glUniform1i(location(self.water_program, "uSceneColor"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.water_program, "uSceneDepth"), 3)
        GL.glBindVertexArray(self.water_vao)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.water_triangles * 3)
        GL.glDisable(GL.GL_BLEND)
        GL.glDepthMask(GL.GL_TRUE)

    def render_exposure(self) -> None:
        """两级缩小，把整幅画面压成一个像素的平均对数亮度。"""
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glDepthMask(GL.GL_FALSE)
        GL.glUseProgram(self.exposure_program)
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)
        GL.glUniform1i(location(self.exposure_program, "uSource"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.exposure_program, "uDepth"), 1)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_tile_fbo)
        GL.glViewport(0, 0, LUMINANCE_SIZE[0], LUMINANCE_SIZE[1])
        set_uniforms(self.exposure_program, {"uResolution": [float(LUMINANCE_SIZE[0]), float(LUMINANCE_SIZE[1])],
                                             "uMode": 0})
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.lum_final_fbo)
        GL.glViewport(0, 0, 1, 1)
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_tile)
        set_uniforms(self.exposure_program, {"uResolution": [1.0, 1.0], "uMode": 1})
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
        GL.glDepthMask(GL.GL_TRUE)

    def render_post(self, frame: int, scene_time: float) -> None:
        """把抗锯齿结果压到屏幕，完成一帧。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)
        GL.glViewport(0, 0, self.width, self.height)
        GL.glDisable(GL.GL_DEPTH_TEST)
        GL.glUseProgram(self.post_program)
        GL.glActiveTexture(GL.GL_TEXTURE0)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.display_color)
        GL.glUniform1i(location(self.post_program, "uColor"), 0)
        GL.glActiveTexture(GL.GL_TEXTURE1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)
        GL.glUniform1i(location(self.post_program, "uExposure"), 1)
        GL.glActiveTexture(GL.GL_TEXTURE2)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.bloom_combine_color)
        GL.glUniform1i(location(self.post_program, "uBloom"), 2)
        GL.glActiveTexture(GL.GL_TEXTURE3)
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)
        GL.glUniform1i(location(self.post_program, "uDepth"), 3)
        set_uniforms(self.post_program, {
            "uResolution": [float(self.width), float(self.height)], "uExposureKey": self.exposure_key,
            "uTonemap": self.tonemap, "uFrame": float(frame), "uTime": scene_time,
            "uAspect": self.width / self.height, "uBloomStrength": self.bloom_strength,
            "uFocusDistance": 7.0, "uAperture": 0.18, "uNear": NEAR, "uFar": FAR,
        })
        GL.glBindVertexArray(self.fullscreen)
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)

    def draw(self, frame: int, scene_time: float) -> None:
        """按固定顺序绘制一帧，并在需要时输出每阶段耗时。"""
        pattern = JITTER_SEQUENCE[frame % len(JITTER_SEQUENCE)]
        self.jitter = (pattern[0] - 0.5, pattern[1] - 0.5)
        stages = (
            ("shadow", lambda: self.render_shadow(scene_time) if frame % 4 == 0 else None),
            ("scene", lambda: self.render_scene(frame, scene_time)),
            ("gi", lambda: self.render_global_illumination(frame)),
            ("reflection", lambda: self.render_reflection(frame, scene_time) if frame % 6 == 0 else None),
            ("water", lambda: self.render_water(frame, scene_time)),
            ("taa", lambda: self.render_taa(frame)),
            ("bloom", lambda: self.render_bloom()),
            ("exposure", lambda: self.render_exposure()),
            ("post", lambda: self.render_post(frame, scene_time)),
        )
        for name, stage in stages:
            start = time.perf_counter()
            stage()
            if getattr(self, "profile", False):
                GL.glFinish()
                print(f"{name:>10}: {(time.perf_counter() - start) * 1000.0:6.2f} ms")
        self.previous_view_projection = self.view_projection()
        forward, right, up, tan_half, aspect = self.basis()

    def exposure_value(self) -> float:
        """读回一个像素的平均对数亮度。"""
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.lum_final)
        data = GL.glGetTexImage(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, GL.GL_FLOAT)
        values = array("f")
        values.frombytes(bytes(data))
        return float(values[0])

    def screenshot(self, path: Path) -> None:
        """读回默认帧缓冲并写成图片。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)
        GL.glReadBuffer(GL.GL_BACK)
        pixels = GL.glReadPixels(0, 0, self.width, self.height, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)
        rgb = bytearray(self.width * self.height * 3)
        for index in range(self.width * self.height):
            source = index * 4
            target = index * 3
            rgb[target:target + 3] = pixels[source:source + 3]
        path.parent.mkdir(parents=True, exist_ok=True)
        png.write_rgb(path, self.width, self.height, bytes(rgb))

    def close(self) -> None:
        """释放显卡对象与窗口。"""
        for program in (self.sky_program, self.terrain_program,
                        self.props_program, self.card_program, self.shadow_program, self.shadow_card_program,
                        self.water_program, self.gi_program,
                        self.taa_program, self.bloom_program, self.exposure_program, self.post_program,
                        self.copy_program):
            GL.glDeleteProgram(program)
        GL.glDeleteVertexArrays(6, [self.fullscreen, self.terrain_vao, self.props_vao, self.leaf_vao,
                                    self.grass_vao, self.flower_vao])
        GL.glDeleteVertexArrays(1, [self.water_vao])
        GL.glDeleteBuffers(1, [self.terrain_vbo])
        GL.glDeleteBuffers(1, [self.props_vbo])
        GL.glDeleteBuffers(1, [self.leaf_vbo])
        GL.glDeleteBuffers(1, [self.grass_vbo])
        GL.glDeleteBuffers(1, [self.flower_vbo])
        GL.glDeleteBuffers(1, [self.water_vbo])
        textures = [self.blue_noise, self.scene_color, self.scene_normal, self.scene_depth, self.water_color,
                    self.water_depth, self.sky_cube, self.lum_tile, self.lum_final,
                    self.reflection_color, self.reflection_depth, self.reflection_normal,
                    self.bloom_color, self.bloom_coarse_color, self.bloom_combine_color, self.sky_texture]
        textures.extend(self.shadow_depths)
        textures.extend(self.gi_color)
        textures.extend(self.taa_color)
        textures.extend(self.textures.values())
        GL.glDeleteTextures(textures)
        fbos = [self.scene_fbo, self.water_fbo, self.sky_fbo, self.lum_tile_fbo,
                self.lum_final_fbo, self.reflection_fbo, self.bloom_fbo,
                self.bloom_coarse_fbo, self.bloom_combine_fbo]
        fbos.extend(self.shadow_fbos)
        fbos.extend(self.gi_fbo)
        fbos.extend(self.taa_fbo)
        GL.glDeleteFramebuffers(len(fbos), fbos)
        glfw.destroy_window(self.window)
        glfw.terminate()


def run(args) -> None:
    """按参数运行截图或交互模式，并写出性能记录。"""
    world = World(args.width, args.height, args.tonemap, args.sun, args.exposure_key)
    world.bloom_strength = args.bloom
    world.profile = args.profile
    if args.camera is not None:  # 允许命令行覆盖机位；默认站在草甸上。
        world.camera.position = list(args.camera)
    if args.target is not None:
        world.camera.look_at(list(args.target))
    output = Path(args.screenshot)
    perf_path = Path(args.perf)
    try:
        if args.window:
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
        for frame in range(args.warmup):
            world.draw(frame, args.time)
        GL.glFinish()
        times = []
        for frame in range(args.frames):
            start = time.perf_counter()
            world.draw(args.warmup + frame, args.time)
            GL.glFinish()
            times.append((time.perf_counter() - start) * 1000.0)
        world.screenshot(output)
        average = sum(times) / len(times)
        average_log = world.exposure_value()
        report = {
            "width": args.width, "height": args.height, "frames": args.frames, "warmup": args.warmup,
            "averageMs": average, "medianMs": percentile(times, 0.5), "p95Ms": percentile(times, 0.95),
            "minMs": min(times), "maxMs": max(times), "fps": 1000.0 / average,
            "device": world.device,
            "terrainTriangles": world.terrain_triangles,
            "propsTriangles": world.vegetation["propsTriangles"],
            "leafTriangles": world.vegetation["leafTriangles"],
            "grassTriangles": world.vegetation["grassTriangles"],
            "flowerTriangles": world.vegetation["flowerTriangles"],
            "waterTriangles": world.water_triangles,
            "trees": world.vegetation["trees"],
            "shadowMapSize": CASCADE_SIZE, "shadowCascades": CASCADE_COUNT,
            "averageLogLuminance": average_log, "averageLuminance": 2.0 ** average_log,
            "camera": world.camera.position, "target": args.target or DEFAULT_TARGET,
            "sun": world.sun, "time": args.time, "tonemap": args.tonemap,
        }
        perf_path.parent.mkdir(parents=True, exist_ok=True)
        perf_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"截图：{output}")
        print(f"帧时：平均 {average:.2f} 毫秒，中位 {report['medianMs']:.2f}，95 分位 {report['p95Ms']:.2f}，"
              f"最小 {report['minMs']:.2f}，最大 {report['maxMs']:.2f}，约 {report['fps']:.1f} 帧每秒")
        print(f"三角形：地形 {report['terrainTriangles']}，树干与岩石 {report['propsTriangles']}，"
              f"树叶 {report['leafTriangles']}，草 {report['grassTriangles']}，花 {report['flowerTriangles']}")
        print(f"设备：{world.device['renderer']} / {world.device['version']}")
        print(f"记录：{perf_path}")
    finally:
        world.close()


def main() -> None:
    """解析参数并启动测试世界。"""
    parser = argparse.ArgumentParser(description="omni-gfx 照片级户外测试世界")
    parser.add_argument("--width", type=int, default=1280, help="画面宽度")
    parser.add_argument("--height", type=int, default=720, help="画面高度")
    parser.add_argument("--frames", type=int, default=120, help="计时帧数")
    parser.add_argument("--warmup", type=int, default=24, help="预热帧数")
    parser.add_argument("--screenshot", default=str(ROOT / ".dev/omni-gfx/world-photoreal.png"), help="截图路径")
    parser.add_argument("--perf", default=str(ROOT / ".dev/omni-gfx/perf-photoreal.json"), help="性能记录路径")
    parser.add_argument("--window", action="store_true", help="打开可交互窗口")
    parser.add_argument("--camera", type=float, nargs=3, default=None, help="相机位置")
    parser.add_argument("--target", type=float, nargs=3, default=None, help="看向的目标")
    parser.add_argument("--sun", type=float, nargs=3, default=None, help="太阳方向；默认从 HDR 天空自动求")
    parser.add_argument("--time", type=float, default=12.0, help="固定场景时间")
    parser.add_argument("--exposure-key", type=float, default=0.32, help="自动曝光的目标亮度")
    parser.add_argument("--tonemap", type=int, default=0, choices=(0, 1, 2), help="零 ACES，一 AgX，二无压缩")
    parser.add_argument("--bloom", type=float, default=0.28, help="泛光强度")
    parser.add_argument("--profile", action="store_true", help="输出每阶段耗时，仅用于性能分析")
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
