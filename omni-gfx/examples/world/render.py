"""不启动 Minecraft 的程序化测试世界：体素地形、天空、云、水面与后期。

调用位置：`python omni-gfx/build.py demo` 或直接运行本文件。
调用示例：
    python omni-gfx/examples/world/render.py --frames 120 --screenshot .dev/omni-gfx/world.png
    python omni-gfx/examples/world/render.py --window
设计原因与取舍：
    测试世界是独立消费者：它只读取 `shaders/omni-gfx` 里生成的 GLSL，
    因此能证明产物真的能编译、能出图，而不是只在生成器里看起来正确。
    场景全部程序化生成，不依赖 Minecraft 存档、材质包或网络资源。
    默认隐藏窗口出图并计时；加窗口参数才进入可移动相机的交互模式。
"""
from __future__ import annotations

import argparse  # 命令行参数，截图与交互共用一套入口。
import ctypes  # 顶点属性偏移必须用空指针包装，否则会被当成 Python 对象地址。
import json  # 性能记录写成机器可读文件。
import math  # 视场角与矩阵计算。
import sys  # 调整工具目录的搜索路径。
import time  # 帧时测量。
from pathlib import Path  # 输出路径。

import glfw  # 窗口与输入。
from OpenGL import GL  # 绘制调用。

HERE = Path(__file__).resolve().parent  # 测试世界目录。
LIB = HERE.parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用上下文与着色器工具。
sys.path.insert(0, str(HERE))  # 导入同目录的地形、相机与图片模块。

import camera  # 相机与矩阵。
import gl  # OpenGL 小工具。
import png  # 无依赖图片写入。
import terrain  # 高度图与网格。

TERRAIN_SIZE = 96  # 地形边长，单位为方块。
SKY_CUBE_SIZE = 80  # 反射立方体贴图的边长，越小越省时间。
NEAR = 0.2  # 投影近平面。
FAR = 2600.0  # 投影远平面。
DEFAULT_SUN = [0.30, 0.20, -0.93]  # 默认太阳方向，斜射能看清地形阴影。


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
    for location, count, offset in attributes:  # 逐属性启用并指定格式。
        GL.glEnableVertexAttribArray(location)  # 打开这个通道。
        # 偏移必须包成空指针，否则会被解释成 Python 对象地址，顶点会全部飞走。
        GL.glVertexAttribPointer(location, count, GL.GL_FLOAT, GL.GL_FALSE, stride, ctypes.c_void_p(offset))
    return vao, vbo  # 调用方负责释放。


def upload_height(heights: list[float]) -> int:
    """把高度图上传成单通道浮点纹理，供地形阴影步进读取。"""
    texture = GL.glGenTextures(1)  # 单通道纹理只存高度。
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 后续设置作用于这张纹理。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_R32F, TERRAIN_SIZE, TERRAIN_SIZE, 0, GL.GL_RED, GL.GL_FLOAT,
                    terrain.height_texture(heights))  # 三十二位浮点，阴影比较不需要解码。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 缩小用线性，坡面高度连续。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也用线性。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 横向不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 纵向不重复。
    return texture  # 调用方负责删除。


def make_sky_cube() -> tuple[int, int]:
    """创建天空立方体贴图与只用于渲染它的帧缓冲。"""
    texture = GL.glGenTextures(1)  # 反射用的立方体贴图。
    GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, texture)  # 绑定后逐个面分配。
    # 六个面使用同一尺寸与格式，采样时不用再判断面类型。
    for face in range(6):  # 逐个分配。
        GL.glTexImage2D(GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, 0, GL.GL_RGBA16F, SKY_CUBE_SIZE, SKY_CUBE_SIZE,
                        0, GL.GL_RGBA, GL.GL_FLOAT, None)  # 十六位浮点，保留太阳高光。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)  # 反射采样要平滑。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)  # 放大也平滑。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_CUBE_MAP, GL.GL_TEXTURE_WRAP_R, GL.GL_CLAMP_TO_EDGE)  # 接缝处不重复。
    fbo = GL.glGenFramebuffers(1)  # 渲染每个面时临时挂载。
    return texture, fbo  # 调用方负责删除。


def location(program: int, name: str) -> int:
    """取 uniform 位置；不存在时返回负一，OpenGL 会忽略对应写入。"""
    return GL.glGetUniformLocation(program, name)


class World:
    """测试世界的全部显卡资源与绘制顺序。"""

    def __init__(self, width: int, height: int, tonemap: int, cloud_cover: float, sun: list[float]) -> None:
        """创建窗口、程序、网格与离屏目标，之后可反复绘制。"""
        self.width = width  # 画面宽度。
        self.height = height  # 画面高度。
        self.tonemap = tonemap  # 后期曲线编号。
        self.cloud_cover = cloud_cover  # 云量。
        self.sun = camera.normalize(sun)  # 太阳方向。
        self.window = gl.init_window(width, height, "omni-gfx 测试世界", visible=False)  # 先隐藏，交互模式再显示。
        self.device = gl.device_info()  # 设备信息随性能记录保存。
        self.fullscreen = gl.fullscreen_vao()  # 全屏三角形共用的空顶点数组。
        # 四个程序分别负责天空、地形、水面与后期，互不共享 uniform 状态。
        self.sky_program = make_program("天空", "fullscreen.vert", "sky.frag")
        self.terrain_program = make_program("地形", "terrain.vert", "terrain.frag")
        self.water_program = make_program("水面", "water.vert", "water.frag")
        self.post_program = make_program("后期", "fullscreen.vert", "post.frag")
        heights = terrain.heightmap(TERRAIN_SIZE)  # 固定种子，画面可重复。
        vertices, self.terrain_triangles = terrain.build_mesh(heights, TERRAIN_SIZE)  # 顶面与侧墙。
        self.terrain_vao, self.terrain_vbo = upload_mesh(vertices, [(0, 3, 0), (1, 3, 12), (2, 3, 24), (3, 1, 36)])
        water_vertices, self.water_triangles = terrain.water_plane(2400.0, 128)  # 远处海面。
        self.water_vao, self.water_vbo = upload_mesh(water_vertices, [(0, 2, 0)])
        self.height_texture = upload_height(heights)  # 阴影步进使用。
        self.scene_fbo, self.scene_color, self.scene_depth = gl.color_depth_target(width, height)  # 天空与地形。
        self.water_fbo, self.water_color, self.water_depth = gl.color_depth_target(width, height)  # 水面合成结果。
        self.sky_cube, self.sky_fbo = make_sky_cube()  # 反射用天空。
        self.camera = camera.Camera([48.0, 30.0, 100.0], fov=55.0)  # 初始相机。
        self.camera.look_at([48.0, 16.0, 40.0])  # 看向岛屿中心。
        self.keys: set[int] = set()  # 交互模式按下的键。
        self.first_mouse = True  # 第一帧鼠标位置只记录不转向。
        self.last_mouse = (0.0, 0.0)  # 上一帧鼠标位置。
        self.screenshot_request = False  # 交互模式按 F12 时置位。

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

    def render_sky_cube(self, frame: int, scene_time: float) -> None:
        """把天空与云渲染到立方体贴图的六个面，供水面反射。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.sky_fbo)  # 离屏渲染，不影响主画面。
        GL.glViewport(0, 0, SKY_CUBE_SIZE, SKY_CUBE_SIZE)  # 小尺寸足够做反射。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空在无限远处，不需要深度。
        GL.glUseProgram(self.sky_program)  # 天空程序同时支持屏幕与立方体模式。
        # 太阳、时间、云量与相机位置在六个面之间共用。
        GL.glUniform3f(location(self.sky_program, "uSunDirection"), *self.sun)
        GL.glUniform3f(location(self.sky_program, "uCameraPos"), *self.camera.position)
        GL.glUniform1f(location(self.sky_program, "uTime"), scene_time)
        GL.glUniform1f(location(self.sky_program, "uCloudCover"), self.cloud_cover)
        GL.glUniform2f(location(self.sky_program, "uResolution"), SKY_CUBE_SIZE, SKY_CUBE_SIZE)
        GL.glUniform1f(location(self.sky_program, "uFrame"), float(frame))
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形覆盖每个面。
        for face in range(6):  # 每个面单独挂到帧缓冲再绘制。
            GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0,
                                      GL.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, self.sky_cube, 0)  # 换到当前面。
            GL.glUniform1i(location(self.sky_program, "uFace"), face)  # 告诉着色器当前是哪个面。
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 画满整个面。
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 回到默认帧缓冲。

    def render_scene(self, frame: int, scene_time: float) -> None:
        """渲染天空背景与地形到场景目标。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, self.scene_fbo)  # 场景先画到浮点目标。
        GL.glViewport(0, 0, self.width, self.height)  # 使用完整分辨率。
        GL.glClearColor(0.45, 0.62, 0.82, 1.0)  # 天空没覆盖到的像素也有底色。
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)  # 深度清零，地形才能正常遮挡。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 天空铺满背景，不参与深度。
        GL.glUseProgram(self.sky_program)  # 主画面天空使用屏幕光线。
        forward = self.camera.forward()  # 三个基向量构造每像素光线。
        right = self.camera.right()
        up = self.camera.up()
        GL.glUniform3f(location(self.sky_program, "uForward"), *forward)  # 前方向。
        GL.glUniform3f(location(self.sky_program, "uRight"), *right)  # 右方向。
        GL.glUniform3f(location(self.sky_program, "uUp"), *up)  # 上方向。
        GL.glUniform1f(location(self.sky_program, "uTanHalfFov"), math.tan(math.radians(self.camera.fov) * 0.5))  # 视场角一半。
        GL.glUniform1f(location(self.sky_program, "uAspect"), self.width / self.height)  # 宽高比。
        GL.glUniform3f(location(self.sky_program, "uSunDirection"), *self.sun)  # 太阳方向。
        GL.glUniform3f(location(self.sky_program, "uCameraPos"), *self.camera.position)  # 云层视差。
        GL.glUniform1f(location(self.sky_program, "uTime"), scene_time)  # 云随风移动。
        GL.glUniform1f(location(self.sky_program, "uCloudCover"), self.cloud_cover)  # 云量。
        GL.glUniform2f(location(self.sky_program, "uResolution"), self.width, self.height)  # 屏幕尺寸。
        GL.glUniform1f(location(self.sky_program, "uFrame"), float(frame))  # 抖动相位。
        GL.glUniform1i(location(self.sky_program, "uFace"), -1)  # 负一表示屏幕模式。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 先铺天空。
        GL.glEnable(GL.GL_DEPTH_TEST)  # 地形开始写深度。
        GL.glDepthMask(GL.GL_TRUE)  # 允许写深度。
        GL.glUseProgram(self.terrain_program)  # 切到地形程序。
        view = self.camera.view_matrix()  # 视图矩阵。
        projection = self.camera.projection_matrix(self.width / self.height, NEAR, FAR)  # 投影矩阵。
        GL.glUniformMatrix4fv(location(self.terrain_program, "uViewProjection"), 1, GL.GL_FALSE,
                              multiply(projection, view))  # 列主序相乘。
        GL.glUniform3f(location(self.terrain_program, "uCameraPos"), *self.camera.position)  # 雾与视线。
        GL.glUniform3f(location(self.terrain_program, "uSunDirection"), *self.sun)  # 直射与阴影方向。
        GL.glUniform1f(location(self.terrain_program, "uTerrainSize"), float(TERRAIN_SIZE))  # 高度图范围。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 高度图固定零号单元。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.height_texture)  # 绑定高度图。
        GL.glUniform1i(location(self.terrain_program, "uHeight"), 0)  # 着色器采样零号单元。
        GL.glBindVertexArray(self.terrain_vao)  # 地形顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.terrain_triangles * 3)  # 全部三角形一次画完。

    def render_water(self, scene_time: float) -> None:
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
        GL.glUniformMatrix4fv(location(self.water_program, "uViewProjection"), 1, GL.GL_FALSE,
                              multiply(projection, view))  # 列主序相乘。
        GL.glUniform3f(location(self.water_program, "uCameraPos"), *self.camera.position)  # 视线方向。
        GL.glUniform3f(location(self.water_program, "uSunDirection"), *self.sun)  # 太阳高光。
        GL.glUniform1f(location(self.water_program, "uTime"), scene_time)  # 波浪动画。
        GL.glUniform1f(location(self.water_program, "uWaterLevel"), terrain.SEA_LEVEL)  # 海平面高度。
        GL.glUniform2f(location(self.water_program, "uResolution"), self.width, self.height)  # 屏幕坐标。
        GL.glUniform1f(location(self.water_program, "uNear"), NEAR)  # 深度反解用近平面。
        GL.glUniform1f(location(self.water_program, "uFar"), FAR)  # 深度反解用远平面。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放天空。
        GL.glBindTexture(GL.GL_TEXTURE_CUBE_MAP, self.sky_cube)  # 反射纹理。
        GL.glUniform1i(location(self.water_program, "uSky"), 0)  # 采样器指向零号单元。
        GL.glActiveTexture(GL.GL_TEXTURE1)  # 一号单元放场景颜色。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_color)  # 折射颜色。
        GL.glUniform1i(location(self.water_program, "uSceneColor"), 1)  # 采样器指向一号单元。
        GL.glActiveTexture(GL.GL_TEXTURE2)  # 二号单元放场景深度。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.scene_depth)  # 水深计算。
        GL.glUniform1i(location(self.water_program, "uSceneDepth"), 2)  # 采样器指向二号单元。
        GL.glBindVertexArray(self.water_vao)  # 海面顶点数组。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, self.water_triangles * 3)  # 一次画完海面。
        GL.glDisable(GL.GL_BLEND)  # 后续阶段不需要混合。
        GL.glDepthMask(GL.GL_TRUE)  # 恢复深度写入。

    def render_post(self, frame: int) -> None:
        """把水面结果压缩到屏幕，完成一帧。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)  # 最后输出到窗口。
        GL.glViewport(0, 0, self.width, self.height)  # 完整分辨率。
        GL.glDisable(GL.GL_DEPTH_TEST)  # 后期是二维处理。
        GL.glUseProgram(self.post_program)  # 后期程序。
        GL.glActiveTexture(GL.GL_TEXTURE0)  # 零号单元放水面结果。
        GL.glBindTexture(GL.GL_TEXTURE_2D, self.water_color)  # 线性场景颜色。
        GL.glUniform1i(location(self.post_program, "uColor"), 0)  # 采样器指向零号单元。
        GL.glUniform2f(location(self.post_program, "uResolution"), self.width, self.height)  # 画面尺寸。
        GL.glUniform1f(location(self.post_program, "uExposure"), 0.85)  # 曝光倍率。
        GL.glUniform1i(location(self.post_program, "uTonemap"), self.tonemap)  # 曲线编号。
        GL.glUniform1f(location(self.post_program, "uFrame"), float(frame))  # 抖动相位。
        GL.glBindVertexArray(self.fullscreen)  # 全屏三角形。
        GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)  # 输出最终画面。

    def draw(self, frame: int, scene_time: float) -> None:
        """按固定顺序绘制一帧：反射、天空与地形、水面、后期。"""
        self.render_sky_cube(frame, scene_time)
        self.render_scene(frame, scene_time)
        self.render_water(scene_time)
        self.render_post(frame)

    def screenshot(self, path: Path) -> None:
        """读回默认帧缓冲并写成图片。"""
        GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, 0)
        GL.glReadBuffer(GL.GL_BACK)
        pixels = GL.glReadPixels(0, 0, self.width, self.height, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)
        rgb = bytearray(self.width * self.height * 3)  # 图片只保留三个颜色通道。
        for index in range(self.width * self.height):  # 丢弃透明通道。
            source = index * 4
            target = index * 3
            rgb[target:target + 3] = pixels[source:source + 3]
        path.parent.mkdir(parents=True, exist_ok=True)
        png.write_rgb(path, self.width, self.height, bytes(rgb))

    def close(self) -> None:
        """释放显卡对象与窗口。"""
        GL.glDeleteProgram(self.sky_program)
        GL.glDeleteProgram(self.terrain_program)
        GL.glDeleteProgram(self.water_program)
        GL.glDeleteProgram(self.post_program)
        GL.glDeleteVertexArrays(3, [self.fullscreen, self.terrain_vao, self.water_vao])
        GL.glDeleteBuffers(2, [self.terrain_vbo, self.water_vbo])
        GL.glDeleteTextures([self.height_texture, self.scene_color, self.scene_depth, self.water_color,
                             self.water_depth, self.sky_cube])
        GL.glDeleteFramebuffers(3, [self.scene_fbo, self.water_fbo, self.sky_fbo])
        glfw.destroy_window(self.window)
        glfw.terminate()


def multiply(a: list[float], b: list[float]) -> list[float]:
    """列主序四乘四矩阵相乘，返回 a 乘 b。

    OpenGL 的矩阵按列存放；这里按同一约定计算，上传时不需要转置。
    """
    result = [0.0] * 16  # 结果矩阵。
    for column in range(4):  # 遍历结果的每一列。
        for row in range(4):  # 遍历每一行。
            result[column * 4 + row] = sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))  # 点积。
    return result  # 可直接上传。


def percentile(values: list[float], fraction: float) -> float:
    """返回排序后指定分位的值，用于报告慢帧。"""
    ordered = sorted(values)  # 不改动原列表。
    index = min(len(ordered) - 1, max(0, int(len(ordered) * fraction)))  # 分位落在有效范围内。
    return ordered[index]  # 返回该位置的值。


def run(args) -> None:
    """按参数运行截图或交互模式，并写出性能记录。"""
    world = World(args.width, args.height, args.tonemap, args.cloud_cover, args.sun)  # 场景只建一次。
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
            "cloudSteps": 14,
            "camera": args.camera,
            "target": args.target,
            "sun": args.sun,
            "time": args.time,
            "tonemap": args.tonemap,
        }
        perf_path.parent.mkdir(parents=True, exist_ok=True)
        perf_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"截图：{output}")
        print(f"帧时：平均 {average:.2f} 毫秒，中位 {report['medianMs']:.2f}，95 分位 {report['p95Ms']:.2f}，"
              f"最小 {report['minMs']:.2f}，最大 {report['maxMs']:.2f}")
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
    parser.add_argument("--screenshot", default=str(ROOT / ".dev/omni-gfx/world.png"), help="截图路径")
    parser.add_argument("--perf", default=str(ROOT / ".dev/omni-gfx/perf.json"), help="性能记录路径")
    parser.add_argument("--window", action="store_true", help="打开可交互窗口")
    parser.add_argument("--camera", type=float, nargs=3, default=[48.0, 30.0, 100.0], help="相机位置")
    parser.add_argument("--target", type=float, nargs=3, default=[48.0, 16.0, 40.0], help="看向的目标")
    parser.add_argument("--sun", type=float, nargs=3, default=DEFAULT_SUN, help="太阳方向")
    parser.add_argument("--time", type=float, default=12.0, help="固定场景时间")
    parser.add_argument("--cloud-cover", type=float, default=0.35, help="云量零到一")
    parser.add_argument("--tonemap", type=int, default=0, choices=(0, 1, 2), help="零 ACES，一 AgX，二无压缩")
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
