/*
Omni 通用图形库末地传送门模块：每层旋转、缩放与平移的传送门纹理矩阵。
调用位置：末地传送门表面与需要层叠流动纹理的世界效果；由 `/omni-gfx/world/portal.glsl` 引入。
可复制示例：
    float4x4 clip = ogxEndPortalLayer(3.0, frameTime); // 取该层的矩阵。
设计原因与取舍：
    十六层各自不同旋转与平移，矩阵按参考实现的乘法顺序展开，调用方直接乘贴图坐标。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。末地传送门矩阵目前只有探针覆盖，顶层入口尚未接入。
*/
#ifndef OGX_WORLD_PORTAL_INCLUDED
#define OGX_WORLD_PORTAL_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"

// 末地传送门层：每层一个旋转、缩放与平移，叠出会流动的传送门纹理。
float4x4 ogxEndPortalLayer(float layer, float timeSeconds)
{
    float4x4 translate = float4x4(1.0, 0.0, 0.0, 17.0 / layer,
                                  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (timeSeconds * 0.0005),
                                  0.0, 0.0, 1.0, 0.0,
                                  0.0, 0.0, 0.0, 1.0); // 每层不同的平移。
    float angle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0); // 每层不同的旋转角。
    float s = (4.5 - layer / 4.0) * 2.0; // 与参考实现相同的均匀缩放。
    float4x4 scaleRotate = float4x4(s * cos(angle), -s * sin(angle), 0.0, 0.0,
                                    s * sin(angle), s * cos(angle), 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 0.0, 0.0, 1.0); // 按列填写的缩放旋转矩阵。
    float4x4 uvScaleTranslate = float4x4(0.5, 0.0, 0.0, 0.25,
                                         0.0, 0.5, 0.0, 0.25,
                                         0.0, 0.0, 1.0, 0.0,
                                         0.0, 0.0, 0.0, 1.0); // 贴图坐标从零到一压到四分之一到四分之三。
    float4x4 scaledTranslate; // 缩放旋转乘平移。
    float4x4 result; // 再乘贴图缩放。
    for (int column = 0; column < 4; column++) // 逐列展开矩阵乘法。
    {
        for (int row = 0; row < 4; row++) // 逐行点积。
        {
            scaledTranslate[column][row] = scaleRotate[0][row] * translate[column][0] + scaleRotate[1][row] * translate[column][1]
                + scaleRotate[2][row] * translate[column][2] + scaleRotate[3][row] * translate[column][3]; // 第一段乘积。
            result[column][row] = scaledTranslate[0][row] * uvScaleTranslate[column][0] + scaledTranslate[1][row] * uvScaleTranslate[column][1]
                + scaledTranslate[2][row] * uvScaleTranslate[column][2] + scaledTranslate[3][row] * uvScaleTranslate[column][3]; // 第二段乘积。
        }
    }
    return result; // 参考实现的乘法顺序。
}

#endif
