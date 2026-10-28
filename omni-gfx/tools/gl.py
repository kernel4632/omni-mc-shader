"""GPU 测试与测试世界共用的 OpenGL 小工具：建上下文、展开引用、编译程序、读像素。

调用位置：`omni-gfx/tests/equivalence.py` 和 `omni-gfx/examples/world/render.py`。
调用示例：等价测试导入本模块建立 OpenGL 上下文并运行全屏着色器。

设计原因与取舍：
    只封装每次都要重复的样板：窗口、着色器日志、浮点目标与全屏三角形。
    引用展开规则与项目构建保持一致：以斜杠开头的路径相对 `shaders/`，其余相对引用者。
    这里不做渲染算法，场景与测试各自保留自己的职责。
"""
from __future__ import annotations

import re  # 识别引用行。
from pathlib import Path  # 引用路径解析。

import glfw  # 跨平台窗口与 OpenGL 上下文。
from OpenGL import GL  # 实际绘制调用。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
SHADERS = ROOT / "shaders"  # 光影目录，测试与示例都从这里读取生成库。

INCLUDE = re.compile(r'^[ \t]*#include[ \t]+"([^"\n]+)"[ \t]*$', re.MULTILINE)  # 只认整行引用。


def init_window(width: int, height: int, title: str, visible: bool) -> object:
    """创建 OpenGL 3.3 核心上下文窗口，返回窗口对象。

    核心模式与 Minecraft 使用的 330 兼容模式共用同一批语法；
    隐藏窗口用于截图和计时，可见窗口用于交互查看。
    """
    # 初始化失败通常是没有窗口系统或驱动缺失，必须直接报出。
    if not glfw.init():  # 不能静默退回软件绘制。
        raise RuntimeError("GLFW 初始化失败")
    glfw.window_hint(glfw.VISIBLE, glfw.TRUE if visible else glfw.FALSE)  # 截图时不弹出窗口。
    glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 3)  # 与光影基础路径一致的主版本。
    glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)  # 与光影基础路径一致的次版本。
    glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)  # 核心模式，避免旧特性混入。
    window = glfw.create_window(width, height, title, None, None)  # 不共享其他上下文。
    if not window:  # 没有可用显卡或版本不满足时，窗口为空。
        glfw.terminate()  # 初始化过的库必须释放，避免下次调用状态混乱。
        raise RuntimeError("创建 OpenGL 窗口失败")
    glfw.make_context_current(window)  # 后续调用都作用于这个上下文。
    glfw.swap_interval(0)  # 关垂直同步，帧时反映真实绘制耗时。
    return window  # 调用方负责事件循环与退出。


def device_info() -> dict:
    """读取当前 OpenGL 版本、显卡与驱动字符串，写进性能记录。

    这些值与性能结论绑定，换设备后不能直接套用同一帧时。
    """
    # 三个字符串一起记录，换驱动或换显卡时能直接看出差异。
    return {
        "version": GL.glGetString(GL.GL_VERSION).decode("utf-8", "replace"),
        "renderer": GL.glGetString(GL.GL_RENDERER).decode("utf-8", "replace"),
        "vendor": GL.glGetString(GL.GL_VENDOR).decode("utf-8", "replace"),
    }


def _include_path(reference: str, parent: Path) -> Path:
    """把一条引用解析成真实文件，规则与光影加载器一致。

    以斜杠开头表示光影根目录，其余相对当前文件；路径逃出光影目录时拒绝。
    """
    path = (SHADERS / reference[1:]) if reference.startswith("/") else (parent.parent / reference)
    path = path.resolve()  # 先解析真实路径，目录链接也不能逃出光影目录。
    if not path.is_file() or not (path.is_relative_to(SHADERS.resolve()) or path.is_relative_to(LIB.resolve())):  # 光影库与示例目录都允许相对引用。
        raise ValueError(f"引用不存在或越界：{reference}（来自 {parent}）")
    return path


def expand(source: Path, stack: tuple[Path, ...] = ()) -> str:
    """展开一个着色器文件的全部引用，返回可编译的完整文本。

    `stack` 用于检测循环引用；被引用文件不允许再写 `#version`，
    语言版本只能由最外层入口声明。
    """
    source = source.resolve()
    if source in stack:
        raise ValueError("循环引用：" + " → ".join(path.name for path in (*stack, source)))
    # 读入整份源文件，引用行按整行替换，注释与空行原样保留。
    text = source.read_text(encoding="utf-8")  # 源文件统一 UTF-8。
    for match in INCLUDE.finditer(text):  # 只展开真正独立的引用行。
        included = _include_path(match[1], source)
        if re.search(r"(?m)^\s*#version\b", included.read_text(encoding="utf-8")):
            raise ValueError(f"被引用文件不能声明 #version：{included}")
        body = expand(included, (*stack, source))  # 递归展开更深的引用。
        text = text.replace(match[0], body)  # 同一行只替换一次，引用行本身不保留。
    return text  # 注释与空行原样保留，日志仍能定位源文件。


def build_program(vertex: Path, fragment: Path) -> int:
    """编译并链接一对顶点与片元着色器，返回程序编号。

    失败时抛出带编译器日志的错误，日志保留完整的行号信息。
    """
    # 程序对象先建好，两个阶段编译成功后再链接，失败时日志仍带源文件路径。
    program = GL.glCreateProgram()  # 先建程序对象。
    stages = []  # 已编译的阶段对象，链接后统一删除。
    for stage, path in ((GL.GL_VERTEX_SHADER, vertex), (GL.GL_FRAGMENT_SHADER, fragment)):
        shader = GL.glCreateShader(stage)
        GL.glShaderSource(shader, expand(path))  # 引用在交给驱动前展开。
        GL.glCompileShader(shader)
        if not GL.glGetShaderiv(shader, GL.GL_COMPILE_STATUS):
            log = GL.glGetShaderInfoLog(shader).decode("utf-8", "replace")
            raise RuntimeError(f"着色器编译失败：{path}\n{log}")
        GL.glAttachShader(program, shader)  # 链接前挂到程序。
        stages.append(shader)
    GL.glLinkProgram(program)  # 链接两个阶段。
    if not GL.glGetProgramiv(program, GL.GL_LINK_STATUS):
        log = GL.glGetProgramInfoLog(program).decode("utf-8", "replace")
        raise RuntimeError(f"着色器链接失败：{fragment}\n{log}")
    # 链接成功后阶段对象可以释放，程序本身继续持有编译结果。
    for shader in stages:  # 逐个释放。
        GL.glDeleteShader(shader)
    return program  # 调用方负责在退出前删除。


def fullscreen_vao() -> int:
    """创建一个空顶点数组，供不依赖顶点缓冲的全屏三角形使用。

    顶点位置由 `gl_VertexID` 直接算出，空数组只是核心模式要求的绑定对象。
    """
    vao = GL.glGenVertexArrays(1)
    GL.glBindVertexArray(vao)
    return vao


def float_target(width: int, height: int, count: int) -> tuple[int, list[int]]:
    """创建带若干 RGBA32F 附件的帧缓冲，返回帧缓冲与纹理编号。

    浮点附件用于逐通道比较，不需要经过八位量化，差异不会被舍入掩盖。
    """
    fbo = GL.glGenFramebuffers(1)
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)
    # 每个附件一张独立纹理，Python 侧才能分别读回旧值和新值。
    textures = []  # 按附件顺序保存纹理编号。
    attachments = []  # 传给绘制缓冲的枚举值。
    for index in range(count):
        texture = GL.glGenTextures(1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
        GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA32F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)
        attachment = GL.GL_COLOR_ATTACHMENT0 + index
        GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, attachment, GL.GL_TEXTURE_2D, texture, 0)
        textures.append(texture)  # 纹理编号按附件顺序保存。
        attachments.append(attachment)  # 绘制缓冲列表与附件编号一一对应。
    GL.glDrawBuffers(len(attachments), attachments)  # 一次写入全部附件。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 驱动不支持浮点附件时尽早失败。
        raise RuntimeError("浮点帧缓冲不完整")
    # 调用方负责在退出前删除帧缓冲与全部附件纹理。
    return fbo, textures  # 返回编号。


def color_depth_target(width: int, height: int) -> tuple[int, int, int]:
    """创建一张颜色加一张深度的离屏目标，返回帧缓冲、颜色纹理与深度纹理。

    测试世界先把天空与地形画进这里，再复制给水面阶段；
    颜色用十六位浮点保存线性高动态范围，避免水面反射提前被截断。
    """
    fbo = GL.glGenFramebuffers(1)
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)
    color = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, color)
    # 十六位浮点保存线性颜色，太阳高光不会在进入后期前被截断。
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA16F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0, GL.GL_TEXTURE_2D, color, 0)
    depth = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, depth)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_DEPTH_COMPONENT24, width, height, 0, GL.GL_DEPTH_COMPONENT, GL.GL_FLOAT, None)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_ATTACHMENT, GL.GL_TEXTURE_2D, depth, 0)
    GL.glDrawBuffer(GL.GL_COLOR_ATTACHMENT0)
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 深度纹理在部分驱动上不完整时尽早报错。
        raise RuntimeError("场景帧缓冲不完整")
    return fbo, color, depth  # 调用方负责释放三个对象。


def multi_color_depth_target(width: int, height: int, count: int) -> tuple[int, list[int], int]:
    """创建带多张颜色附件与一张深度的离屏目标，返回帧缓冲、颜色纹理列表与深度纹理。

    为什么需要多张颜色：测试世界的场景阶段要同时写颜色与法线，后面的遮蔽与反射降噪
    都按法线和深度判断邻域，只有颜色的话拿不到几何信息。
    """
    fbo = GL.glGenFramebuffers(1)  # 绘制时挂载。
    GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)  # 之后的附件设置作用于它。
    colors = []  # 颜色纹理按附件顺序保存。
    attachments = []  # 绘制缓冲列表与附件一一对应。
    for index in range(count):  # 每张附件单独一张纹理。
        texture = GL.glGenTextures(1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
        GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA16F, width, height, 0, GL.GL_RGBA, GL.GL_FLOAT, None)  # 十六位浮点保留高动态范围。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 法线与深度不能插值，取样必须精确到纹素。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 放大同样用最近值。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
        attachment = GL.GL_COLOR_ATTACHMENT0 + index  # 这个附件的枚举值。
        GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, attachment, GL.GL_TEXTURE_2D, texture, 0)  # 挂上颜色。
        colors.append(texture)  # 保存纹理编号。
        attachments.append(attachment)  # 保存附件编号。
    depth = GL.glGenTextures(1)  # 深度纹理。
    GL.glBindTexture(GL.GL_TEXTURE_2D, depth)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_DEPTH_COMPONENT24, width, height, 0, GL.GL_DEPTH_COMPONENT, GL.GL_FLOAT, None)  # 二十四位深度。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)  # 深度只做精确比较。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)  # 放大也用最近值。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)  # 屏幕外不重复。
    GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_ATTACHMENT, GL.GL_TEXTURE_2D, depth, 0)  # 挂深度。
    GL.glDrawBuffers(len(attachments), attachments)  # 一次写全部颜色附件。
    if GL.glCheckFramebufferStatus(GL.GL_FRAMEBUFFER) != GL.GL_FRAMEBUFFER_COMPLETE:  # 驱动不支持时尽早报错。
        raise RuntimeError("多附件帧缓冲不完整")
    return fbo, colors, depth  # 调用方负责释放。


def read_float(texture: int, width: int, height: int) -> list[float]:
    """从浮点纹理读回全部像素，返回按行排列的通道列表。

    读取前绑定纹理对应的帧缓冲附件，调用方已经绘制完成。
    """
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)  # 选择要读的附件。
    # 读取整张纹理；PyOpenGL 可能返回字节，也可能返回嵌套数组，两种都要处理。
    data = GL.glGetTexImage(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, GL.GL_FLOAT)  # 返回打包字节或嵌套数组。
    if isinstance(data, (bytes, bytearray)):  # 有的后端返回连续字节。
        import array  # 只在需要时导入，保持顶部依赖轻量。
        values = array.array("f")
        values.frombytes(bytes(data))
        return list(values)
    def walk(node):
        """把 PyOpenGL 的嵌套底层数组展开成一维浮点列表。"""
        if isinstance(node, (int, float)):  # 标量已经是最终值。
            yield float(node)
            return
        try:  # 底层数组可以逐层迭代。
            iterator = iter(node)
        except TypeError:  # 单个底层标量在这里转成浮点。
            yield float(node)
            return
        for item in iterator:  # 逐层展开嵌套。
            yield from walk(item)
    return list(walk(data))  # 调用方按连续通道比较。
