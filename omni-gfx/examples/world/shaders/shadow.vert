#version 330 core
// 阴影顶点阶段：用方向光的视图投影矩阵把地形与植被投影到深度图。
// 调用位置：测试世界每帧第一遍绘制，目标是一张只有深度的级联阴影贴图。
// 设计原因与取舍：与地形共用同一套顶点缓冲，属性位置零就是世界坐标；
// 风摆公式必须和 `terrain.vert` 完全一致，否则树冠在动、树影不动，画面立刻穿帮。
layout(location = 0) in vec3 aPosition; // 方块角点的世界坐标。
layout(location = 5) in float aSway; // 风摆权重，与主画面同一条属性。

uniform mat4 uLightViewProjection; // 方向光的视图投影矩阵。
uniform float uTime; // 场景时间，驱动风摆。
uniform float uWind; // 风摆幅度，米。

void main()
{
    vec3 position = aPosition; // 先复制一份，再叠加与主画面相同的风摆。
    float phase = aPosition.x * 0.62 + aPosition.z * 0.41; // 与地形顶点着色器同一相位。
    float gust = 0.65 + 0.35 * sin(uTime * 0.37 + aPosition.x * 0.05); // 同一阵风曲线。
    position.x += sin(uTime * 1.55 + phase) * 0.10 * aSway * uWind * gust; // 横向摆动。
    position.z += cos(uTime * 1.23 + phase * 1.31) * 0.07 * aSway * uWind * gust; // 纵向摆动。
    position.y += sin(uTime * 2.10 + phase * 0.7) * 0.025 * aSway * uWind; // 竖向起伏。
    gl_Position = uLightViewProjection * vec4(position, 1.0); // 直接投影到光源裁剪空间。
}
