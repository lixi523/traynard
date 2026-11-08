# 原生托盘图标改造 · 验证清单

> 适用改动：弃用 LCL `TTrayIcon`，改用原生 `Shell_NotifyIcon` + 每个图标唯一 `guidItem`
> （新增 `src/traynard.tray.native.pas`，修改 `traynard.tray.pas` / `traynard.form.background.pas` / `traynard.form.background.lfm` / `traynard.lpi`）
>
> 目的：验证来自同一进程（`traynard.exe`）的多个托盘图标不再“相邻且整组跟随拖动”。

## A. 前置检查

- [ ] 目标系统版本确认（影响拖动用例，见 D3/D5）
  - Windows 10：支持拖拽 → 可测“独立拖动”
  - Windows 11 ≥ Build 22563：**系统已移除托盘拖拽**，改测“各图标独立占位 / 独立显隐”
- [ ] 工作区为改造后的代码：`git status` 显示新增 `src/traynard.tray.native.pas` 及 4 处修改
- [ ] 记录**基线版本号**（官方 Releases 同一版本），用于 F 段对照

## B. 构建

按项目构建顺序（DLL → 主程序）：

```powershell
$env:PATH += ";C:\lazarus"
lazbuild --pcp=C:\lazarus\configs uniqueinstance\uniqueinstance_package.lpk
lazbuild --pcp=C:\lazarus\configs toml-fp\packages\lazarus\toml_fp.lpk
lazbuild --pcp=C:\lazarus\configs --bm=Release src\traynard.lib.lpi     # out\traynard.dll
lazbuild --pcp=C:\lazarus\configs --bm=Release src\traynard.lpi         # out\traynard.exe
```

- [ ] `out\traynard.exe`、`out\traynard.dll` 均生成，无编译错误
- [ ] 若报单元未找到 / 标识符重名，记录并附错误原文（草案可能需要微调）

**准备独立运行目录（便携模式，便于查看配置）**

```powershell
$dst = "$env:USERPROFILE\Desktop\traynard-test"
New-Item -ItemType Directory -Force -Path "$dst\data"      # 存在 data\ → 便携模式
Copy-Item out\traynard.exe,out\traynard.dll $dst -Force
New-Item -ItemType Directory -Force -Path "$dst\languages"
Copy-Item out\languages\*.mo "$dst\languages" -Force
```

- [ ] 启动 `$dst\traynard.exe`，托盘出现 Traynard 主图标
- [ ] `$dst\data\config\*.toml` 自动生成（确认为便携模式）

## C. 测试夹具（多窗口）

仓库自带 `tests/test_window.c`（自带 1 秒改标题的定时器，顺带验证“标题变化”联动）：

```powershell
# MinGW：  gcc -mwindows -O2 -o test_window.exe tests\test_window.c -luser32 -lgdi32
# MSVC：   cl /nologo tests\test_window.c /link user32.lib gdi32.lib /SUBSYSTEM:WINDOWS
# 起 3 个实例，制造“同一 exe 的多窗口”
Start-Process .\test_window.exe; Start-Process .\test_window.exe; Start-Process .\test_window.exe
```

- [ ] 桌面出现 3 个标题每秒递增的测试窗口

## D. 用例矩阵

| # | 用例 | 操作 | 期望结果 | 结果 |
|---|---|---|---|---|
| D1 | 图标生成 | 对 3 个测试窗口分别“最小化到**托盘图标**” | 托盘出现 **1 主 + 3 窗口** 共 4 个图标 | ☐ |
| D2 | 提示更新 | 观察各图标悬停提示 | 提示文本随窗口标题变化更新（`SendModify(NIF_TIP)`） | ☐ |
| **D3** | **核心：独立拖动** | Win10：拖动任一图标 | **仅该图标移动，其余不动**（旧版会整组跟随） | ☐ |
| D4 | 图标消失 | 关闭一个被托管的窗口 | 对应图标消失，其余不受影响 | ☐ |
| D5 | Win11 占位 | Win11≥22563：设置→任务栏→其他系统托盘图标 | 每个图标可**单独**显隐，互不绑定 | ☐ |
| D6 | 单击还原 | 左键单击某图标 | 仅该窗口还原（`NIN_SELECT` → `DoClick`） | ☐ |
| D7 | 右键菜单 | 右键单击某图标 | 弹出托盘菜单；点击菜单外可正常关闭（`DoContextMenu`） | ☐ |
| D8 | 双击开主窗 | 双击**主图标** | 打开 Traynard 主窗口（`OnDblClick`） | ☐ |
| D9 | 分组模式 | 设置里切换“图标分组”开 / 关 | 在“分组图标 / 逐窗口图标”间切换，位置独立 | ☐ |
| D10 | 气球通知 | 触发一次通知（规则通知 / 异常提示） | 正常弹出气泡（`ShowBalloonHint` / `NIF_INFO`） | ☐ |
| D11 | 任务栏重建 | 任务管理器重启 `explorer.exe` | 全部图标**自动重新出现**（`TaskbarCreated` → `RecreateAll`） | ☐ |
| D12 | 多程序来源 | 另起一个不同 exe（如记事本）也最小化到托盘图标 | 新增图标与其它图标同样独立 | ☐ |
| D13 | 退出清理 | 退出 Traynard（托盘菜单 → Exit） | **无残留 / 幽灵图标**（`NIM_DELETE`） | ☐ |

> 建议 D3 / D5 各测两遍：改造版 vs 官方版（F 段）。

## E. 通过 / 失败判据

- **通过**：D1–D13 全绿，尤其 **D3（独立拖动）** 与 **D11（explorer 重启后恢复）**。
- **失败定位提示**：
  - 拖动仍联动 → GUID 未真正生效（检查 `uFlags` 是否含 `TRAY_NIF_GUID`、`guidItem` 是否唯一）
  - 图标不出现 → `AddToTray` 的 `Shell_NotifyIconW` 返回值，或身份字段错误
  - explorer 重启后丢失 → `TaskbarCreated` 分支未命中
  - 点击无响应 → v4 回调分发（`HIWORD(lParam)`）未取到 id
  - 菜单不消失 / 焦点异常 → `DoContextMenu` 的 `SetForegroundWindow` 时机

## F. 与官方版对照（关键佐证）

- [ ] 同一批测试窗口，在**官方发行版**上重复 D3：应出现“图标相邻 + 拖动整组跟随”
- [ ] 在**改造版**上 D3：应“各自独立”
- [ ] 两者差异即本次改造生效的直接证据；建议录屏 / 截图存证，便于后续提 issue / PR

## G. 回归与回滚

- [ ] 回归：托盘主菜单各项（Restore All / Last、Auto-minimize、Apply Rules、Launcher）仍正常
- [ ] 回归：多语言切换后菜单文本正常
- [ ] 回滚：`git checkout -- src`；删除新增文件 `src\traynard.tray.native.pas` 及临时目录
