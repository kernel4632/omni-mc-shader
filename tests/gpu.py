"""显卡测试工具：编译所有基础程序并读回最终调试像素。

示例 .venv/Scripts/python.exe tests/gpu.py；必须用户授权实际显卡测试后执行。
报告明确区分程序链接、可预测调试像素与没有覆盖的完整世界绘制。
"""
from __future__ import annotations
import ctypes  # 向实际驱动传递纹理与像素。
import json  # 保存真实设备和结果。
import sys  # 从项目根目录导入构建主体。
from pathlib import Path  # 输出只写开发报告。
import glfw  # 现有锁定依赖建立兼容上下文。
from OpenGL import GL as gl  # 实际驱动编译与像素读取。
ROOT = Path(__file__).resolve().parents[1]  # 测试位置不依赖终端目录。
sys.path.insert(0,str(ROOT))  # 复用真实展开与配置接口。
import build  # 不另写一份渲染预处理。

def program(name: str, values: dict, found: dict) -> int:
    """链接真实多阶段程序，驱动错误保留原文。"""
    kinds = {".vsh":gl.GL_VERTEX_SHADER,".fsh":gl.GL_FRAGMENT_SHADER,".gsh":gl.GL_GEOMETRY_SHADER,".tcs":gl.GL_TESS_CONTROL_SHADER,".tes":gl.GL_TESS_EVALUATION_SHADER,".csh":gl.GL_COMPUTE_SHADER}
    handle = gl.glCreateProgram(); compiled = []  # 资源在结束或失败后释放。
    try:
        for suffix,kind in kinds.items():
            source = ROOT/"shaders/world0"/(name+suffix)  # 主世界驱动检查与加载器使用同一路径。
            if not source.is_file(): continue  # 只有流程实际存在的阶段才编译。
            text = build.option_source(build.expand(source),found,values)  # 默认或指定合法配置。
            text = text.replace("#version 330 compatibility","#version 330 compatibility\n#define RGBA16F 34842\n#define RGBA32F 34836",1)  # 模拟加载器格式宏。
            shader = gl.glCreateShader(kind); compiled.append(shader)
            gl.glShaderSource(shader,text); gl.glCompileShader(shader)  # 使用实际显卡编译器。
            if not gl.glGetShaderiv(shader,gl.GL_COMPILE_STATUS): raise RuntimeError(gl.glGetShaderInfoLog(shader).decode("utf-8",errors="replace"))
            gl.glAttachShader(handle,shader)  # 多阶段一起检查接口。
        gl.glLinkProgram(handle)  # 不把单阶段编译当链接成功。
        if not gl.glGetProgramiv(handle,gl.GL_LINK_STATUS): raise RuntimeError(gl.glGetProgramInfoLog(handle).decode("utf-8",errors="replace"))
        return handle  # 调用者负责删除有效程序。
    except Exception:
        gl.glDeleteProgram(handle); raise  # 失败不遗留驱动资源。
    finally:
        for shader in compiled: gl.glDeleteShader(shader)  # 链接完成后阶段对象可释放。

def texture(unit: int, color: tuple) -> int:
    """准备可预测纹理，避免未绑定输入影响调试断言。"""
    handle = gl.glGenTextures(1)
    gl.glActiveTexture(gl.GL_TEXTURE0+unit); gl.glBindTexture(gl.GL_TEXTURE_2D,handle)  # 固定采样单元。
    data = (ctypes.c_float*4)(*color)  # 真实线性浮点数据。
    gl.glTexImage2D(gl.GL_TEXTURE_2D,0,gl.GL_RGBA32F,1,1,0,gl.GL_RGBA,gl.GL_FLOAT,data)  # 单像素常量输入。
    gl.glTexParameteri(gl.GL_TEXTURE_2D,gl.GL_TEXTURE_MIN_FILTER,gl.GL_NEAREST)
    gl.glTexParameteri(gl.GL_TEXTURE_2D,gl.GL_TEXTURE_MAG_FILTER,gl.GL_NEAREST)  # 不引入过滤误差。
    return handle  # 由测试结束统一释放。

def draw(handle: int) -> list:
    """绘制最终程序的可预测深度或坐标调试输出。"""
    gl.glUseProgram(handle)
    for name,unit in [("colortex"+str(i),i) for i in range(9)]+[("depthtex0",9)]:  # 水附件独立绑定，不能与标准深度共用单元。
        location = gl.glGetUniformLocation(handle,name)
        if location>=0: gl.glUniform1i(location,unit)  # 所有实际引用纹理均绑定真实输入。
    for name,value in (("viewWidth",64.0),("viewHeight",64.0)):
        location = gl.glGetUniformLocation(handle,name)
        if location>=0: gl.glUniform1f(location,value)  # 调试采样使用固定尺寸。
    gl.glBegin(gl.GL_QUADS)  # 与加载器相同兼容四边形。
    for x,y in ((-1,-1),(1,-1),(1,1),(-1,1)):
        gl.glTexCoord2f((x+1)/2,(y+1)/2); gl.glVertex2f(x,y)  # 坐标与屏幕位置一一对应。
    gl.glEnd(); gl.glFinish()  # 读回之前等待真实绘制完成。
    pixel = (ctypes.c_float*4)()
    gl.glReadPixels(32,32,1,1,gl.GL_RGBA,gl.GL_FLOAT,pixel)  # 只断言已知中心像素。
    return list(pixel)

def main() -> None:
    """真实显卡测试不会由普通单元测试自动触发。"""
    if not glfw.init(): raise RuntimeError("无法初始化图形环境")
    window, textures = None,[]  # 失败也统一释放上下文资源。
    try:
        glfw.window_hint(glfw.VISIBLE,glfw.FALSE)  # 测试使用隐藏窗口。
        glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR,3); glfw.window_hint(glfw.CONTEXT_VERSION_MINOR,3)
        glfw.window_hint(glfw.OPENGL_PROFILE,glfw.OPENGL_COMPAT_PROFILE)  # 基础路径需要兼容内置属性。
        glfw.window_hint(glfw.DOUBLEBUFFER,glfw.FALSE)
        window = glfw.create_window(64,64,"Omni GPU check",None,None)
        if not window: raise RuntimeError("无法创建兼容图形上下文")
        glfw.make_context_current(window); gl.glViewport(0,0,64,64)  # 固定测试像素范围。
        gl.glDisable(gl.GL_DITHER)  # 不让驱动抖动改变断言。
        found,_,_ = build.configuration(); defaults = {n:o.default for n,o in found.items()}  # 读取真实默认配置。
        names = sorted({p.stem for p in build.entrypoints() if p.parent==build.SHADERS/"world0"})  # 根目录只有共用代码，不是实际程序来源。
        linked = []
        for name in names:
            handle = program(name,defaults,found); gl.glDeleteProgram(handle)  # 所有基础入口在当前驱动实际链接。
            linked.append(name)  # 只记录已执行结果。
        textures = [texture(i,(0.2,0.4,0.6,1.0)) for i in range(9)] + [texture(9,(0.25,0,0,1))]  # 覆盖新增水深附件，工具本轮仍不运行。
        expectations = {"1":(0.25,0.25,0.25,1.0),"2":(32.5/64,32.5/64,0,1.0)}  # 正常画面调色不再使用旧版恒等断言。
        views = []
        for view,expected in expectations.items():
            handle = program("final",defaults|{"OMNI_DEBUG_VIEW":view},found)
            try:
                actual = draw(handle)  # 真正执行最终调试路径。
                if any(abs(a-b)>0.01 for a,b in zip(actual,expected)): raise RuntimeError(f"调试视图 {view} 输出不符：{actual}")
                views.append({"view":view,"pixel":actual,"status":"通过"})
            finally: gl.glUseProgram(0); gl.glDeleteProgram(handle)  # 单个断言失败也释放程序。
        report = {"shaderVersion":build.version(),"vendor":gl.glGetString(gl.GL_VENDOR).decode(),"renderer":gl.glGetString(gl.GL_RENDERER).decode(),"opengl":gl.glGetString(gl.GL_VERSION).decode(),"linkedPrograms":linked,"views":views,"scope":"基础程序驱动链接与最终调试像素；未覆盖完整场景、远景接口或游戏集成"}
        destination = ROOT/".dev/reports/gpu.json"; destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")  # 不覆盖公开兼容结论。
        print(json.dumps(report,ensure_ascii=False,indent=2))
    finally:
        if window:
            if textures: gl.glDeleteTextures(textures)  # 测试结束删除自有纹理。
            glfw.destroy_window(window)
        glfw.terminate()  # 不遗留隐藏上下文。

if __name__=="__main__":
    sys.stdout.reconfigure(encoding="utf-8"); sys.stderr.reconfigure(encoding="utf-8")  # 驱动与中文报告可读。
    try: main()
    except (RuntimeError,OSError) as error: print(f"显卡测试失败：{error}",file=sys.stderr); sys.exit(1)  # 错误不伪装通过。
