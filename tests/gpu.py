"""显卡冒烟测试：用 OpenGL 兼容环境编译实际入口并检查像素输出。

运行示例：.venv/Scripts/python.exe tests/gpu.py。
结果写入 .dev/reports/gpu.json；这是基础绘制验证，不能代替 Iris 游戏适配。
"""

from __future__ import annotations

import ctypes
import json
import sys
from pathlib import Path

import glfw
from OpenGL import GL as gl

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build


def shader(kind: int, text: str) -> int:
    """使用当前显卡编译一个阶段，保留驱动给出的错误原因。"""
    handle = gl.glCreateShader(kind)
    gl.glShaderSource(handle, text)
    gl.glCompileShader(handle)
    if not gl.glGetShaderiv(handle, gl.GL_COMPILE_STATUS):
        error = gl.glGetShaderInfoLog(handle).decode("utf-8", errors="replace")
        gl.glDeleteShader(handle)
        raise RuntimeError(error)
    return handle


def program(values: dict, options: dict) -> int:
    """编译并链接项目的实际 final 顶点和像素入口。"""
    shaders = []
    handle = gl.glCreateProgram()
    try:
        for kind, suffix in ((gl.GL_VERTEX_SHADER, ".vsh"), (gl.GL_FRAGMENT_SHADER, ".fsh")):
            source = build.expand(ROOT / "shaders" / ("final" + suffix))
            compiled = shader(kind, build.option_source(source, options, values))
            shaders.append(compiled)
            gl.glAttachShader(handle, compiled)
        gl.glLinkProgram(handle)
        if not gl.glGetProgramiv(handle, gl.GL_LINK_STATUS):
            raise RuntimeError(gl.glGetProgramInfoLog(handle).decode("utf-8", errors="replace"))
        return handle
    except Exception:
        gl.glDeleteProgram(handle)
        raise
    finally:
        for compiled in shaders:
            gl.glDeleteShader(compiled)


def texture(unit: int, color: tuple[float, ...]) -> int:
    """准备可预测的小纹理，使读回颜色能够与已知结果比较。"""
    handle = gl.glGenTextures(1)
    gl.glActiveTexture(gl.GL_TEXTURE0 + unit)
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
    data = (ctypes.c_float * len(color))(*color)
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, 1, 1, 0, gl.GL_RGBA, gl.GL_FLOAT, data)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST)
    return handle


def draw(handle: int) -> list[float]:
    """绘制覆盖屏幕的四边形，读回中心像素，检查整条基础绘制路径。"""
    gl.glUseProgram(handle)
    for name, unit in (("colortex0", 0), ("depthtex0", 1)):
        location = gl.glGetUniformLocation(handle, name)
        if location >= 0:
            gl.glUniform1i(location, unit)
    gl.glActiveTexture(gl.GL_TEXTURE0)
    gl.glBegin(gl.GL_QUADS)
    for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        gl.glTexCoord2f((x + 1) / 2, (y + 1) / 2)
        gl.glVertex2f(x, y)
    gl.glEnd()
    gl.glFinish()
    pixel = (ctypes.c_float * 4)()
    gl.glReadPixels(32, 32, 1, 1, gl.GL_RGBA, gl.GL_FLOAT, pixel)
    return list(pixel)


def main() -> None:
    """建立隐藏窗口，在真实显卡上检查全部开发调试视图。"""
    if not glfw.init():
        raise RuntimeError("无法初始化 GLFW 图形环境")
    window, textures = None, []
    try:
        glfw.window_hint(glfw.VISIBLE, glfw.FALSE)
        glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 3)
        glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)
        glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_COMPAT_PROFILE)
        glfw.window_hint(glfw.DOUBLEBUFFER, glfw.FALSE)
        window = glfw.create_window(64, 64, "Omni GPU check", None, None)
        if not window:
            raise RuntimeError("无法创建 OpenGL 3.3 兼容环境")
        glfw.make_context_current(window)
        gl.glViewport(0, 0, 64, 64)
        gl.glDisable(gl.GL_DITHER)
        textures = [texture(0, (0.2, 0.4, 0.6, 1.0)), texture(1, (0.25, 0.0, 0.0, 1.0))]
        options, _, _ = build.configuration()
        defaults = {name: option.default for name, option in options.items()}
        expectations = {"0": (0.2, 0.4, 0.6, 1.0), "1": (0.25, 0.25, 0.25, 1.0),
                        "2": (32.5 / 64, 32.5 / 64, 0.0, 1.0)}
        results = []
        for view, expected in expectations.items():
            handle = program(defaults | {"OMNI_DEBUG_VIEW": view}, options)
            try:
                actual = draw(handle)
                if any(abs(value - target) > 0.01 for value, target in zip(actual, expected)):
                    raise RuntimeError(f"视图 {view} 输出不符：实际 {actual}，期望 {expected}")
                results.append({"view": view, "pixel": actual, "status": "passed"})
            finally:
                gl.glUseProgram(0)
                gl.glDeleteProgram(handle)
        report = {"vendor": gl.glGetString(gl.GL_VENDOR).decode(),
                  "renderer": gl.glGetString(gl.GL_RENDERER).decode(),
                  "opengl": gl.glGetString(gl.GL_VERSION).decode(), "views": results,
                  "scope": "OpenGL final pass only; Minecraft/Iris integration not tested"}
        destination = ROOT / ".dev/reports/gpu.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
    finally:
        if window:
            if textures:
                gl.glDeleteTextures(textures)
            glfw.destroy_window(window)
        glfw.terminate()


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (RuntimeError, OSError) as error:
        print(f"显卡测试失败：{error}", file=sys.stderr)
        sys.exit(1)
