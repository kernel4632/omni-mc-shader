"""把 omni-gfx 自带的离线回归接入项目统一的测试发现。

调用位置：项目根目录的测试发现命令会自动加载。
设计原因与取舍：
    omni-gfx 的测试与示例放在自己的目录里，但项目验证只扫描根目录的测试目录；
    这里按文件路径加载同一个测试模块，不复制断言，也不改变两边的维护位置。
"""
from __future__ import annotations

import importlib.util  # 按文件路径加载带连字符目录下的模块。
import unittest  # 继承测试类，让统一发现能运行同一批断言。
from pathlib import Path  # 固定项目内路径。

ROOT = Path(__file__).resolve().parents[1]  # 仓库根目录。
MODULE_PATH = ROOT / "omni-gfx" / "tests" / "test_omni_gfx.py"  # 实际维护的测试文件。
SPEC = importlib.util.spec_from_file_location("omni_gfx_offline_tests", MODULE_PATH)  # 目录名带连字符，不能按包名导入。
if SPEC is None or SPEC.loader is None:  # 文件缺失时让测试直接失败，而不是静默跳过。
    raise ImportError(f"找不到 omni-gfx 测试：{MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)  # 先建模块对象。
SPEC.loader.exec_module(MODULE)  # 执行后得到测试类。


class OmniGfxProjectTests(MODULE.OmniGfxTests):
    """继承 omni-gfx 的全部离线测试，供项目统一发现运行。"""


if __name__ == "__main__":
    unittest.main()  # 允许直接运行本文件，方便单独排查。
