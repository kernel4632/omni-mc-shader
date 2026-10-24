"""逐通道比较旧 `gfx_` 库与新 `ogx_` 库在真实显卡上的输出。

调用位置：`omni-gfx/build.py test-gpu`；需要 OpenGL 3.3 与显卡，不进入离线检查。
调用示例：`python omni-gfx/build.py test-gpu`。

设计原因与取舍：
    同一个片段着色器里同时调用两边函数，输入、驱动和精度完全一致，
    差异只可能来自迁移本身。结果写两张浮点附件，读回后逐像素比较。
    容差默认极小但不要求逐位相等：乘加顺序在个别驱动上可能重排。
    测试通过只证明这些函数数值一致，不代表完整画面在游戏里已验证。
"""
from __future__ import annotations

import json  # 结果记录供验证文档引用。
import sys  # 调整工具目录的搜索路径。
from pathlib import Path  # 项目内路径。

import glfw  # 退出前释放窗口。
from OpenGL import GL  # 绘制与读回。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用窗口与帧缓冲工具。

import gl  # 项目内 OpenGL 小工具。

SIZE = 256  # 测试固定两百五十六像素见方，坐标与用例都按这个尺寸构造。
TOLERANCE = 1e-6  # 允许极小的乘加顺序差异，超过就说明迁移改变了结果。
CASES = (
    "亮度与三角近似",  # 第0号比较项。
    "平方根与曲线",  # 第1号比较项。
    "八位打包",  # 第2号比较项。
    "十六位打包",  # 第3号比较项。
    "法线编码",  # 第4号比较项。
    "贴图法线与 GGX 分布",  # 第5号比较项。
    "高光四项",  # 第6号比较项。
    "黑体 3000K",  # 第7号比较项。
    "黑体 6500K",  # 第8号比较项。
    "黑体 12000K",  # 第9号比较项。
    "射线求交",  # 第10号比较项。
    "相函数与基础噪声",  # 第11号比较项。
    "拜尔与径向曲线",  # 第12号比较项。
    "颜色转色相",  # 第13号比较项。
    "色相还原与曲率",  # 第14号比较项。
    "切线基",  # 第15号比较项。
    "空间扭曲",  # 第16号比较项。
    "数学模块伽马",  # 第17号比较项。
    "颜色模块伽马",  # 第18号比较项。
    "ACES 带校正",  # 第19号比较项。
    "ACES 不带校正",  # 第20号比较项。
    "AgX 带校正",  # 第21号比较项。
    "AgX 不带校正",  # 第22号比较项。
    "无压缩与高级调色",  # 第23号比较项。
    "暗视觉与黑边",  # 第24号比较项。
    "采样模块",  # 第25号比较项。
)  # 顺序与着色器里的编号一一对应，改动时必须两边同时改。


def make_noise_texture() -> int:
    """创建一张六十四像素的确定性噪声纹理，供两边采样函数共同读取。

    纹理内容不重要，只要两边读到同一像素；用固定算式生成，重复运行结果一致。
    """
    size = 64  # 与采样模块的平铺尺寸一致。
    data = bytearray()
    for y in range(size):
        for x in range(size):
            for channel in range(4):
                data.append((x * 7 + y * 13 + channel * 29) % 251)  # 固定算式，避免随机源。
    texture = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, texture)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA8, size, size, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, bytes(data))
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST)
    return texture  # 调用方负责删除。


def compare() -> dict:
    """运行全部用例并返回每个用例的最大差异。

    返回结构包含设备信息、用例名称、每例最大绝对差与是否通过，
    供命令行报告和验证文档共用。
    """
    window = gl.init_window(SIZE, SIZE, "omni-gfx 等值测试", visible=False)
    device = gl.device_info()  # 在上下文仍然有效时读取设备信息。
    program = gl.build_program(LIB / "tests" / "fullscreen.vert", LIB / "tests" / "equivalence.glsl")
    vao = gl.fullscreen_vao()
    fbo, textures = gl.float_target(SIZE, SIZE, 2)
    noise = make_noise_texture()
    GL.glUseProgram(program)
    GL.glUniform1i(GL.glGetUniformLocation(program, "uNoise"), 0)  # 噪声纹理固定绑到零号单元。
    results = []  # 每个用例一条记录。
    # 逐号绘制：每次只改用例编号，输入与设备状态保持完全一致。
    try:
        for index, name in enumerate(CASES):
            GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, fbo)
            GL.glViewport(0, 0, SIZE, SIZE)
            GL.glUseProgram(program)
            GL.glUniform1i(GL.glGetUniformLocation(program, "uCase"), index)
            GL.glActiveTexture(GL.GL_TEXTURE0)
            GL.glBindTexture(GL.GL_TEXTURE_2D, noise)
            GL.glBindVertexArray(vao)
            GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
            GL.glFinish()  # 读回前必须等绘制完成。
            old = gl.read_float(textures[0], SIZE, SIZE)
            new = gl.read_float(textures[1], SIZE, SIZE)
            if len(old) != len(new) or not old:
                raise RuntimeError(f"用例 {index} 读回长度异常：{len(old)} 与 {len(new)}")
            maximum = 0.0  # 本用例的最大绝对差。
            # 逐通道比较，记录差得最多的通道，失败时能直接定位到某个函数输出。
            worst = 0  # 差异最大的通道下标，便于定位。
            for channel, (a, b) in enumerate(zip(old, new)):
                difference = abs(a - b)
                if difference > maximum:
                    maximum = difference
                    worst = channel
            results.append({"case": index, "name": name, "maxDiff": maximum, "worstChannel": worst, "pass": maximum <= TOLERANCE})
    finally:
        GL.glDeleteTextures([noise, *textures])  # 释放本次测试创建的纹理。
        GL.glDeleteFramebuffers(1, [fbo])
        GL.glDeleteProgram(program)
        glfw.destroy_window(window)
        glfw.terminate()
    return {"size": SIZE, "tolerance": TOLERANCE, "device": device, "cases": results}


def main() -> None:
    """运行测试、打印每个用例的最大差异，并把结果写入本机记录目录。

    任一用例超出容差就返回非零退出码，让构建入口和人工检查都能看到失败。
    """
    report = compare()  # 全部绘制在这里完成。
    # 先打印逐项结果，再统一判断，避免第一条失败就看不到后面的情况。
    passed = all(item["pass"] for item in report["cases"])  # 所有用例必须同时通过。
    for item in report["cases"]:
        mark = "通过" if item["pass"] else "失败"
        print(f"{item['case']:02d} {item['name']}：最大差异 {item['maxDiff']:.3g}，{mark}")
    output = ROOT / ".dev" / "omni-gfx" / "equivalence.json"  # 本机记录，不提交。
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"设备：{report['device']['renderer']} / {report['device']['version']}")
    print(f"结果：{sum(item['pass'] for item in report['cases'])}/{len(report['cases'])} 通过，记录 {output.relative_to(ROOT)}")
    if not passed:
        raise SystemExit(1)  # 失败必须让命令返回非零。


if __name__ == "__main__":
    main()
