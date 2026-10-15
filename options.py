"""选项与分享配置：从效果源码生成菜单、翻译和可迁移配置。

调用位置：`build.py` 调用 `scan`、`presets` 和 `generated` 生成菜单；
`options.py` 自己的命令入口负责导入、导出、对比和重置配置。
可复制示例：`python options.py export --input .dev/config/user.json --output .dev/config/share.json --format json`。
设计取舍：源码中直接交给加载器的宏声明 `#define`、常量声明 `const` 和旁边的 `@option`
说明是唯一来源；常量仅扫描加载器明确支持的名称，工具不另存默认值。
加载器 `properties` 是单行键值格式，分享 `JSON` 是带字段结构并携带格式与版本的数据，
因此两者只在明确的导入、导出边界转换。未知选项和重复字段直接报错，避免分享者不知道配置已经丢失。
"""

from __future__ import annotations

import argparse  # 配置分享命令入口。
import json  # 读取受控配置与机器说明。
import re  # 检查选项名称与数值格式。
import sys  # 唯一入口报告错误。
from dataclasses import dataclass  # 保存已检查的选项数据。
from pathlib import Path  # 所有用户输出限制在开发目录。
import paths  # 开发目录写入边界在专用模块里只检查一次。

LOCALES = ("zh_cn", "en_us")  # 菜单同时支持中文与英文玩家。
SHARE_SCHEMA = 2  # JSON分享与打包清单共用这一个格式版本。
LEGACY_VERSION = "0.0.0-dev.3"  # 旧配置格式只描述效果开发前的调试选项。
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
}
OPTION_RENAMES = {  # 保留历史名称对照；当前导入不使用此表，不会自动接受或改写旧名称。
    "OMNI_SHADOW_RESOLUTION": "shadowMapResolution",
    "OMNI_SHADOW_DISTANCE": "shadowDistance",
}


def unique_object(pairs: list[tuple]) -> dict:
    """拒绝重复键，避免不同读取器得到不同配置。

    输入边界：只接收 `json.loads` 提供的键值对；同一对象中的键必须唯一。
    单源原因：后续流程只信任这里返回的对象，不再重复猜测哪个值才是有效值。
    """
    result = {}  # 输入对象不允许后值覆盖前值。
    for name, value in pairs:
        if name in result:
            raise ValueError(f"重复配置字段：{name}")  # 重复值必须由分享者明确修正。
        result[name] = value  # 检查后下游信任唯一键。
    return result


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
        text, object_pairs_hook=unique_object
    )
    if not isinstance(data, dict) or set(data) - allowed:
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
        group = source.relative_to(shaders / "effects").parts[0].removesuffix(".glsl")  # 效果名称来自目录主体。
        if not re.fullmatch(r"[a-z][a-z0-9_]*", group):
            raise ValueError(f"{source}：效果名称只能使用小写英文、数字和下划线")
        lines = source.read_text(encoding="utf-8").splitlines()  # 保留原始行号便于定位错误。
        for index, line in enumerate(lines):
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
        {"label", "description", "slider"},
    )  # 菜单文字和滑块要求只读取这一条源码说明。
    line = lines[index + 1] if index + 1 < len(lines) else ""  # 文件末尾没有声明时按相邻格式错误处理。
    definition = DEFINE.fullmatch(line)  # 原生宏允许无数值开关以及带范围的数字。
    constant = CONST.fullmatch(line)  # 常量必须带类型、默认值和明确范围。
    if definition is None and constant is None:
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
    if default is None:
        default = "false" if commented else "true"  # 无数值宏按是否被注释表示开关，范围不能伪造布尔类型。
        if values or data.get("slider", False):
            raise ValueError(f"{location}：布尔开关不能声明数值范围或滑块")
    elif (not constant and (commented or not values)) or not all(NUMBER.fullmatch(value) for value in choices):
        raise ValueError(f"{location}：数值选项必须启用定义并提供数字范围")
    if default not in choices or len(set(choices)) != len(choices):
        raise ValueError(f"{location}：默认值不在范围内，或范围含重复值")
    return Option(
        name, default, choices, data["label"], data.get("description", {}),
        data.get("slider", False), group, source, index + 2, declaration,
    )  # 返回同时包含菜单文字和原生取值的数据，不再另存一份默认值。


def read_properties(source: Path) -> dict[str, str]:
    """读取单行 `properties` 键值，拒绝重复键和含糊的续行。

    输入边界：只接受外部配置文件中的单行 `key=value`；空行和注释可存在，续行不接受。
    格式取舍：`properties` 是加载器直接读取的单行键值文本，没有分享对象的字段结构。
    工具额外写出的版本注释由 `shared` 单独读取，不会被这里当成玩家选项。
    """
    result = {}  # 同一个键只允许定义一次。
    for index, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()  # 配置输入先整理空白。
        if not stripped or stripped.startswith(("#", "!")):
            continue  # 空行与说明不影响玩家值。
        key, separator, value = stripped.partition("=")  # 只支持明确的单行键值。
        key, value = key.strip(), value.strip()  # 键值分别规范化。
        if not separator or not key or key in result or stripped.endswith("\\"):
            raise ValueError(f"{source}:{index}：需要唯一的单行 key=value")
        result[key] = value  # 下游再检查具体选项范围。
    return result  # 不悄悄覆盖重复配置。


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
        changes = read_properties(source)  # 预设同样经过配置边界检查。
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


def generated(shaders: Path, options: dict[str, Option], groups: dict,
              profiles: list[Preset]) -> dict[Path, str]:
    """从效果源码和预设生成菜单、滑块、预设及翻译文件内容。

    输入边界：`options`、`groups` 和 `profiles` 必须来自本文件的扫描结果；`shaders` 中的
    `rendering/pipeline.properties` 只能保存绘制流程设置，不能重复声明菜单内容。
    单源原因：返回待写入内容而不是直接写盘，调用方可以先比较结果；菜单和翻译始终从同一批
    效果说明生成，避免手工同步遗漏。
    """
    pipeline = shaders / "rendering/pipeline.properties"  # 绘制设置只有一个维护文件。
    settings = read_properties(pipeline)  # 不手工改生成产物。
    if any(key == "sliders" or key.startswith(("screen", "profile.")) for key in settings):
        raise ValueError(f"{pipeline}：菜单、滑块和预设由工具生成，不能重复维护")
    lines = ["# \\u7531 build.py \\u751f\\u6210\\uff1b\\u8bf7\\u4fee\\u6539 effects/\\u3001presets/ \\u6216 rendering/pipeline.properties \\u540e\\u91cd\\u65b0\\u751f\\u6210\\u3002"]  # 转义中文提示，保持生成文件的加载器编码。
    for line in pipeline.read_text(encoding="utf-8").splitlines():  # 保留流程设置原有顺序和说明，便于追溯来源。
        if line.strip().startswith("#"):
            lines.append(line.encode("ascii","backslashreplace").decode("ascii"))  # 保留来源的中文业务说明并转成兼容编码。
        elif line.strip():
            key = line.partition("=")[0].strip()  # 值使用已检查结果，不再从原始文字另做一次解析。
            lines.append(f"{key} = {settings[key]}")  # 已检查的键值保持唯一来源。
    lines += ["", "screen = " + " ".join((["<profile>"] if profiles else []) + [f"[{group.upper()}]" for group in sorted(groups)])]  # 顶层只列效果分组，有预设时才显示预设入口。
    for group in sorted(groups):  # 顺序固定便于跨系统对比。
        lines.append(f"screen.{group.upper()} = " + " ".join(
            option.name for option in options.values() if option.group == group))  # 分组归属来自效果文件位置，选项顺序沿用源码。
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
    for group in sorted(groups):  # 分组顺序与菜单一致，跨系统生成时不产生无意义差异。
        lines.append(f"screen.{group.upper()}={escape(groups[group][locale])}")
    for option in options.values():  # 选项标题与帮助使用相同语言，避免混用另一套翻译。
        lines.append(f"option.{option.name}={escape(option.label[locale])}")
        if option.description:  # 没有帮助内容时不生成空白提示。
            lines.append(f"option.{option.name}.comment={escape(option.description[locale])}")
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


def shared(source: Path, found: dict[str, Option], shader_version: str, legacy: bool = False) -> dict:
    """读取分享配置或旧属性配置，并迁移为当前完整配置。

    输入边界：`.properties` 按加载器配置读取，其他后缀仍按分享 `JSON` 读取；所有字段、版本、
    选项名称和值都在这里一次检查。`found` 必须来自当前源码扫描，`shader_version` 必须来自
    唯一版本文件；`legacy` 只允许命令入口明确打开旧格式迁移。
    迁移原因：旧配置只有调试选项，当前配置增加了更多效果，不能把旧字段静默套到新含义上；
    迁移后补齐当前默认值，并保留未知选项错误，让分享者知道哪些内容无法导入。
    """
    if source.suffix == ".properties":
        data = _properties_share(source, shader_version, legacy)  # 键值格式先补上版本结构，再走共同检查。
    else:
        data = json.loads(source.read_text(encoding="utf-8"), object_pairs_hook=unique_object)  # 重复字段会产生不同解释，必须在读取时拒绝。
    # 格式版本必须是真整数；布尔值在语言中也能参与整数比较，但不是合法的版本号。
    if (not isinstance(data, dict)
            or set(data) != {"schemaVersion", "shaderVersion", "values"}
            or type(data["schemaVersion"]) is not int
            or data["schemaVersion"] not in (1, SHARE_SCHEMA)
            or not isinstance(data["values"], dict)):
        raise ValueError("分享配置必须包含格式版本、目标版本和选项对象")
    if not isinstance(data["shaderVersion"], str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:dev|alpha|beta|rc)\.\d+)?", data["shaderVersion"]):
        raise ValueError("分享配置的光影版本无效")
    if data["schemaVersion"] == SHARE_SCHEMA and data["shaderVersion"] != shader_version:
        raise ValueError("格式二只能导入当前光影版本")  # 当前格式不隐式猜测字段含义。
    if data["schemaVersion"] == 1 and (not _older_or_equal(data["shaderVersion"], LEGACY_VERSION)
                                       or not _older_or_equal(data["shaderVersion"], shader_version)):
        raise ValueError("格式一只接受开发准备阶段的旧版配置")  # 没有定义迁移的版本不能隐式套用旧规则。
    changes = data["values"]  # 分享数据进入已检查的选项边界。
    if data["schemaVersion"] == 1 and any(name != "OMNI_DEBUG_VIEW" or value not in ("0", "1", "2") for name, value in changes.items()):
        raise ValueError("旧版配置只能包含原有调试视图；当前选项请按当前格式导入")  # 不把当前水云等选项伪装成旧接口。
    for name, value in changes.items():  # 逐项报告未知名称与非法取值，不把拼写错误当成缺省值。
        if name not in found or not isinstance(value, str) or value not in found[name].values:
            raise ValueError(f"未知选项或无效取值：{name}={value}")  # 静默忽略会让分享者误以为配置已完整生效。
    values = {name: changes.get(name, option.default) for name, option in found.items()}  # 缺少的当前选项补源码默认值，导入总是完整替换。
    return {"schemaVersion": SHARE_SCHEMA, "shaderVersion": shader_version, "values": values}  # 旧格式只升级结构，不臆测或重命名未知字段。


def _properties_share(source: Path, shader_version: str, legacy: bool) -> dict:
    """给加载器键值配置补上分享结构，让两种输入使用相同的版本与取值检查。

    版本注释不影响游戏读取；没有注释时默认按当前版解释，只有显式旧格式参数才启用旧版规则。
    本函数只整理外部文件格式，不替调用方检查选项，避免两种输入各自维护一套范围判断。
    """
    lines = source.read_text(encoding="utf-8").splitlines()  # 从原始注释读版本，不把它混入玩家选项。
    versions = [line.removeprefix("# @shaderVersion ").strip()
                for line in lines if line.startswith("# @shaderVersion ")]  # 只识别约定前缀，不从任意说明猜版本。
    if len(versions) > 1:
        raise ValueError("properties 配置只能有一个 @shaderVersion")  # 即使两个标记相同，也要求作者消除重复来源。
    source_version = versions[0] if versions else (LEGACY_VERSION if legacy else shader_version)  # 有明确标记时优先尊重文件，而非命令猜测。
    return {
        "schemaVersion": 1 if legacy else SHARE_SCHEMA,  # 当前配置不会因缺少版本注释被误标成旧格式。
        "shaderVersion": source_version,  # 后续共同边界负责验证版本是否合法且可迁移。
        "values": read_properties(source),  # 原始键值读取仍拒绝重复键和续行。
    }


def _older_or_equal(source: str, current: str) -> bool:
    """比较两个配置版本，供旧格式迁移判断先后顺序。

    先比较三个数字，再比较开发、测试、候选和正式阶段，最后比较阶段内序号。
    无法识别的版本返回否，不能因为解析失败就获得旧版迁移资格。
    """
    pattern = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-(dev|alpha|beta|rc)\.(\d+))?$")
    left, right = pattern.fullmatch(source), pattern.fullmatch(current)  # 两边使用同一种版本语法。
    if not left or not right:
        return False  # 只有已知版本才能按历史迁移规则解释，不能用文字排序猜先后。
    stage = {"dev": 0, "alpha": 1, "beta": 2, "rc": 3, None: 4}  # 正式版本排在所有预发布阶段之后。
    source_order = tuple(map(int, left.group(1, 2, 3))) + (stage[left.group(4)], int(left.group(5) or 0))  # 序号按数字比较，避免十排在二前面。
    current_order = tuple(map(int, right.group(1, 2, 3))) + (stage[right.group(4)], int(right.group(5) or 0))  # 正式阶段没有序号时用零占位。
    return source_order <= current_order  # 相同版本也可按已有规则导入。


def save(destination: Path, values: dict, shader_version: str, root: Path) -> None:
    """把完整分享 `JSON` 写入项目 `.dev`，不修改玩家设置。

    输入边界：本函数用 `paths.development_path` 检查 `destination`；`values` 必须是已经检查过的完整选项，
    `shader_version` 必须来自当前版本来源。`JSON` 保存格式版本和目标光影版本，便于分享与迁移。
    """
    destination = paths.development_path(destination, root, ".json")  # 格式与路径同时在写入边界检查。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 只在确认边界后建立输出目录。
    content = {"schemaVersion": SHARE_SCHEMA, "shaderVersion": shader_version, "values": values}  # 版本信息与值一起分享，读取者才知道该用哪套规则解释。
    destination.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")  # 保留中文和稳定缩进，方便人阅读与比较。


def save_properties(destination: Path, values: dict[str, str], shader_version: str, root: Path) -> None:
    """写出可直接交给加载器的完整 `properties`，并保留工具版本标记。

    输入边界：目标路径必须通过 `paths.development_path`，`values` 必须是完整且已检查的选项值。
    格式取舍：这里输出加载器能直接读取的单行键值，而不是带对象结构的分享 `JSON`；版本注释
    只供本工具迁移读取，不改变加载器的选项语法。
    """
    destination = paths.development_path(destination, root, ".properties")  # 加载器配置沿用同一受控输出边界。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 输出边界检查后才创建目录。
    content = [
        f"# @shaderVersion {shader_version}",  # 版本放注释里，加载器仍只接收原来的选项键值。
        "# Omni \\u5171\\u4eab\\u914d\\u7f6e\\uff1b\\u6bcf\\u4e2a\\u9009\\u9879\\u503c\\u6765\\u81ea\\u6548\\u679c\\u6e90\\u7801\\u7684\\u539f\\u751f\\u5b9a\\u4e49\\u3002",  # 说明保留原有转义内容与顺序。
        *(f"{name}={value}" for name, value in values.items()),  # 已检查的字符串原样写入，不重新格式化数字。
    ]
    destination.write_text("\n".join(content) + "\n", encoding="ascii")  # 中文说明使用转义，键和值保持加载器可读编码。


def _arguments() -> tuple[argparse.Namespace, argparse.ArgumentParser]:
    """读取并检查命令参数组合，返回参数和保留原错误出口的解析器。

    参数名、帮助文字和拒绝顺序保持原样。先拒绝不相关参数，再扫描源码，避免错误命令触发文件操作。
    """
    parser = argparse.ArgumentParser(description="Omni 配置分享")  # 参数错误继续通过解析器退出，保留命令退出码。
    parser.add_argument("command", choices=("import", "export", "diff", "reset"))  # 每条命令完成一个玩家动作。
    parser.add_argument("--input", type=Path)  # 分享操作显式指定外部输入，不隐式读取玩家设置。
    parser.add_argument("--other", type=Path)  # 另一份配置只允许用于只读比较。
    parser.add_argument("--output", type=Path)  # 文件后缀与内容格式必须一致，避免导出文件名误导玩家。
    parser.add_argument("--legacy", action="store_true", help="按开发准备阶段格式一导入旧properties")  # 旧属性没有自带格式结构，必须由用户明确选择。
    parser.add_argument("--format", choices=("json", "properties"), help="输出格式；export默认properties，import与reset默认json")  # 显式格式只开放给导出命令。
    args = parser.parse_args()  # 参数不匹配时在任何输出文件写入前拒绝。
    if args.legacy and (args.command != "import" or not args.input or args.input.suffix != ".properties"):
        parser.error("--legacy 只能用于 import 的旧properties输入")
    if args.other and args.command != "diff":
        parser.error("--other 只能用于 diff")  # 不把第二份输入误当成导出或导入对象。
    if args.format and args.command != "export":
        parser.error("--format 只能用于 export")  # 此处已覆盖对比、导入和重置，无需再次检查相同组合。
    if args.output and args.command == "diff":
        parser.error("diff 不写入文件，不能指定 --output")  # 对比只打印差异，不创建配置。
    if args.command == "reset" and args.input:
        parser.error("reset 从源码重置，不接受 --input")  # 重置的唯一数据源是原生默认值。
    return args, parser  # 文件后缀仍在确定最终输出格式后用同一解析器报错。


def main() -> None:
    """执行配置导入、导出、对比和重置命令。

    命令边界：参数由 `_arguments` 检查，外部配置由 `shared` 检查，保存时统一检查输出路径。
    外部行为：保留现有命令名、参数名、默认输出路径和中文结果文字，方便脚本继续调用。
    模块末尾统一报告可预期错误；未知选项、路径越界或格式错误都不会被静默跳过。
    """
    import build  # 延迟引入避免构建与配置循环初始化，保持原有入口依赖顺序。
    args, parser = _arguments()  # 参数检查完成后才读取当前源码与版本。
    found, _ = scan(build.SHADERS)  # 当前所有取值仍来自效果原生定义。
    release = build.version()  # 文件目标版本只来自唯一版本文件，不在命令中硬编码。
    if args.format:
        output_format = args.format  # 显式指定优先，后面仍要检查后缀一致。
    elif args.command == "export" and not args.output:
        output_format = "properties"  # 没指定目标的导出默认生成加载器可读配置。
    else:
        output_format = "properties" if args.output and args.output.suffix == ".properties" else "json"  # 其余情况沿用原来的后缀推断规则。
    filename = f".dev/config/load.{output_format}" if args.command == "export" else ".dev/config/user.json"  # 保留各命令的默认目标。
    destination = args.output or build.ROOT / filename  # 指定目标时沿用用户路径，不自动替换后缀。
    if destination.suffix != "." + output_format:
        parser.error("--format 必须与 --output 的文件后缀一致")  # 内容格式和文件名不符时在写盘前拒绝。
    defaults = {name: option.default for name, option in found.items()}  # 默认值来自真实声明，不来自旧配置或预设。
    if args.command == "reset":
        save(destination, defaults, release, build.ROOT)  # 重置只保存工具管理的共享配置。
        print("已重置开发共享配置")  # 保留现有成功文字，供用户和脚本识别。
        return  # 重置无需输入文件，不进入分享读取流程。
    if not args.input:
        parser.error("此命令需要 --input")  # 导入、导出与对比均需明确输入。
    current = shared(args.input, found, release, args.legacy)["values"]  # 检查后内部只使用完整且合法的配置。
    if args.command == "diff":
        other = shared(args.other, found, release)["values"] if args.other else defaults  # 不给另一份配置时与源码默认值对比。
        for name in found:  # 仅显示两份完整配置实际不同的值。
            if current[name] != other[name]:
                print(f"{name}: {other[name]} → {current[name]}")  # 箭头继续从对照值指向输入值。
        return  # 对比到此结束，不触发任何保存函数。
    if args.command == "export" and destination.suffix == ".properties":
        save_properties(destination, current, release, build.ROOT)  # 导出的完整属性可直接交给加载器。
    else:
        save(destination, current, release, build.ROOT)  # 分享对象保留格式和目标光影版本。
    print("共享配置已保存到开发目录")  # 只有实际保存成功后才报告完成。


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # 成功信息和差异文字保持中文可读。
    sys.stderr.reconfigure(encoding="utf-8")  # 参数错误与配置错误采用相同编码。
    try:
        main()  # 所有命令走同一条检查、读取和反馈主线。
    except (ValueError, OSError) as error:
        print(f"错误：{error}", file=sys.stderr)  # 配置与文件错误统一报告原因，不吞掉异常内容。
        sys.exit(1)  # 保留失败退出码，让调用脚本能识别保存失败。
