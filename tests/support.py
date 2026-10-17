"""测试共用的扫描与展开缓存：一次读取光影源码，多组断言复用同一结果。

调用位置：`tests/` 下的各回归模块直接导入，代替各自重复调用 `build.configuration()`、
`build.expand()` 与读取效果文件。
调用示例：
    `found, profiles, files = support.configuration()`
    `text = support.text("effects/cloud/cloud.glsl")`
    `expanded = support.expand(build.SHADERS / "world0/composite.fsh")`
为什么缓存：`python build.py verify` 只有十秒总预算，合成本体展开一次约零点四秒，
逐条断言各展开一次会挤爆预算；这些源码在本轮测试期间不改动，所以可以安全共享。
边界：只缓存项目自有的只读源码；临时目录里构造的源码不走这里，仍各自独立展开。
"""
from __future__ import annotations

import json  # 缓存流程表与本维度声明映射的解析结果。
import build  # 复用真实构建接口，不复制扫描与展开逻辑。

_configuration = None  # 首次调用后保存真实选项、预设与生成文件。
_numbers = None  # 展开用的稳定编号表，全模块共享一份。
_expanded: dict = {}  # 已展开文本，按源码路径复用，避免重复拼接整棵引用树。
_texts: dict[str, str] = {}  # 已读取的效果文件原文。
_programs = None  # 流程表解析结果只读一次。


def configuration() -> tuple[dict, list, dict]:
    """返回真实扫描得到的 (选项, 预设, 生成文件)，只扫描一次后复用。"""
    global _configuration
    if _configuration is None:  # 各测试共用同一份扫描结果，不重复读整棵效果树。
        _configuration = build.configuration()  # 真实生成内容来自维护源码。
    return _configuration


def expand(path, shaders=None) -> str:
    """展开 `path`，复用同一编号表与读取缓存；`shaders` 省略时取项目光影目录。

    只用于项目自有入口；测试构造的临时源码要自己展开，避免和项目路径串味。
    """
    global _numbers
    if _numbers is None:
        _numbers = build.numbered_sources(build.SHADERS)  # 全部项目入口共用一份编号。
    root = build.SHADERS if shaders is None else shaders
    return build.expand(path, root, (), _numbers, _expanded)  # 共享缓存只在测试进程内复用。


def text(path: str) -> str:
    """读取项目光影目录下 `path` 的原文，同一文件只读一次。

    `path` 是相对 `shaders/` 的正斜杠路径，例如 `"effects/water/water.glsl"`；
    只提供稳定文本给关键字断言，不参与展开。
    """
    if path not in _texts:
        _texts[path] = (build.SHADERS / path).read_text(encoding="utf-8")  # 测试期间源码不变。
    return _texts[path]


def programs() -> dict:
    """返回 `rendering/programs.json` 的解析结果，避免每个测试重新读取。"""
    global _programs
    if _programs is None:
        _programs = json.loads((build.SHADERS / "rendering/programs.json").read_text(encoding="utf-8"))  # 流程表是维度与程序的唯一来源。
    return _programs
