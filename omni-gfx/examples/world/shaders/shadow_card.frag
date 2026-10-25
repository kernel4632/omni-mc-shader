#version 330 core
// 植物卡片阴影片元阶段：按 alpha 裁切，只让真正有叶片的地方写入深度。
// 调用位置：树叶、草丛与野花的方向光阴影绘制。
// 设计原因与取舍：整张四边形都写深度会让树冠变成一块实心板，地面阴影没有缝隙；
// 阈值比主画面略低，远处稀疏叶片仍在阴影里留下淡淡斑块。
uniform sampler2D uCard; // 当前植物卡片。

in vec2 vUv; // 卡片纹理坐标。

void main()
{
    if (texture(uCard, vUv).a < 0.30)
    {
        discard;
    }
}
