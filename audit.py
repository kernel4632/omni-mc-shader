"""源码审计：检查自有代码中文注释与未实现标记；示例 python build.py audit。

审计项目内的 Python 与 GLSL 源码，排除环境、参考、外部库与生成翻译；每个薄入口仍接受审计。
"""
from __future__ import annotations
import ast  # 只把真正文档字符串算作注释。
import io  # 将源码交给标准词法扫描。
import json  # 机器菜单说明必须是真实的结构数据。
import re  # 识别中文与未实现标记。
import tokenize  # 字符串中的井号不是注释。
from pathlib import Path  # 固定项目相对审计范围。

CHINESE = re.compile(r"[\u3400-\u9fff]")  # 不把英文标识符当中文说明。
EXCLUDED = {".git",".dev",".venv","references","libraries","vendor","dist","__pycache__"}  # 下载与第三方版权不改写。
SUFFIXES = {".py",".glsl",".vsh",".fsh",".gsh",".csh",".tcs",".tes",".properties",".yml",".yaml"}  # 自有配置也接受业务说明，生成菜单另行排除。
TERMS = set("GLSL glsl Python Iris Sodium Minecraft minecraft labPBR PBR SSR SSAO TAA FXAA GPU CPU DH OpenGL RenderDoc PresentMon JSON CSV ZIP SHA256 HTTPS API UV RGB RGBA F0 LICENSE COPYING main root final shadow deferred composite normals specular texture gtexture include define const version true false tone map sRGB blocklight skylight lab alpha dev beta rc lambda docstring properties Unlicense MIT Ashima snoise sampler2D vec2 vec3 vec4 Java Windows Linux Unicode YAML ASCII Actions data source profile options groups texcoord git add commit tag push pid PR AO shadowtex terrain gbuffers fsh GLSL330 CLI build export GGX Smith LPV setup SSBO".split())  # 只允许明确技术词与接口名，不用少数英语关键词猜自然语言。

def chinese_explanation(line: str) -> bool:
    """判断一行是否是中文说明，机器接口与可复制代码示例单独识别。"""
    text = line.strip().strip('/#*').strip().strip('"\'')  # 只移除注释和文档边界。
    text = re.sub(r"(?:\.?[\w/.-]*python(?:\.exe)?)\s+[^\u3400-\u9fff；。]+", "",text)  # 完整终端示例允许命令参数，但不会吞掉随后中文说明。
    if re.match(r"@(?:option|effect|preset)\s+",text):
        data = json.loads(text.split(" ",1)[1])  # 英文机器翻译不能伪装成普通自然语言注释。
        if not isinstance(data,dict) or not isinstance(data.get("label"),dict) or not isinstance(data["label"].get("zh_cn"),str): raise ValueError("机器说明需要中文名称对象")  # 伪造机器前缀不能绕过语言审计。
        if not CHINESE.search(data["label"]["zh_cn"]): raise ValueError("机器说明的中文名称必须包含中文")  # 豁免仅用于英文翻译，不豁免中文字段。
        for field in ("label","description"):
            if isinstance(data.get(field),dict) and isinstance(data[field].get("zh_cn"),str): chinese_explanation(data[field]["zh_cn"])  # 中文字段同样拒绝夹带英语句子。
        return True  # 菜单其余字段由选项扫描器继续检查。
    if re.fullmatch(r"(?:#?define\s+)?[A-Z][A-Z0-9_]*(?:\s+[-\d.]+)?",text) or re.fullmatch(r"RENDERTARGETS:\s*[\d, ]+",text): return False  # 原生宏和附件指令不是中文业务说明。
    text = re.sub(r"`[^`]*`|https://\S+|[\w./\\:-]+\.(?:py|glsl|vsh|fsh|csh|json|md|zip|txt|exe|properties|lang|ya?ml)\b|\b(?:effects|presets|rendering|common)/", "",text)  # 完整文件示例允许原名，普通英语句子不豁免。
    text = re.sub(r"(?:python\s+-m\s+unittest\s+discover\s+-s\s+tests|python\s+(?:build|audit|generate|check|setup|doctor|watch)|--[\w-]+(?:\s+[\w./:-]+)?)", "",text)  # 明确命令示例不是自然语言英文。
    text = re.sub(r"\b[A-Za-z_]\w*\([^\n]*?\)","",text)  # 可复制的函数调用示例不是英语句子。
    words = re.findall(r"[A-Za-z_][A-Za-z_0-9]*",text)  # 混入单个汉字也仍检查所有英文单词。
    unknown = [word for word in words if word not in TERMS and word not in {"VERSION","CHANGELOG","ROOT","STAGES","INCLUDE","UTF","BOM"} and len(word)>1 and "_" not in word and not re.search(r"[a-z][A-Z]|\d",word)]  # 标准编码术语允许原名，大写英语句子不能借此豁免。
    if unknown: raise ValueError("自然语言说明必须中文："+", ".join(unknown))  # 没有登记的英文词必须改为中文，避免漏过纯英文描述。
    return len(CHINESE.findall(text))>=4  # 至少有完整中文说明，不接受单字凑数。

def comments(source: Path) -> tuple[set[int], list[tuple[int,str]]]:
    """解析真实注释和文档块，返回有效中文行与说明片段。"""
    text = source.read_text(encoding="utf-8")  # 审计实际源文件，不读生成报告。
    parts = []  # 保留片段原始行号用于报错。
    if source.suffix==".py":  # Python 使用标准词法与语法，避免把字符串算注释。
        tree = ast.parse(text)  # 无法解析的代码也不能通过审计。
        for node in ast.walk(tree):  # 只有模块、类、函数开头的说明是文档字符串。
            if isinstance(node,(ast.Module,ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef)) and node.body and isinstance(node.body[0],ast.Expr) and isinstance(node.body[0].value,ast.Constant) and isinstance(node.body[0].value.value,str):
                value = node.body[0].value  # 接口文档位置来自实际语法树。
                parts.append((value.lineno,ast.get_source_segment(text,value)))  # 仅接口文档字符串。
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type==tokenize.COMMENT: parts.append((token.start[0],token.string))  # 排除普通字符串中的中文。
    elif source.suffix in {".properties",".yml",".yaml",".lang"}:
        pattern = re.compile(r'"(?:\\.|[^"\\])*"|\x27(?:\x27\x27|[^\x27])*\x27|#[^\n]*',re.DOTALL)  # 字符串中的井号不计，YAML尾随说明仍是有效业务注释。
        for match in pattern.finditer(text):
            if match[0].startswith("#"): parts.append((text[:match.start()].count("\n")+1,match[0]))
    else:
        pattern = re.compile(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',re.DOTALL)  # 字符串、块注释与尾注分别识别。
        for match in pattern.finditer(text):
            if match[0].startswith(("//","/*")): parts.append((text[:match.start()].count("\n")+1,match[0]))
    lines = set()  # 同一行有多个中文片段也只算一次。
    for begin, part in parts:
        # 菜单中的中文名称与帮助属于有效接口说明，英文机器翻译不接受自然语言审计。
        for offset,line in enumerate(part.splitlines()):  # 块注释按真正带中文的非空行统计。
            try:
                if chinese_explanation(line): lines.add(begin+offset)  # 只有真实中文说明进入比例分子。
            except ValueError:
                pass  # 统一检查阶段报告原始文件与行号，失败注释不计入比例。
    return lines,parts

def check(root: Path) -> list[dict]:
    """拒绝注释不足与未实现标记，报告每个文件真实比例。"""
    result, errors = [],[]  # 汇总全部失败位置，接手者不用逐个重跑。
    for source in sorted(root.rglob("*")):
        relative_path = source.relative_to(root).as_posix()
        if not source.is_file() or source.suffix not in SUFFIXES or EXCLUDED.intersection(source.relative_to(root).parts) or relative_path=="shaders/shaders.properties": continue
        nonempty = {i for i,line in enumerate(source.read_text(encoding="utf-8").splitlines(),1) if line.strip()}  # 不把空行当分母。
        commented,parts = comments(source)
        ratio = len(commented & nonempty)/max(len(nonempty),1)  # 尾注代码行同时贡献分子与分母。
        relative = source.relative_to(root).as_posix()  # 报告不暴露本机绝对路径。
        result.append({"file":relative,"nonempty":len(nonempty),"chineseCommentLines":len(commented & nonempty),"ratio":ratio})
        if ratio<0.5: errors.append(f"{relative}：中文有效注释 {ratio:.1%}，至少需要 50%")
        for line,part in parts:
            if part.lstrip().startswith(("// @option ","// @effect ")):
                try: chinese_explanation(part)
                except (ValueError,TypeError) as error: errors.append(f"{relative}:{line}：机器说明无效：{error}")
                continue  # 只对合法机器说明豁免英文翻译。
            if re.search(r"\b(?:TODO|FIXME)\b|待实现|尚未实现|未接入的占位",part): errors.append(f"{relative}:{line}：存在未实现标记")  # 检查维护者真实说明。
            for offset,text in enumerate(part.splitlines()):
                try: chinese_explanation(text)
                except ValueError as error: errors.append(f"{relative}:{line+offset}：{error}")  # 中英混合和纯英文说明使用同一严格规则。
    if errors: raise ValueError("源码审计失败\n"+"\n".join(errors))
    return result

def generated_comments(path: Path, content: str) -> None:
    """检查机器生成说明的真实语言，解码中文转义但不要求菜单数据凑注释比例。"""
    for number,line in enumerate(content.splitlines(),1):
        if not line.lstrip().startswith("#"): continue  # 菜单值和英文翻译不是注释。
        decoded = re.sub(r"\\u([0-9a-fA-F]{4})",lambda match:chr(int(match[1],16)),line)  # 只还原Unicode中文，不修改代码示例中的反斜杠。
        if not chinese_explanation(decoded): raise ValueError(f"{path}:{number}：生成说明必须是有效中文")  # 生成器不能豁免英语说明要求。
