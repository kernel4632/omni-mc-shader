"""静态符号扫描：按入口展开引用与条件块，报告"使用先于声明"的未定义符号。

背景：离线编译器与游戏内转译器行为不同，历史上出现过三类只在游戏里暴露的错误：
保留字当变量名、整型参数传进浮点函数、以及某些选项组合下才出现的未定义使用。
本工具不启动游戏，从每个入口按加载器同样的方式展开引用树，把所有条件分支
都当作可达（玩家可以打开任意选项组合），逐行跟踪符号首次声明与首次使用。

调用方式（在仓库根目录）：
    python tools/symbols.py               # 扫全部入口，输出未定义使用清单
    python tools/symbols.py composite     # 只扫文件名含 composite 的入口，调试用

设计取舍：不做完整预处理与类型推导，只跟踪"谁在哪一行首次出现"；
加载器注入的 uniform、MC 宏与内置函数用登记表压掉，剩余报告人工复核。
误报主要来自函数签名续行与结构体类型声明，宁多报不漏报。
"""

from __future__ import annotations  # 类型标注允许引用后文定义。

import re  # 正则匹配引用、声明与使用。
import sys  # 命令行参数读取入口过滤词。
from pathlib import Path  # 光影源码树的路径遍历。

ROOT = Path(__file__).resolve().parent.parent  # 仓库根目录。
SHADERS = ROOT / "shaders"  # 光影源码根。
STAGE_SUFFIXES = {".vsh", ".fsh", ".gsh", ".csh"}  # 光影包的四种入口阶段。

# 引用指令：路径独占一行，与加载器的解析规则一致。
INCLUDE = re.compile(r'^[ \t]*#include[ \t]+"([^"\n]+)"[ \t]*$')  # 引用指令模式。

# 加载器注入的 uniform 与内置变量：不需要声明也永远可见，整块按登记表处理。
IRIS_BUILTINS = set("""viewWidth viewHeight aspectRatio near far nearUpper farUpper  # 加载器注入项登记。
sunPosition moonPosition shadowLightPosition upPosition cameraPosition playerLookAngle  # 加载器注入项登记。
shadowPosition eyeBrightness eyeBrightnessSmooth worldTime worldDay sunAngle moonPhase  # 加载器注入项登记。
rainStrength wetness isEyeInWater blindness darknessFactor darknessLightFactor  # 加载器注入项登记。
screenBrightness eyeAltitude skyColor fogColor frameTimeCounter frameCounter  # 加载器注入项登记。
atlasSize entityId blockEntityId biome biomeCategory biomePrecipitation  # 加载器注入项登记。
biomeTemperature biomeHumidity temperature humidity snowAccumulationHeight  # 加载器注入项登记。
customUniformTexture biome_data_0 biome_data_1 biome_data_2 biome_data_3  # 加载器注入项登记。
renderStage crimsonForestTwilightTimer customUniformModdedNoises  # 加载器注入项登记。
centerDepthSmooth previousScreenWidth previousScreenHeight playerMood  # 加载器注入项登记。
currentPlayerHealth currentPlayerHunger currentPlayerAir currentPlayerXp  # 加载器注入项登记。
texture noisetex colortex0 colortex1 colortex2 colortex3 colortex4 colortex5  # 加载器注入项登记。
colortex6 colortex7 colortex8 colortex9 colortex10 colortex11 colortex12  # 加载器注入项登记。
colortex13 colortex14 colortex15 shadowtex0 shadowtex1 shadowtex0HW shadowtex1HW  # 加载器注入项登记。
shadowcolor0 shadowcolor1 depthtex0 depthtex1 depthtex2 gdepthtex gcolor gdepth  # 加载器注入项登记。
gnormal gaux1 gaux2 gaux3 gaux4 dhDepthTex0 dhDepthTex1 dhDepthTex0trans  # 加载器注入项登记。
dhDepthTex1trans dhTexture gl_Vertex gl_MultiTexCoord0 gl_MultiTexCoord1  # 加载器注入项登记。
gl_Color gl_Normal ftransform mc_chunkFade  # 加载器注入项登记。
""".split())

# GLSL 内置变量与兼容模式老接口，同样永远可见。
GL_BUILTINS = set("""gl_Position gl_FragColor gl_FragCoord gl_FragDepth gl_VertexID  # 内置变量登记。
gl_InstanceID gl_FrontFacing gl_PointSize gl_Normal gl_ModelViewMatrix  # 内置变量登记。
gl_ProjectionMatrix gl_NormalMatrix gl_TextureMatrix gl_Color gl_SecondaryColor  # 内置变量登记。
gl_NormalScale gl_FragData gl_in gl_GlobalInvocationID gl_WorkGroupID  # 内置变量登记。
gl_WorkGroupSize gl_LocalInvocationID gl_LocalInvocationIndex EmitVertex  # 内置变量登记。
EndPrimitive gl_MultiTexCoord1 gl_TextureMatrix  # 内置变量登记。
""".split())

# 语言关键字与限定符：不参与使用检查。
KEYWORDS = set("""attribute const uniform varying if else for while do break continue  # 关键字与限定符登记。
return discard struct in out inout flat smooth noperspective centroid invariant  # 关键字与限定符登记。
precise layout location binding offset true false switch case default precision  # 关键字与限定符登记。
highp mediump lowp restrict readonly writeonly coherent volatile shared  # 关键字与限定符登记。
void bool int uint float double long short signed unsigned vec2 vec3 vec4  # 关键字与限定符登记。
ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 mat2 mat3 mat4 mat2x2  # 关键字与限定符登记。
mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 sampler1D sampler2D  # 关键字与限定符登记。
sampler3D samplerCube sampler1DArray sampler2DArray sampler2DRect samplerBuffer  # 关键字与限定符登记。
sampler2DMS sampler2DMSArray samplerCubeArray image1D image2D image3D imageCube  # 关键字与限定符登记。
imageCubeArray image2DArray image2DMS imageBuffer atomic_uint usampler1D  # 关键字与限定符登记。
usampler2D usampler3D usampler2DArray usamplerBuffer uimage1D uimage2D uimage3D  # 关键字与限定符登记。
r8 rg8 rgba8 rgba16 rgba16f rg32ui r16ui r32ui rg16 rgba32ui main triangles  # 关键字与限定符登记。
triangle_strip max_vertices local_size_x local_size_y local_size_z  # 关键字与限定符登记。
""".split())

# 内置函数全集：调用处不算未定义使用。
BUILTIN_FUNCS = set("""sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh  # 内置函数登记。
pow exp exp2 log log2 sqrt inversesqrt abs sign floor ceil trunc round roundEven  # 内置函数登记。
fract mod modf min max clamp mix step smoothstep isnan isinf any all not length  # 内置函数登记。
degrees radians  # 内置函数登记。
distance dot cross normalize faceforward reflect refract texture textureLod  # 内置函数登记。
textureOffset textureSize textureProj textureGather texelFetch texelFetchOffset  # 内置函数登记。
texture2D texture3D textureCube dFdx dFdy fwidth transpose inverse outerProduct  # 内置函数登记。
matrixCompMult frexp ldexp packUnorm2x16 unpackUnorm2x16 packUnorm4x8  # 内置函数登记。
unpackUnorm4x8 packSnorm2x16 unpackSnorm2x16 packSnorm4x8 unpackSnorm4x8  # 内置函数登记。
packHalf2x16 unpackHalf2x16 floatBitsToInt floatBitsToUint intBitsToFloat  # 内置函数登记。
uintBitsToFloat equal notEqual lessThan lessThanEqual greaterThan greaterThanEqual  # 内置函数登记。
bitfieldExtract bitfieldInsert bitfieldReverse bitCount findLSB findMSB  # 内置函数登记。
imageLoad imageStore imageSize barrier memoryBarrier groupMemoryBarrier  # 内置函数登记。
""".split())

IDENT = re.compile(r"[A-Za-z_]\w*")  # 裸标识符。
MEMBER = re.compile(r"\.\s*(\w+)")  # 成员访问：点号后面的名字不算独立标识符。


def strip_comments(text: str) -> str:  # 入口：剥注释。
    """剥掉注释并保持行号不变，供引用展开与使用检查共用。"""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)  # 块注释折成等行数空行。
    text = re.sub(r"//[^\n]*", "", text)  # 行注释直接截断。
    return text  # 剥完交回。


class Flow:  # 代码流类型。
    """展开后的代码流：按加载顺序排列的 (文件, 行号, 代码行) 三元组。"""

    def __init__(self):  # 初始化空流。
        self.lines: list[tuple[Path, int, str]] = []  # 按加载顺序存放。

    def add(self, path: Path, lineno: int, code: str) -> None:  # 追加一行代码。
        if code.strip():  # 空行不进流。
            self.lines.append((path, lineno, code))  # 登记三元组。


def expand(entry: Path) -> Flow:  # 入口：展开引用树。
    """从入口展开引用树；所有条件分支都按可达计算。

    理由：离线编译只编默认与全高两组配置，而玩家可以打开任意选项组合；
    只在其它组合下出现的未定义使用恰好是离线验证的盲区，必须全部展开。
    """
    flow = Flow()  # 输出流。
    seen: set[Path] = set()  # 引用环防护。

    def walk(path: Path) -> None:  # 单文件遍历。
        if path in seen:  # 已展开过的文件跳过。
            return  # 重复文件跳过。
        seen.add(path)  # 守卫登记。
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))  # 注释不参与扫描。
        cond_depth = 0  # 条件嵌套深度。
        for lineno, raw in enumerate(text.splitlines(), 1):  # 逐行扫描。
            stripped = raw.strip()  # 去首尾空白。
            m = INCLUDE.match(raw)  # 引用匹配。
            if m:  # 命中引用就递归展开。
                target = (SHADERS / m.group(1).lstrip("/")).resolve()  # 按加载器规则拼路径。
                if target.is_file():  # 文件存在才递归。
                    walk(target)  # 递归展开目标。
                else:  # 缺失引用登记成假声明，报告里能看到。
                    flow.add(path, lineno, f"int __missing_include_{re.sub(r'[^A-Za-z0-9_]', '_', m.group(1))};")  # 缺失引用占位。
                continue  # 处理下一行。
            if stripped.startswith("#"):  # 预处理行不进代码流。
                if re.match(r"#\s*(if|ifdef|ifndef)\b", stripped):  # 条件深度加一。
                    cond_depth += 1  # 条件深度减一。
                elif re.match(r"#\s*endif\b", stripped):  # 不越界。
                    cond_depth = max(0, cond_depth - 1)  # 预处理行跳过。
                continue  # 展开完成。
            flow.add(path, lineno, raw)  # 条件分支内的代码全部放行。

    walk(entry)  # 从入口开始走。
    return flow  # 交回代码流。


def main() -> int:  # 主函数。
    pattern = sys.argv[1] if len(sys.argv) > 1 else ""  # 可选的入口名过滤。
    macro_names: set[str] = set()  # 宏名集合。
    sources = sorted(SHADERS.rglob("*.glsl")) + sorted(p for p in SHADERS.rglob("*") if p.suffix in STAGE_SUFFIXES)  # 全部源码参与扫描。
    for path in sources:  # 全部源码都参与宏登记。
        for m in re.finditer(r"(?m)^[ \t]*#[ \t]*define[ \t]+(\w+)", path.read_text(encoding="utf-8", errors="replace")):  # 宏定义逐个提取。
            macro_names.add(m.group(1))  # 宏名入集合。

    # 声明形式：限定符或类型开头的名字登记；局部声明（类型 名字）也覆盖。
    decl_re = re.compile(  # 声明模式：限定符或类型。
        r"(?:const|uniform|flat|in|out|inout|attribute|varying|shared|precise)\s+"
        r"|(?:void|bool|int|uint|float|double|vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234](?:x[234])?"
        r"|sampler\w*|image\w*|usampler\w*|uimage\w*)\s+(\w+)\s*(\([^;{]*\))?[\s=;\[,&)]"
    )  # 结构体模式。

    struct_re = re.compile(r"^[ \t]*struct[ \t]+(\w+)")  # 结构体定义行。
    func_re = re.compile(r"^[ \t]*(?:const[ \t]+)?[\w:\[\]]+\s+(\w+)\s*\(")  # 函数定义或声明行。
    # 局部声明：行首是类型名加标识符，行尾无分号也先登记，宁可少报不误报函数体。
    local_decl = re.compile(r"^\s*(?:const\s+)?(?:vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234](?:x[234])?|float|int|uint|bool|double)\s+(\w+)\s*(?:=|;|\[|,)")  # 局部声明模式。

    problems: list[str] = []  # 收集可疑使用。
    entries = [p for p in SHADERS.rglob("*") if p.suffix in STAGE_SUFFIXES and pattern in p.name]  # 入口集合。
    for entry in sorted(entries):  # 逐入口处理。
        flow = expand(entry)  # 展开单个入口。
        declared: set[str] = set()  # 本入口可见的符号集合。
        declared |= macro_names | IRIS_BUILTINS | GL_BUILTINS | KEYWORDS | BUILTIN_FUNCS  # 预置永真符号。
        declared |= {"MC_RENDER_QUALITY", "MC_HAND_DEPTH", "MC_VERSION", "MC_GL_VERSION", "GL_RENDERER"}  # 加载器注入宏。
        declared |= {m for m in macro_names if m.startswith("MC_")}  # MC 开头的选项宏。
        absorbed: dict[int, int] = {}  # 签名吸收表：行号到吸收行数的映射。
        absorbed_range: set[int] = set()  # 被吸收的行号集合，使用检查跳过。
        for index, (path, lineno, code) in enumerate(flow.lines):  # 逐行核对。
            if index in absorbed_range:  # 被吸收行跳过。
                continue  # 已被签名吸收处理的行不再检查。
            for m in local_decl.finditer(code):  # 局部变量登记。
                declared.add(m.group(1))  # 局部变量名登记。
            for m in decl_re.finditer(code):  # 全局声明登记。
                if m.group(1):  # 类型分支带捕获组。
                    declared.add(m.group(1))  # 全局与成员声明登记。
            # 结构体类型变量：自定义类型名加标识符的声明（含带初始化的形式）。
            struct_var = re.match(r"\s*(\w+)\s+(\w+)\s*(?:=[^;]*|;)", code)  # 结构体变量模式。
            if struct_var and struct_var.group(1) not in KEYWORDS and struct_var.group(1)[0].isupper():  # 首字母大写才算自定义类型。
                declared.add(struct_var.group(1))  # 用到的结构体类型也登记。
                declared.add(struct_var.group(2))  # 变量名登记。
                declared.update(IDENT.findall(code))  # 初始化表达式里的名字也先登记，避免级联误报。
            # const 结构体常量：const 开头带构造器初始化，整行登记。
            if re.match(r"\s*const\s+\w+\s+\w+\s*=", code):  # 常量声明整行登记。
                declared.update(IDENT.findall(re.sub(r"//.*", "", code)))  # 常量名与构造器实参都登记。
            # 结构体定义行：定义本身不算使用，类型名与字段一并登记。
            if re.match(r"\s*struct\s+\w+", code):  # 结构体定义整行登记。
                declared.update(IDENT.findall(re.sub(r"//.*", "", code)))  # struct 行整行登记。
            # layout 行：整行登记，格式限定符与变量名都不算使用。
            if code.strip().startswith("layout("):  # layout 行整行登记。
                declared.update(IDENT.findall(re.sub(r"//.*", "", code)))  # layout 行标识符全部登记。
            # MC_RENDER_STAGE 宏族：加载器按绘制阶段注入，全部预登记。
            for m in re.finditer(r"MC_RENDER_STAGE_\w+", code):  # 阶段宏登记。
                declared.add(m.group(0))  # 阶段宏登记。
            # 签名吸收：函数定义行与其参数续行整行登记，参数名不算使用。
            # 为什么吸收续行：参数列表跨行时，续行里只有参数名与类型，不是使用。
            if func_re.search(code):  # 函数签名吸收。
                absorbing = True  # 进入签名吸收状态。
                cursor = index  # 从当前行向后看。
                while absorbing and cursor < len(flow.lines):  # 签名续行逐行吸收。
                    tail = flow.lines[cursor][2]  # 待吸收的行。
                    declared.update(IDENT.findall(re.sub(r"//[^\n]*", "", tail)))  # 行内标识符登记。
                    if re.search(r"[;{]\s*$", tail):  # 见到定义体或声明结束就停。
                        absorbing = False  # 定义体开始则停止。
                    elif ";" in tail and "(" not in tail and ")" not in tail:  # 无括号行句尾停止。
                        absorbing = False  # 无括号行出现句尾，视作结束。
                    cursor += 1  # 继续吸收下一行。
                for offset in range(index, cursor):  # 吸收的行号登记。
                    absorbed_range.add(offset)  # 全部续行跳过使用检查。
                continue  # 签名行跳过使用检查。
            body = MEMBER.sub("", code)  # 成员访问剥离。
            body = re.sub(r"\b\d[\d.eE+-]*\b", " ", body)  # 数字常数剔除，避免科学计数法误报。
            body = re.sub(r"0[xX][0-9a-fA-F]+[uUlL]*", " ", body)  # 十六进制常数剔除。
            for ident in IDENT.findall(body):  # 逐个标识符核对。
                if ident in declared:  # 已声明则放行。
                    continue  # 已声明项放行。
                problems.append(f"{entry.relative_to(SHADERS)} 使用 {path.relative_to(SHADERS)}:{lineno} 的 {ident} 未见声明 | {code.strip()[:90]}")
    seen: set[tuple[str, str]] = set()  # 去重键。
    unique: list[str] = []  # 每处只报第一次。
    for item in problems:  # 去重输出。
        head = item.split(" 未见声明")[0]
        where = head.split(" 使用 ")[-1].rsplit(":", 1)[0]
        ident_name = head.split(" 的 ")[-1]
        key = (where, ident_name)  # 去重键构造。
        if key in seen:  # 重复项跳过。
            continue  # 未见过的继续。
        seen.add(key)  # 键入集合。
        unique.append(item)  # 唯一项入列表。
    print("\n".join(unique[:120]) if unique else "clean")  # 只打印前一百二十条。
    print("total:", len(unique))  # 报告总数。
    return 0  # 正常结束。


if __name__ == "__main__":
    raise SystemExit(main())
