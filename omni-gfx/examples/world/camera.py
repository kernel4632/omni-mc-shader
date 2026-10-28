"""测试世界的相机：位置、朝向、视图矩阵、投影矩阵与键盘移动。

调用位置：`omni-gfx/examples/world/render.py` 创建相机，截图模式设固定姿态，
    交互模式由 GLFW 回调更新朝向与按键。
调用示例：`camera = Camera(...)`；交互模式用 `move()` 更新位置。

设计原因与取舍：
    不引入数学库，矩阵按列主序直接生成，正好匹配 OpenGL 的上传格式。
    相机只负责几何，不读取选项或窗口状态；输入由调用方转成简单动作。
"""
from __future__ import annotations

import math  # 三角函数与弧度换算。


def normalize(vector: list[float]) -> list[float]:
    """把三维向量归一化；长度为零时返回前方向，避免除零。"""
    length = math.sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2])  # 向量长度。
    if length < 1e-8:  # 退化向量没有方向。
        return [0.0, 0.0, -1.0]
    return [component / length for component in vector]  # 每个分量除以长度。


def cross(a: list[float], b: list[float]) -> list[float]:
    """三维叉乘，用于构造相机的右方向与上方向。"""
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]  # 标准叉乘公式。


def subtract(a: list[float], b: list[float]) -> list[float]:
    """三维相减，返回 a 减 b。"""
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]  # 逐分量相减。


class Camera:
    """一台针孔相机：位置、偏航、俯仰与竖直视场角。"""

    def __init__(self, position: list[float], yaw: float = 0.0, pitch: float = 0.0, fov: float = 58.0) -> None:
        """保存初始位置与朝向，视场角使用角度制。"""
        self.position = list(position)  # 相机世界坐标。
        self.yaw = yaw  # 水平角，零表示朝负 Z。
        self.pitch = pitch  # 俯仰角，正数抬头。
        self.fov = fov  # 竖直视场角。

    def forward(self) -> list[float]:
        """返回当前视线方向，已归一化。"""
        cos_pitch = math.cos(math.radians(self.pitch))  # 俯仰的余弦。
        return normalize([math.sin(math.radians(self.yaw)) * cos_pitch, math.sin(math.radians(self.pitch)),
                          -math.cos(math.radians(self.yaw)) * cos_pitch])  # 偏航绕纵轴。

    def right(self) -> list[float]:
        """返回相机右方向，已归一化。"""
        return normalize(cross(self.forward(), [0.0, 1.0, 0.0]))  # 前方向与世界上方向叉乘。

    def up(self) -> list[float]:
        """返回相机上方向，已归一化。"""
        return normalize(cross(self.right(), self.forward()))  # 右方向与前方向叉乘。

    def look_at(self, target: list[float]) -> None:
        """把相机转向目标点，位置不变。"""
        direction = normalize(subtract(target, self.position))  # 从相机指向目标。
        self.yaw = math.degrees(math.atan2(direction[0], -direction[2]))  # 由横向分量反解偏航。
        self.pitch = math.degrees(math.asin(max(-1.0, min(1.0, direction[1]))))  # 由纵向分量反解俯仰。

    def turn(self, delta_x: float, delta_y: float, sensitivity: float = 0.09) -> None:
        """按鼠标位移转动视角，俯仰限制在正负八十九度。"""
        self.yaw += delta_x * sensitivity  # 水平不限制。
        self.pitch = max(-89.0, min(89.0, self.pitch - delta_y * sensitivity))  # 防止翻转。

    def move(self, keys: set[int], delta_time: float, glfw_module, speed: float = 12.0) -> None:
        """按当前按键移动相机；前后左右沿视线水平面，升降沿世界纵轴。"""
        forward = self.forward()  # 前方向。
        flat = normalize([forward[0], 0.0, forward[2]])  # 去掉俯仰，走路不会往地里钻。
        right = self.right()  # 右方向。
        step = speed * delta_time  # 本帧移动距离。
        if glfw_module.KEY_W in keys:  # 前进。
            self.position = [self.position[i] + flat[i] * step for i in range(3)]
        if glfw_module.KEY_S in keys:  # 后退。
            self.position = [self.position[i] - flat[i] * step for i in range(3)]
        if glfw_module.KEY_A in keys:  # 左移。
            self.position = [self.position[i] - right[i] * step for i in range(3)]
        if glfw_module.KEY_D in keys:  # 右移。
            self.position = [self.position[i] + right[i] * step for i in range(3)]
        if glfw_module.KEY_SPACE in keys:  # 上升。
            self.position[1] += step
        if glfw_module.KEY_LEFT_CONTROL in keys:  # 下降。
            self.position[1] -= step

    def view_matrix(self) -> list[float]:
        """返回列主序视图矩阵，可直接上传 OpenGL。"""
        forward = self.forward()  # 前方向。
        right = self.right()  # 右方向。
        up = self.up()  # 上方向。
        position = self.position  # 相机位置。
        return [
            right[0], up[0], -forward[0], 0.0,  # 第一列。
            right[1], up[1], -forward[1], 0.0,  # 第二列。
            right[2], up[2], -forward[2], 0.0,  # 第三列。
            -sum(right[i] * position[i] for i in range(3)),  # 平移的横向分量。
            -sum(up[i] * position[i] for i in range(3)),  # 平移的纵向分量。
            sum(forward[i] * position[i] for i in range(3)),  # 平移的深度分量。
            1.0,
        ]

    def projection_matrix(self, aspect: float, near: float, far: float) -> list[float]:
        """返回列主序透视投影矩阵。"""
        f = 1.0 / math.tan(math.radians(self.fov) * 0.5)  # 视场角一半的正切倒数。
        return [
            f / aspect, 0.0, 0.0, 0.0,  # 横向缩放。
            0.0, f, 0.0, 0.0,  # 纵向缩放。
            0.0, 0.0, (far + near) / (near - far), -1.0,  # 深度映射。
            0.0, 0.0, (2.0 * far * near) / (near - far), 0.0,  # 深度平移。
        ]
