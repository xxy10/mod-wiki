# Gold Film VFX — 使用说明

> 状态触发式自定义武器特效骨架（怪物猎人：荒野 / REFramework）
> 纳刀/拔刀状态机 + 自定义生命周期光柱特效，纯加法架构，与其他特效 mod 天然共存

---

## 一、这是什么

给太刀加"状态触发特效"的 REFramework 脚本骨架：

- **状态机**：轮询拔刀状态（`_IsWeaponOn`），纳刀/拔刀切换时自动挂载/卸载对应特效组；
- **光柱示例**：纳刀瞬间快速出现 → 伸长到 2 倍 → 纳刀期间保持 → 拔刀后**大居合保持 1 秒再淡出**，小居合/普通拔刀立即移除；
- **纯加法架构**：只创建自己的 GameObject（挂在武器 transform 下），不 hook 游戏特效调用、不替换任何原版效果槽——与原版特效、VFX Unleashed 等其他 mod **天然共存**。

架构参照：`blade_prop.lua`（挂载 API）、`hcl_ryujin.lua`（状态机/卫生规则）、VFX Unleashed（动作轮询），均为已逆向验证的实现。

## 二、安装

1. 前提：已装 REFramework（版本匹配当前游戏 build）；
2. 把 `reframework/autorun/gold_film_vfx.lua` 复制到游戏的 `reframework/autorun/` 目录；
3. 进游戏 → REFramework 菜单 → `Gold Film VFX` → 勾选启用。

## 三、快速验证流程（强烈建议先走一遍）

**第一步用占位资产验证机制，再换自制资产**：

1. 临时把 `MOUNTS` / `PILLAR` 里的 `mesh`/`mdf2` 填成现成路径试跑（例如 texiao mod 的 `Art/VFX/Mesh/24/107/abigail000.mesh` + `abigail000.mdf2`）；
2. 训练场勾选启用 → 拔刀/纳刀，观察 UI 里 `State:` 行随动作切换；
3. 纳刀 → 光柱出现并伸长；**大居合拔刀 → 保持 1s 淡出；小居合/普通拔刀 → 立即消失**；
4. UI 里有 `Pillar: <phase>` 实时相位显示（appear/grow/hold/draw_pending/draw_hold/fade），可直接确认判定分支走对了；
5. 机制验证通过后，把路径换成自制资产（`gold_film`、`star_cross`、`light_pillar`）。

## 四、光柱时间轴（当前默认参数）

```
纳刀瞬间      0.10s     0.45s                拔刀翻转        +0.25s(判定窗)      +1.00s      淡出
   |──快速出现──|──伸长×2──|──── 纳刀期间保持 ────|──识别拔刀方式──┬─ 大居合ID命中 ──┬→ 淡出销毁
                                                  └─ 小居合/普通拔刀 ──→ 立即移除
```

| 参数 | 值 | 含义 |
|---|---|---|
| `appear` | 0.10s | 弹出阶段（XZ+Y 从 0 → 1） |
| `grow` | 0.35s | Y 从 1 → `grow_to`（smoothstep 缓出） |
| `grow_to` | 2.0 | 伸长一倍的终态长度 |
| `pending` | 0.25s | 拔刀方式判定窗口 |
| `draw_hold` | 1.00s | 大居合后保持时长 |
| `fade` | 0.30s | 淡出时长（平方缓出） |

**大居合判定表** `SPIRIT_MOTIONS`：bank 20 的动作 **252 / 263 / 264 / 265**（居合抜刀気刃斬，来自 hcl_ryujin 逆向编目）。小居合（居合抜刀斬）与普通拔刀落入 else 分支自动处理。

## 五、配置指南（都在脚本顶部）

| 配置项 | 说明 |
|---|---|
| `ASSET` | 你的 mod 资产根路径（natives 相对路径） |
| `MOUNTS.sheathed / .drawn` | 每状态的特效组：`{name, mesh, mdf2, part, joint}`；`part` = 武器挂载节点（`Wp_Parent`=刀身 / `WpSub_Parent`=刀鞘），`joint` = 绑定的骨骼名（如 `Guard_Star`，nil 则挂节点原点） |
| `PILLAR.*` | 光柱时间轴参数（上表） |
| `POLL_SECONDS` | 状态轮询间隔；`0` = 每帧（推荐，触发跟手） |
| `SPIRIT_MOTIONS` | 大居合动作 ID 表 |

## 六、上线前 TODO（脚本尾部已标注）

1. **每武器门控**：校验装备武器 mesh 路径（hcl 的 `is_hcl_ryujin_path` 式检查），只对自己的武器生效；
2. **红刃条件闸**：`blade_is_red()` 桩函数待填——字段探查方法：REF 的 GameObject 浏览器找到太刀武器对象 → 找 `Gauge`/`Spirit`/`Kijin` 字段 → 白/黄/红三态记录值；找到后 `pillar_spawn` 加一道闸即可（判定必须在脚本做，efx 做不了状态条件——原版把槽色拆成三个效果 ID 就是证据）；
3. **UV 滚动驱动**：光膜壳的流动由 mdf2 材质参数（Artian 流光式）或脚本逐帧脉动兜底；
4. （可选）**特殊纳刀限定**：光柱目前任何纳刀都触发，要限定特殊纳刀就 gate 在 motion 249 上；
5. （可选）**小居合动作 ID 编目**：训练场拔一次小居合记录 motion ID，加显式分支（当前 else 分支已正确处理）。

## 七、共存规则（重要）

| 规则 | 原因 |
|---|---|
| 只加不删：不 hook 游戏特效调用、不替换原版效果槽 | 与原版特效/其他脚本 mod 零冲突 |
| 自制资产放私有命名空间路径（如 `107/`、`vfx_xxx_` 前缀） | 避免覆盖原版或其他 mod 的文件 |
| 所有运行时对象带 `PREFIX` 前缀命名 | 热重载后可扫描清理残留 |
| 武器骨骼**只追加**（`Guard_Star` 加在骨骼表末尾） | 否则换装时其他外观骨骼变形 |

## 八、故障排查

| 症状 | 排查 |
|---|---|
| 菜单里没有 "Gold Film VFX" | REF 控制台看 Lua 报错（语法/路径） |
| 启用后 State 一直 waiting | 本地猎人未加载（先进任务/训练场） |
| 特效不出现 | 资产路径拼错（看控制台 `Resource unavailable`）；`part` 节点名不对 |
| 光柱不触发 | 看 `State:` 是否有翻转；`Pillar:` 相位卡在哪 |
| 换区后残留/失效 | 正常——脚本会 `remove_stale` 自愈；确认 `PREFIX` 没被改动 |
| 大居合判定不准 | 确认游戏版本动作 ID 没变（游戏更新可能挪动 motion 编号） |

## 九、相关文件（本工作区）

| 文件 | 内容 |
|---|---|
| `仙剑特效_金色光膜与十字星芒_计划文档.md` | 总计划：设计图参考、资产清单、里程碑、避坑清单 |
| `vfx/gold_flow/gold_flow_alba.png` | 流动贴图成品（RGBA，转 TEX 用这张） |
| `vfx/gold_flow/star_gold_alba_1024.png` | 星芒贴图资产版 |
| `scripts/gen_gold_flow.py` | 流动贴图生成器（饱满度/起伏/星点参数可调） |
| `scripts/gen_star_1024.py` | 星芒生成器（球核/芒刺/颜色过渡参数） |
| `scripts/gold_film_vfx.lua` | 脚本工作副本（与 `GoldFilmVFX/reframework/autorun/` 内的一致） |

## 十、版本风险备忘

- 贴图/网格版本号：tex `241106027`、mesh `241111606`——游戏大版本若 bump 格式，需重导出；
- 动作 ID（249/252/263/264/265 等）为当前版本编号，标题更新可能挪动；
- 以上失效均为"软失败"（少效果不崩游戏），更新后先看 REF 日志定位。
