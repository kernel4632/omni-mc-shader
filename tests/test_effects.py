"""第一波效果回归：只检查选项接入与展开后的算法骨架，不宣称像素效果。

示例 python -m unittest discover -s tests；全部使用离线展开，不建立显卡上下文。
"""
import unittest  # 保留标准测试入口。
import build  # 读取真实展开源码与原生选项。

class EffectTests(unittest.TestCase):
    """逐个效果核对选项单源、算法接入和默认路径。"""
    def test_agx_tone_mapping_is_selectable(self):
        """AgX 通过色调映射选项接入最终显示，简单路径仍然保留。"""
        found,_,_ = build.configuration()  # 原生定义仍是唯一默认值来源。
        self.assertIn("OMNI_TONE_MAP",found); self.assertEqual(found["OMNI_TONE_MAP"].values,("0","1"))  # 菜单提供两种映射。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从加载器实际入口展开。
        self.assertIn("omniToneMapAgx",source)  # 最终显示包含 AgX 曲线。
        self.assertIn("omniToneMapSimple",source)  # 简单有理映射没有被删除。
        self.assertIn("omniToneMap(color)",source)  # 计算路径由选项统一分派。
