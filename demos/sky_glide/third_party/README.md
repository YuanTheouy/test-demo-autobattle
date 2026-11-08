# 引用的角色控制器代码

本 demo 只引入下列 MIT 代码，没有引入原项目的模型、贴图、声音或关卡。

| 上游 | 固定版本 | 本项目使用位置 |
| --- | --- | --- |
| [GDQuest 3D character controller tutorial](https://github.com/gdquest-demos/godot-4-3d-character-controller-tutorial) | `6f3292ed36537e33230e5ea9205d424b37b180af` | `../locomotion.gd` 改编自 `lesson_reference/player_3d_template_v3.gd` 的相机相对移动与水平/垂直速度分离 |
| [Andicraft Stairs Character](https://github.com/Andicraft/stairs-character) | `5403d02f6b64b49a1d1bd7af11dd51a6edfc9e6c` | `stairs_character.gd` 改编自 `addons/stairs-character/stairs_character.gd` 的上抬、前探、落脚形状扫掠 |

原许可全文分别保存在 `gdquest-code.LICENSE`、`stairs-character.LICENSE`。GDQuest 原仓库的美术另有非商业许可，本项目未复制这些资产。

本地适配：把台阶控制器帧生命周期变为显式调用；禁止跳跃时吸附台阶；下降时确认坡面可以站立；暴露支撑状态供滑翔、采集使用；限制实际台阶高度。地面使用独立加速/制动参数，空中步行输入只能改变已有水平动量的方向、不能从静止获得前进推力。碰撞体按 Stairs Character 的主要测试组合使用圆柱，明确启用 Godot 4.6 内置 Jolt。

`aerodynamics.gd`、`climbing.gd`、地形生成与相机球形扫掠为本 demo 代码，不能称为上述开源项目提供的滑翔/攀爬物理。
