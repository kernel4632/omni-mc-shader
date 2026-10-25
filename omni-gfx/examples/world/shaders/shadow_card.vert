#version 330 core
// 植物卡片阴影顶点阶段：与主画面同一套风摆公式，只输出光源裁剪坐标与 UV。
// 调用位置：树叶、草丛与野花的方向光阴影绘制。
// 设计原因与取舍：叶片必须参与阴影，树冠才会在地面留下斑驳的软影；
// 风摆与 `card.vert` 逐项一致，叶片移动时影子同步移动。
layout(location = 0) in vec3 aPosition; // 世界坐标。
layout(location = 2) in vec2 aUv; // 卡片纹理坐标。
layout(location = 4) in float aSway; // 风摆权重。

uniform mat4 uLightViewProjection; // 方向光视图投影。
uniform float uTime; // 场景时间。
uniform float uWind; // 风摆幅度。

out vec2 vUv; // 卡片纹理坐标。

void main()
{
    vec3 position = aPosition;
    float phase = aPosition.x * 0.62 + aPosition.z * 0.41;
    float gust = 0.65 + 0.35 * sin(uTime * 0.37 + aPosition.x * 0.05);
    position.x += sin(uTime * 1.55 + phase) * 0.10 * aSway * uWind * gust;
    position.z += cos(uTime * 1.23 + phase * 1.31) * 0.07 * aSway * uWind * gust;
    position.y += sin(uTime * 2.10 + phase * 0.7) * 0.025 * aSway * uWind;
    vUv = aUv;
    gl_Position = uLightViewProjection * vec4(position, 1.0);
}
