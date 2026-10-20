"""选项菜单：从效果源码的原生声明生成菜单、翻译和可迁移预设。

调用位置：`build.py` 调用 `scan`、`presets` 和 `generated` 生成菜单；`config.py` 的
配置读写复用这里的 `unique_object` 与 `read_properties` 两个配置读取器。
可复制示例：`options.scan(build.SHADERS)` 读取选项，`options.generated(shaders, found, groups, profiles)` 生成菜单内容。
设计取舍：源码中直接交给加载器的宏声明 `#define`、常量声明 `const` 和旁边的 `@option`
说明是唯一来源；常量仅扫描加载器明确支持的名称，工具不另存默认值。
分享配置的读写、版本格式和命令入口都在 `config.py`，本文件只负责从源码生成菜单，两者都不手工维护产物。
菜单把十五种效果文件夹收进九个顶层页：`GROUP_PAGES` 只决定入口，效果文件夹仍决定子页面标题；
快速设置页重复展示常用选项，不改变归属、默认值和配置文件；关于页平铺调试开关，不新增配置键。
"""

from __future__ import annotations

import json  # 读取选项旁的机器说明。
import re  # 检查选项名称与数值格式。
from dataclasses import dataclass, field  # 保存已检查的选项数据。
from pathlib import Path  # 效果源码与预设路径。
import config  # 配置读取器与分享格式在配置模块里只维护一份。

LOCALES = ("zh_cn", "en_us")  # 菜单同时支持中文与英文玩家。
NAME = re.compile(r"[A-Z][A-Z0-9_]*\Z")  # 接口名称保持加载器可识别。
NUMBER = re.compile(  # 原生数值范围不允许任意表达式，只接受数字字面量。
    r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\Z"
)
DEFINE = re.compile(  # 注释标记、名字、数值和范围分别保留，才能区分关闭开关与数值选项。
    r"\s*(//\s*)?#define\s+(\w+)(?:\s+([^/\s]+))?\s*"
    r"(?://\s*\[([^]]+)\])?\s*$"
)
CONST = re.compile(  # 只读取声明中的类型和字面量，不求值任意源码表达式。
    r"\s*const\s+(int|float)\s+(\w+)\s*=\s*([^;\s]+)\s*;\s*"
    r"//\s*\[([^]]+)\]\s*$"
)  # Iris原生常量菜单需要字面量范围。
CONST_OPTIONS = {  # 只允许加载器真正认识的原生常量，避免生成无效菜单。
    "shadowMapResolution": "int",
    "shadowDistance": "float",
    "sunPathRotation": "float",
    "wetnessHalflife": "float",
    "drynessHalflife": "float",
}


@dataclass(frozen=True)
class Option:
    """已检查的游戏选项，`source` 指向唯一的原生定义。

    这个对象把菜单需要的文字和加载器需要的取值放在一起，避免生成阶段再次猜测
    默认值或范围；`declaration` 只用于说明它来自宏还是受支持的原生常量。
    """

    name: str  # 对玩家稳定的选项名称。
    default: str  # 唯一原生定义读取的默认值。
    values: tuple[str, ...]  # 原生范围中的合法取值。
    label: dict[str, str]  # 菜单名称翻译。
    description: dict[str, str]  # 画面影响与依赖说明。
    slider: bool  # 数值是否用滑块显示。
    group: str  # 文件位置决定菜单分组。
    source: Path  # 定义来源用于可读错误。
    line: int  # 原始源文件行号。
    declaration: str = "define"  # 选项来自普通宏还是加载器支持的原生常量。
    page: str = ""  # 可选的菜单页面覆盖；空表示按效果文件位置映射到页面。
    valueLabels: dict[str, dict[str, str]] = field(default_factory=dict)  # 档位取值的玩家可读名称，从源码旁读取。


# 页面顺序就是玩家打开菜单时看到的按钮顺序。
# 关于页集中放调试开关和标题开关，不再单独设开发者页。
# 快速设置没有独立选项，避免同一配置出现两个默认值来源。
# 预设按钮由生成器放在快速设置页最前面，切换预设仍然一次写入全部选项。
# 玩家分享的配置文件只按选项名匹配，因此这次只移动菜单位置，不改写任何旧设置。
# 主界面分类：顺序即菜单里的按钮顺序，`id` 用于 `screen.<ID>` 键名。
MAIN_PAGES: list[tuple[str, dict[str, str]]] = [
    ("quick", {"zh_cn": "快速设置", "en_us": "Quick setup"}),
    ("sky", {"zh_cn": "天空", "en_us": "Sky"}),
    ("cloudfog", {"zh_cn": "云与雾", "en_us": "Clouds & fog"}),
    ("waterground", {"zh_cn": "水与地面", "en_us": "Water & ground"}),
    ("lightshadow", {"zh_cn": "光照与阴影", "en_us": "Light & shadow"}),
    ("camera", {"zh_cn": "画面与镜头", "en_us": "Image & camera"}),
    ("weather", {"zh_cn": "天气与季节", "en_us": "Weather & seasons"}),
    ("world", {"zh_cn": "世界与远景", "en_us": "World & distance"}),
    ("about", {"zh_cn": "关于与调试", "en_us": "About & debug"}),
]  # 封面分类只在一处定义，菜单与翻译都从这里取。

# 顶层分页只改菜单入口，不改效果文件位置、选项名称或已有配置。
# 九个入口覆盖全部效果，快速设置只提供常用选项的第二个入口。
# 文件夹仍是最小效果单位，子页面标题继续用效果自己的名称。
# 旧配置按选项名读取，换页不会让玩家已有设置失效。
# 效果文件夹到主页面的归属：文件夹仍决定子页面标题，页面只决定顶层入口。
# 这样顶层保持九页，效果文件不必为了分页而搬家，已有子页面名称也不变。
GROUP_PAGES: dict[str, str] = {
    "sky": "sky",
    "cloud": "cloudfog",
    "fog": "cloudfog",
    "water": "waterground",
    "ground": "waterground",
    "lighting": "lightshadow",
    "shadow": "lightshadow",
    "reflection": "lightshadow",
    "color": "camera",
    "lens": "camera",
    "clarity": "camera",
    "entity": "camera",
    "weather": "weather",
    "world": "world",
    "dev": "about",
}  # 十五种效果文件夹归入九个主页面，不设“高级”总入口。

# 快速设置页的快捷入口：只重复展示常用选项，不改变选项归属、默认值或配置文件。
# 同一选项仍保留在所属效果的子页面里，删除或改名这里不会删除任何选项。
QUICK_OPTIONS: tuple[str, ...] = (
    "OMNI_VOLUMETRIC_CLOUDS",
    "OMNI_CLOUD_QUALITY",
    "OMNI_VFOG",
    "OMNI_VFOG_QUALITY",
    "OMNI_WATER_PARALLAX",
    "OMNI_UNDERWATER_FOG",
    "OMNI_VARIABLE_PENUMBRA_SHADOWS",
    "OMNI_GTAO",
    "OMNI_MANUAL_EXPOSURE",
    "OMNI_AE_OFFSET",
)  # 预设按钮由生成器加在这一页最前面。


@dataclass(frozen=True)
class Preset:
    """已检查的共享配置，文件名决定菜单中的预设名称。

    `values` 已经补齐所有选项，因此切换风格时会完整替换旧值，不会留下上一个预设的效果。
    """

    name: str  # 文件名就是共享配置名称。
    label: dict[str, str]  # 预设菜单翻译。
    values: dict[str, str]  # 完整配置保证切换不残留旧值。


def metadata(text: str, location: str, allowed: set[str]) -> dict:
    """检查菜单说明的字段与翻译，并保留原始位置用于报错。

    输入边界：`text` 必须是效果源码或预设旁边的一段 `JSON`，字段只能来自 `allowed`。
    单源原因：菜单名称和帮助文字只从源码旁边读取，不在生成器中复制第二份。
    """
    data = json.loads(  # 用户写入的机器说明在边界检查一次。
        text, object_pairs_hook=config.unique_object
    )
    if not isinstance(data, dict) or set(data) - allowed:  # 说明必须是对象，且只含允许字段。
        raise ValueError(f"{location}：说明必须是对象，且只能含 {sorted(allowed)}")
    for field in ("label", "description"):  # 名称必填，帮助说明可选。
        if field not in data and field == "description":  # 菜单帮助可以省略，名称必须提供。
            continue  # 未提供的帮助不会生成空说明。
        translations = data.get(field)  # 两种语言必须来自同一条说明。
        if not isinstance(translations, dict) or set(translations) != set(LOCALES):
            raise ValueError(f"{location}：{field} 必须同时提供 zh_cn 和 en_us")
        if any(
            not isinstance(value, str)
            or not value.strip()
            or "\n" in value
            or "\r" in value
            for value in translations.values()
        ):
            raise ValueError(f"{location}：翻译必须是非空单行文字")
    if "slider" in data and not isinstance(data["slider"], bool):  # 滑块不能被文字真假值误启用。
        raise ValueError(f"{location}：slider 必须为 true 或 false")
    if "values" in data:  # 档位名称让按钮显示的取值变成玩家能看懂的词。
        mapping = data["values"]
        valid = (isinstance(mapping, dict) and mapping
                 and all(isinstance(key, str) for key in mapping)
                 and all(isinstance(text, dict) and set(text) == set(LOCALES)
                         and all(isinstance(value, str) and value.strip() and "\n" not in value and "\r" not in value
                                 for value in text.values())
                         for text in mapping.values()))
        if not valid:  # 档位名称结构不合格时拒绝生成菜单。
            raise ValueError(f"{location}：values 必须是取值到双语单行名称的映射")
    return data  # 下游信任已检查的字段。


def scan(shaders: Path) -> tuple[dict[str, Option], dict[str, dict[str, str]]]:
    """扫描效果源码，返回选项和菜单分组。

    输入边界：`shaders` 必须指向包含 `effects/` 的光影源码目录；源码中的
    `@option` 下一行必须是原生 `#define` 或加载器白名单内的原生 `const`。
    单源原因：默认值和合法范围直接来自加载器会看到的声明，不能在工具中再维护一份。
    """
    options: dict[str, Option] = {}  # 效果源码是默认值唯一来源。
    groups: dict[str, dict[str, str]] = {}  # 文件主体自动形成菜单。
    for source in sorted((shaders / "effects").rglob("*.glsl")):  # 文件新增后自动登记，不改中央表。
        group = source.relative_to(shaders / "effects").with_suffix("").as_posix()  # 效果名称是“文件夹/文件”，文件夹按主页面命名。
        if not all(re.fullmatch(r"[a-z][a-z0-9_]*", part) for part in group.split("/")):
            raise ValueError(f"{source}：效果名称每段只能使用小写英文、数字和下划线")
        lines = source.read_text(encoding="utf-8").splitlines()  # 保留原始行号便于定位错误。
        for index, line in enumerate(lines):  # 逐行读取说明与紧随其后的声明。
            stripped = line.strip()  # 说明允许缩进但不允许跨行。
            if stripped.startswith("// @effect "):  # 每个效果提供自己的菜单标题。
                data = metadata(stripped.removeprefix("// @effect "), str(source), {"label"})
                if group in groups and groups[group] != data["label"]:
                    raise ValueError(f"{source}：同一效果出现不同菜单名称")
                groups[group] = data["label"]  # 同一效果只维护一个菜单名称。
            if not stripped.startswith("// @option "):
                continue  # 普通业务注释不参与菜单生成。
            # 单项解析检查声明及已有名称；扫描主线负责按文件顺序登记结果。
            option = _read_option(source, lines, index, group, options)
            options[option.name] = option  # 后续菜单和预设共同使用这份已检查数据。
    for option in options.values():  # 菜单分组不能没有玩家看得懂的名称。
        if option.group not in groups:
            raise ValueError(f"{option.source}：有选项的效果需要 // @effect 菜单名称")
    return options, groups  # 新效果只需新增主体文件。


def _read_option(source: Path, lines: list[str], index: int, group: str,
                 options: dict[str, Option]) -> Option:
    """把一条源码说明和紧邻的原生声明读成游戏选项。

    `index` 指向已识别的说明行；不向后搜索声明，以免把说明错配给后面的另一个选项。
    此处检查源码提供的名字、范围和默认值；用扫描主线传来的已有名称拒绝跨文件重名。
    重名检查仍放在范围检查之前，保留同时出错时原有的报错顺序。
    """
    location = f"{source}:{index + 1}"  # 说明行报格式错误，定义行保存在返回对象中。
    data = metadata(
        lines[index].strip().removeprefix("// @option "), location,
        {"label", "description", "slider", "page", "values"},
    )  # 菜单文字、滑块要求、页面覆盖与档位名称只读取这一条源码说明。
    if "page" in data and not re.fullmatch(r"[a-z][a-z0-9_]*", data["page"]):  # 页面名用于加载器键名，必须是小写标识。
        raise ValueError(f"{location}：page 只能使用小写英文、数字和下划线")
    line = lines[index + 1] if index + 1 < len(lines) else ""  # 文件末尾没有声明时按相邻格式错误处理。
    definition = DEFINE.fullmatch(line)  # 原生宏允许无数值开关以及带范围的数字。
    constant = CONST.fullmatch(line)  # 常量必须带类型、默认值和明确范围。
    if definition is None and constant is None:  # 说明下一行必须是受支持的原生声明。
        raise ValueError(f"{location}：@option 下一行必须是原生 #define 或受支持的 const 选项")
    declaration = "define"  # 保留对外数据中区分宏和常量的原有字段值。
    if constant:
        declaration, name, default, values = constant.groups()  # 加载器直接识别常量声明，不能用宏替换。
        if CONST_OPTIONS.get(name) != declaration:
            raise ValueError(f"{location}：Iris不支持这个const选项名称或类型")
        if declaration == "int" and not all(re.fullmatch(r"\d+", value) for value in values.split()):
            raise ValueError(f"{location}：整数const范围必须是整数字面量")
        if declaration == "float" and not all(NUMBER.fullmatch(value) for value in values.split()):
            raise ValueError(f"{location}：浮点const范围必须是数字字面量")
        commented = None  # 常量没有通过注释表达关闭状态的语法。
    else:
        commented, name, default, values = definition.groups()  # 注释宏与无值宏共同决定开关默认状态。
    if not constant and (not NAME.fullmatch(name) or name in options):  # 宏名规则不套在加载器固定的常量名上。
        raise ValueError(f"{location}：选项名称无效或重复：{name}")
    if constant and name in options:  # 一个名字只能对应一处默认值，不让后面的文件覆盖它。
        raise ValueError(f"{location}：选项名称重复：{name}")
    choices = tuple(values.split()) if values else ("false", "true")  # 范围文字原样保留，不把浮点值重新格式化。
    if default is None:  # 无数值宏按是否被注释表示开关。
        default = "false" if commented else "true"  # 无数值宏按是否被注释表示开关，范围不能伪造布尔类型。
        if values or data.get("slider", False):
            raise ValueError(f"{location}：布尔开关不能声明数值范围或滑块")
    elif (not constant and (commented or not values)) or not all(NUMBER.fullmatch(value) for value in choices):
        raise ValueError(f"{location}：数值选项必须启用定义并提供数字范围")
    if default not in choices or len(set(choices)) != len(choices):  # 默认值必须在范围内且取值不重复。
        raise ValueError(f"{location}：默认值不在范围内，或范围含重复值")
    valueLabels = data.get("values", {})  # 档位名称必须对应真实取值，避免菜单写出用不到的按钮文字。
    if any(key not in choices for key in valueLabels):  # 档位名称必须对应真实取值。
        raise ValueError(f"{location}：values 里的名字必须来自声明的数值范围")
    return Option(
        name, default, choices, data["label"], data.get("description", {}),
        data.get("slider", False), group, source, index + 2, declaration, data.get("page", ""), valueLabels,
    )  # 返回同时包含菜单文字和原生取值的数据，不再另存一份默认值。


def read_pipeline(source: Path) -> dict[str, str]:
    """读取绘制设置，允许同一个键出现在互斥的条件分支里。

    输入边界：`rendering/pipeline.properties` 由维护者编写，可以用 `#if`、`#ifdef`、`#elif`、
    `#else`、`#endif` 按选项挑选设置，加载器会按玩家选项只保留一支。
    检查规则：同一个键在同一分支、或在任何条件之外出现两次都报错；只有不同分支各写一次才允许。
    返回值只用于检查禁止的键，生成时逐行照原样写出，不靠这里的字典决定取哪一支。
    """
    seen: dict[str, list[tuple]] = {}  # 键名到它出现过的分支路径。
    stack: list[list[int]] = []  # 每层条件块记录自身编号和当前分支序号。
    blocks = 0  # 条件块编号，区分前后两个互不相干的块。
    result = {}  # 只用于检查同名设置是否冲突，不决定取哪一支。
    for index, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):  # 逐行读取设置与条件分支。
        stripped = line.strip()
        directive = re.match(r"#\s*(if|ifdef|ifndef|elif|else|endif)\b", stripped)  # 条件指令只维护分支路径。
        if directive:
            word = directive[1]
            if word in ("if", "ifdef", "ifndef"):
                blocks += 1
                stack.append([blocks, 0])  # 新块从第零支开始。
            elif not stack:
                raise ValueError(f"{source}:{index}：条件指令没有对应的开头")
            elif word in ("elif", "else"):
                stack[-1][1] += 1  # 同一块换到下一支。
            else:
                stack.pop()
            continue
        if not stripped or stripped.startswith(("#", "!")):
            continue  # 空行与说明不影响设置。
        key, separator, value = stripped.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or not key or stripped.endswith("\\"):
            raise ValueError(f"{source}:{index}：需要单行 key=value")
        path = tuple(tuple(level) for level in stack)  # 这一行所在的分支路径。
        for other in seen.get(key, []):
            exclusive = any(a[0] == b[0] and a[1] != b[1] for a, b in zip(path, other))  # 同一块的不同分支才互斥。
            if not exclusive:
                raise ValueError(f"{source}:{index}：{key} 在可能同时生效的位置重复定义")
        seen.setdefault(key, []).append(path)
        result[key] = value
    if stack:
        raise ValueError(f"{source}：条件指令缺少结尾")
    return result


def presets(folder: Path, options: dict[str, Option]) -> list[Preset]:
    """收集预设并补齐默认值。

    输入边界：`folder` 中的每个 `.properties` 必须有一条 `@preset` 说明，且每个值都在
    `options` 的真实范围内；内部调用者传入的 `options` 已由 `scan` 检查。
    单源原因：预设只保存要改变的值，缺少的值从原生声明读取，切换预设时再生成完整配置，
    这样不会把上一套风格遗留到下一套配置中。
    """
    result = []  # 自动登记可分享配置。
    for source in sorted(folder.glob("*.properties")):  # 固定预设顺序便于可重复生成。
        if not re.fullmatch(r"[a-z][a-z0-9_]*", source.stem):
            raise ValueError(f"{source}：预设名称只能使用小写英文、数字和下划线")
        labels = [line.removeprefix("# @preset ") for line in
                  source.read_text(encoding="utf-8").splitlines() if line.startswith("# @preset ")]
        if len(labels) != 1:
            raise ValueError(f"{source}：需要一条 # @preset 菜单说明")
        label = metadata(labels[0], str(source), {"label"})["label"]  # 外部预设说明同样检查翻译。
        changes = config.read_properties(source)  # 预设同样经过配置边界检查。
        for name, value in changes.items():  # 玩家分享的取值必须属于真实选项范围。
            if name not in options or value not in options[name].values:
                raise ValueError(f"{source}：未知选项或无效取值：{name}={value}")
        values = {name: changes.get(name, option.default) for name, option in options.items()}  # 每套补齐全部值。
        result.append(Preset(source.stem, label, values))  # 文件名直接登记。
    return result


def profile_values(values: dict[str, str], options: dict[str, Option]) -> str:
    """将已检查的完整配置写成加载器原生的 `profile` 设置。

    输入边界：`values` 必须已通过 `presets` 或 `shared` 的选项范围检查，不能在这里静默补值。
    格式取舍：布尔关闭使用加载器的 `!NAME` 语法，数值保留原生文字，避免生成另一套配置规则。
    """
    entries = []  # 转换为加载器原生预设语法。
    for name, value in values.items():  # 完整配置写入每个原生选项。
        if options[name].values == ("false", "true"):
            entries.append(name if value == "true" else "!" + name)  # 布尔关闭使用加载器原生否定。
        else:
            entries.append(f"{name}={value}")  # 数值保留原生字符串。
    return " ".join(entries)


def page_of(option: Option) -> str:
    """返回选项所属的主页面名称。

    优先用 `@option` 声明的 `page`；否则按效果文件夹查 `GROUP_PAGES`。
    文件夹仍是效果分组与子页面标题的唯一来源，`GROUP_PAGES` 只决定它落在哪个顶层入口；
    都不匹配时直接报错，避免选项悄悄消失或落到错误分类里。
    """
    if option.page:
        return option.page  # 单个选项可覆盖所在效果的默认页面。
    folder = option.group.split("/")[0]  # 效果分组是“文件夹/文件”，文件夹就是效果名。
    if folder in GROUP_PAGES:
        return GROUP_PAGES[folder]  # 文件夹归入九页之一，不再要求文件夹名等于页面名。
    raise ValueError(f"{option.source}：效果 {option.group} 没有登记主页面")


def _subpages(pages: dict[str, list[str]], options: dict[str, Option]) -> dict[str, dict[str, list[str]]]:
    """把每个分类里的选项按效果折叠成子页面。

    一个分类只来自一个效果文件时返回空，菜单保持平铺；来自多个效果时才建子页面，
    这样玩家先选分类、再选效果，长列表不会一次摊开。子页面名称直接复用效果自己的标题。
    快速设置与关于页保持平铺：它们本来就是少量快捷入口和调试开关，再折一层只会多点一次。
    """
    result: dict[str, dict[str, list[str]]] = {}
    for pid, names in pages.items():
        if pid in {"quick", "about"}:  # 这两页故意平铺，不按效果再分组。
            continue
        by_group: dict[str, list[str]] = {}
        for name in names:
            by_group.setdefault(options[name].group, []).append(name)  # 同一效果的选项归到一起。
        if len(by_group) > 1:
            result[pid] = by_group
    return result


def generated(shaders: Path, options: dict[str, Option], groups: dict,
              profiles: list[Preset]) -> dict[Path, str]:
    """从效果源码和预设生成菜单、滑块、预设及翻译文件内容。

    输入边界：`options`、`groups` 和 `profiles` 必须来自本文件的扫描结果；`shaders` 中的
    `rendering/pipeline.properties` 只能保存绘制流程设置，不能重复声明菜单内容。
    单源原因：返回待写入内容而不是直接写盘，调用方可以先比较结果；菜单和翻译始终从同一批
    效果说明生成，避免手工同步遗漏。
    """
    pipeline = shaders / "rendering/pipeline.properties"  # 绘制设置只有一个维护文件。
    settings = read_pipeline(pipeline)  # 条件分支里的同名设置由加载器按选项挑选，这里只检查是否互斥。
    if any(key == "sliders" or key.startswith(("screen", "profile.")) for key in settings):
        raise ValueError(f"{pipeline}：菜单、滑块和预设由工具生成，不能重复维护")
    lines = ["# \\u7531 build.py \\u751f\\u6210\\uff1b\\u8bf7\\u4fee\\u6539 effects/\\u3001presets/ \\u6216 rendering/pipeline.properties \\u540e\\u91cd\\u65b0\\u751f\\u6210\\u3002"]  # 转义中文提示，保持生成文件的加载器编码。
    for line in pipeline.read_text(encoding="utf-8").splitlines():  # 保留流程设置原有顺序、条件分支和说明，便于追溯来源。
        if line.strip().startswith("#"):
            lines.append(line.strip().encode("ascii","backslashreplace").decode("ascii"))  # 保留中文说明与条件指令，并转成兼容编码。
        elif line.strip():
            key, _, value = line.partition("=")  # 每行按自己的值写出，不同分支的同名设置互不覆盖。
            lines.append(f"{key.strip()} = {value.strip()}")
    pages: dict[str, list[str]] = {}  # 页面名到选项名，顺序沿用源码扫描顺序。
    for option in options.values():
        pages.setdefault(page_of(option), []).append(option.name)  # 每个选项只落在一个页面。
    if sum(len(names) for names in pages.values()) != len(options):  # 自检：不允许漏项或重复登记。
        raise ValueError("菜单页面没有覆盖全部选项")
    quick: list[str] = []  # 快速设置页只放快捷入口，选项仍留在自己的效果页。
    for name in QUICK_OPTIONS:  # 快捷入口必须指向真实选项，拼写错误直接报出来。
        if name not in options:
            raise ValueError(f"快速设置引用了不存在的选项：{name}")
        if name in quick:
            raise ValueError(f"快速设置重复引用选项：{name}")
        quick.append(name)
    ordered = [pid for pid, _ in MAIN_PAGES if pid in pages and pid != "quick"]  # 页面顺序由主界面定义决定。
    unknown = set(pages) - {pid for pid, _ in MAIN_PAGES}  # 未登记页面说明映射遗漏。
    if unknown:
        raise ValueError(f"未登记的菜单页面：{sorted(unknown)}")
    top = [f"[{pid.upper()}]" for pid in ordered]  # 九个顶层入口里的八个效果页。
    if quick:  # 有快捷入口时把它放第一个，预设按钮也收进这一页。
        top.insert(0, "[QUICK]")
    elif profiles:  # 没有快速页时保持原有预设入口。
        top.insert(0, "<profile>")
    lines += ["", "screen = " + " ".join(top)]  # 顶层只列九个分类，不再平铺选项。
    if quick:  # 快速设置页：预设加一组常用选项，全部复用原选项。
        entries = (["<profile>"] if profiles else []) + quick
        lines.append("screen.QUICK = " + " ".join(entries))  # 预设放在最前，后面是快捷选项。
        lines.append("screen.QUICK.columns = 3")  # 与效果页一致的三栏排布。
    subpages = _subpages(pages, options)  # 一个分类里出现多个效果时，各效果折叠成子页面，菜单仍然一眼看到分类。
    for pid in ordered:  # 每页列出自己的子页面或直接平铺选项，并固定三栏。
        if pid in subpages:
            buttons = []  # 这一页只放子页面入口，顺序沿用源码扫描顺序。
            for group in subpages[pid]:
                sub = f"{pid.upper()}_{group.replace('/', '_').upper()}"  # 子页名带分类前缀，并用下划线替换路径分隔符，避免不同分类的同名效果互相覆盖。
                buttons.append(f"[{sub}]")  # 子页面以方括号按钮出现，点击进入。
                lines.append(f"screen.{sub} = " + " ".join(subpages[pid][group]))  # 子页面内的选项归属唯一。
                lines.append(f"screen.{sub}.columns = 3")  # 子页面同样三栏。
            lines.append(f"screen.{pid.upper()} = " + " ".join(buttons))  # 分类页只承担分组，不再平铺长列表。
        else:
            lines.append(f"screen.{pid.upper()} = " + " ".join(pages[pid]))  # 只有一个效果时不必多一层，直接平铺。
        lines.append(f"screen.{pid.upper()}.columns = 3")  # 多栏排布，利用横向空间。
    sliders = [option.name for option in options.values() if option.slider]  # 滑块自动从效果说明读取。
    if sliders:
        lines.append("sliders = " + " ".join(sliders))  # 没有滑块时省略设置，不额外生成空菜单项。
    for preset in profiles:  # 玩家选择预设时设置所有参数，不保留旧风格。
        lines.append(f"profile.{preset.name} = {profile_values(preset.values, options)}")
    files = {shaders / "shaders.properties": "\n".join(lines) + "\n"}  # 返回内容由构建统一写入。
    for locale in LOCALES:  # 两套翻译由同一源同步生成，不在语言文件里手工维护第二份。
        files[shaders / "lang" / f"{locale}.lang"] = _language(options, groups, profiles, locale)
    return files  # 检查命令可直接对比，无需先覆盖旧文件。


def _language(options: dict[str, Option], groups: dict, profiles: list[Preset], locale: str) -> str:
    """生成一种语言的完整菜单文字，和菜单设置共用同一批扫描结果。

    内部数据已在说明读取处检查；这里仅按加载器要求写键名并转义文字，不再检查翻译完整性。
    """
    lines = ["# \\u7531 build.py \\u751f\\u6210\\uff1b\\u7ffb\\u8bd1\\u4f4d\\u4e8e effects/ \\u4e0e presets/ \\u65c1\\u8fb9\\u3002"]  # 保留生成提示，说明翻译应回到源码修改。
    pages: dict[str, list[str]] = {}  # 与菜单设置用同一份归属，避免语言文件出现菜单里没有的页面。
    for option in options.values():
        pages.setdefault(page_of(option), []).append(option.name)
    for pid, label in MAIN_PAGES:  # 页面顺序与菜单一致，跨系统生成时不产生无意义差异。
        if pid == "quick":  # 快速设置页没有自己的选项，只要配了快捷入口就显示。
            if QUICK_OPTIONS:
                lines.append(f"screen.QUICK={escape(label[locale])}")
            continue
        if pid in pages:  # 只输出真正有选项的页面。
            lines.append(f"screen.{pid.upper()}={escape(label[locale])}")
    for pid, by_group in _subpages(pages, options).items():  # 子页面标题直接复用效果自己的名称。
        for group in by_group:
            lines.append(f"screen.{pid.upper()}_{group.replace('/', '_').upper()}={escape(groups[group][locale])}")
    for option in options.values():  # 选项标题与帮助使用相同语言，避免混用另一套翻译。
        lines.append(f"option.{option.name}={escape(option.label[locale])}")
        if option.description:  # 没有帮助内容时不生成空白提示。
            lines.append(f"option.{option.name}.comment={escape(option.description[locale])}")
        for value, text in option.valueLabels.items():  # 档位按钮显示玩家能看懂的取值名称。
            lines.append(f"value.{option.name}.{value}={escape(text[locale])}")
    for preset in profiles:  # 预设名来自文件名，显示文字来自该文件的预设说明。
        lines.append(f"profile.{preset.name}={escape(preset.label[locale])}")
    return "\n".join(lines) + "\n"  # 末尾换行与菜单文件一致，保持生成内容稳定。


def escape(text: str) -> str:
    """把已检查的菜单文字转成加载器可读取的属性值。

    先保护反斜杠、等号和冒号，避免说明文字变成键值语法；再把中文转成兼容编码的转义表示。
    这里只转换表示方式，不修改玩家看到的文字含义，也不再次检查内部翻译数据。
    """
    text = text.replace("\\", "\\\\").replace("=", "\\=").replace(":", "\\:")  # 不让说明改变属性语法。
    return text.encode("ascii", "backslashreplace").decode("ascii")  # 加载器读取兼容的转义中文。
