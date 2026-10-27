# 代码审查报告 — OpenNest v0.5.8

- 审查对象：`lib/`（77 个 Dart 文件，23,746 行）+ `android/app/src/main/kotlin/`
- 审查基线：`49c8c71`（0.5.8+14）
- **修复状态：本文档列出的 P0/P1/P2 共 24 条已在 v0.5.9 全部修复**（唯一保留的是 P0-4「固定口令」—— 那是明确的产品决策，改为在 README 写清代价，不改代码）。逐条对应见文末「修复状态」表。
- 审查范围：传输链路、引擎生命周期、API 客户端、本地存储、SQLite、路径处理、平台桥接为主；UI 层做了模式化抽样（资源释放、async gap、空值）
- 方法：静态阅读 + 危险模式全量检索（空 catch / 强制解包 / Timer 与 StreamSubscription / 文件句柄 / 进程句柄 / 路径拼接），非运行时验证

结论：**没有发现「启动即坏」的致命缺陷**。真正的风险集中在三处：**传输任务的并发控制**、**引擎进程的收尾**、**固定口令的安全面**。下面按严重程度列出。

---

## P0 — 高（会造成数据损坏、功能失效或安全暴露）

### 1. `pause` 后立刻 `resume` 会产生两个并发的 `_run` 操作同一任务，并互相删掉对方的取消令牌

- **位置**：`lib/features/transfers/transfers_controller.dart:363-380`（pause/resume）、`:509-520`（_run 入口）、`:597-599`（finally）
- **原因**：
  - `pause()` 只做 `task.status = paused` + `token.cancel()`，并不等待 `_run` 真正退出；
  - `resume()` 立刻把状态改回 `queued`，`_pump()` 看到 queued 就再起一个 `_run`；
  - 第一个 `_run` 在 `finally` 里无条件 `_tokens.remove(task.id)` —— 删掉的是**第二个** `_run` 刚放进去的 token。
- **影响**：
  - 两个下载协程同时写同一个文件 → 文件损坏（多流分段后更严重，两套定位写交错）；
  - 旧协程的 `catch` 判断的是 `task.status != paused`，而此时状态已被 `resume` 改成 `running`，于是**把新协程正在跑的任务改写为 failed**，界面上会闪过「失败」，随后又被新协程改回 done；
  - `finally` 删掉的是新协程的 token，之后对该任务的「暂停」永久失效，任务会一直跑到结束；
  - 用户看到的是「点了暂停没反应 / 状态乱跳 / 文件下载完但打不开」。
- **建议**：给每个任务加运行代次（`Map<String,int> _runSeq`），`_run` 进入时登记代次，`catch`/`finally` 只在代次相等时改状态、移除 token；或引入 `Map<String, Future<void>> _running`，`resume` 前 `await _running[id]` 再启动。

### 2. `clearTasks` 只从 map 移除 token，不 cancel —— 被清除的运行中任务会继续下载

- **位置**：`lib/features/transfers/transfers_controller.dart:415-424`
- **原因**：`remove()`（单条移除）有 `_tokens[id]?.cancel()`，`clearTasks()`（批量清除失败/已完成）只做了 `_tokens.remove(id)`。
- **影响**：批量「清除失败」时如果混入一条仍在 running 的任务，它会继续占用带宽、继续写盘，但界面上已经消失，用户无法再暂停或删除它；多流分段下还会留下半成品文件。
- **建议**：与 `remove()` 对齐，先 `cancel()` 再 `remove()`；顺手清 `_previousDone`。

### 3. 停止引擎时按 pid 文件盲杀进程，PID 复用会杀掉无关进程

- **位置**：`lib/core/sidecar/sidecar_manager.dart:200-215`
- **原因**：`_process == null` 时读 `pid` 文件并直接 `Process.killPid(pid)`，不校验该 pid 是否仍是 `openlist.exe`。PID 文件可能是上次崩溃残留，Windows 上 PID 复用很常见。
- **影响**：用户点「停止引擎」或退出应用时，可能向一个不相干的用户进程发信号（Windows 上是 TerminateProcess）。概率低，后果严重。
- **建议**：杀之前校验进程名（Windows 用 `tasklist /FI "PID eq N"` 或 `Get-Process -Id`），或改用「启动时记录 pid + 进程启动时间」双重比对；校验不通过就只删文件不动进程。

### 4. 引擎管理员口令固定为 `admin`，且管理接口是明文回环 HTTP —— 本机任意进程可完全接管

- **位置**：`lib/core/sidecar/sidecar_state.dart`（`kDefaultAdminPassword`）、`lib/core/sidecar/sidecar_config.dart:24-28`
- **原因**：这是明确的产品决策（启动零口令环节），但代价需要记录：任何本机进程只要扫 127.0.0.1 的高位端口、用 `admin/admin` 登录，就能读写全部存储源配置（里面含各网盘的凭据）。
- **影响**：同机的恶意软件/脚本可窃取所有云盘 token；不是远程可利用，但也不是零风险。
- **建议**（不改产品体验的前提下）：① 登录口令仍固定，但给引擎 API 再加一层「客户端自签的请求头 + 校验」不现实（引擎不支持）；② 至少把监听端口绑定到当前用户可访问的命名管道（引擎不支持）；③ 现实可行的缓解是**限制引擎端口暴露时间**（不启动时立刻 kill，已在做）并在 README 明确写出该取舍；④ 若将来允许自定义口令，这里是唯一改动点。

---

## P1 — 中（特定场景下功能异常或资源泄漏）

### 5. `_run` 的 `finally` 在 notifier 已 dispose 后仍调 `ref.read`，会抛未捕获异常

- **位置**：`lib/features/transfers/transfers_controller.dart:605`
- **原因**：`dispose()` 会 `cancel()` 所有 token，正在 await 的 `_run` 随即抛错进入 `finally`，此时 `ref` 已失效（Riverpod 抛 `StateError: Cannot use ref after dispose`），而 `_run` 是 `unawaited` 启动的，异常无人接。
- **影响**：退出应用时正在传输 → 控制台报未处理异步异常；在 `runZonedGuarded` 加持下不会崩，但会污染日志，且 `_pump()` 可能在已释放状态上执行。
- **建议**：`finally` 里先判 `mounted`，并把 `ref.read` 换成构造时缓存好的 notifier 引用；`dispose` 时置一个 `_disposed` 标志。

### 6. 引擎 stdout/stderr 的订阅没有保存，日志 sink 关闭后写入可能抛错

- **位置**：`lib/core/sidecar/sidecar_manager.dart:334-346`
- **原因**：`process.stdout.listen(sink.write)` 的 `StreamSubscription` 未保存；`_closeLog()` 关闭 sink 后，若进程仍有残留输出，`sink.write` 抛 `StateError: StreamSink is closed`，无人接。
- **影响**：停止引擎时偶发未捕获异常；连续重试 3 次会残留多组订阅。
- **建议**：保存两个 subscription，`_closeLog()` 前先 `cancel()`；或在 `listen` 里加 `onError` 与 closed 判断。

### 7. 安全模式在 `stop()` 未确认进程真正退出时就改引擎库

- **位置**：`lib/core/sidecar/sidecar_controller.dart:168-184`
- **原因**：`stop()` 内部 `_kill` 只在 `process.exitCode` 5 秒超时后发 sigkill，**不等待退出完成**；`startInSafeMode()` 紧接着 `snapshot()` 复制 data.db 并 `UPDATE x_storages`。
- **影响**：与仍在退出的引擎争写同一份 SQLite，轻则 `database is locked` 报「安全模式不可用」，重则备份文件不一致（主库已复制、WAL 还没落盘）。
- **建议**：`stop()` 增加「等待 pid 消失」的显式确认（轮询 `Process.killPid(pid, sigterm)` 探测或 `tasklist` 校验），安全模式入口再等一次；备份改成「先 `PRAGMA wal_checkpoint(TRUNCATE)` 再 copy」或直接用 SQLite backup API。

### 8. `AppDatabase.instance()` 没有缓存 Future，并发首次调用会重复 open

- **位置**：`lib/data/db/app_database.dart:27-50`
- **原因**：两个 `await` 之间 `_db` 仍为 null，两个调用者都会走到 `openDatabase`。依赖 sqflite 的 `singleInstance` 兜底。
- **影响**：启动阶段 `Prefs.load()` 与 `TransferDao.loadAll()` 并发时可能重复打开；虽然有 singleInstance 复用，但 `onCreate` 竞态在极端情况下会报「table already exists」。
- **建议**：缓存 `Future<Database>? _opening`，`instance()` 直接 `return _opening ??= _open()`。

### 9. `Prefs.flush()` 在事务里先删「全清」标记，事务失败后清缓存永不重试

- **位置**：`lib/core/storage/prefs.dart:353`
- **原因**：`if (_deletedCache.remove('*')) { await txn.delete('listing_cache'); }` —— 标记在事务体内被移除，事务回滚后标记已丢，catch 只保留其他 `_dirty*`。
- **影响**：用户点「清空缓存」时如果落库失败，界面显示已清空，实际数据仍在，且后续不会再清。
- **建议**：把 `remove('*')` 移到事务成功后（与 `_dirty*.clear()` 同处）。

### 10. 重命名不校验新名字里的路径分隔符

- **位置**：`lib/features/files/file_actions.dart:74-92`
- **原因**：`api.rename(source, name.trim())` 直接透传用户输入，`/`、`\`、`..` 都没拦。
- **影响**：输入 `../x` 或 `a/b` 时，引擎可能把条目移到别的目录（视驱动实现），或在本地存储驱动上创建出非预期路径；至少会产生一个无法打开的条目。
- **建议**：提交前用 `safePathSegment(name)` 做一次规范化并回显给用户确认，或直接拒绝含 `/\` 与 `..` 的名字。

### 11. `probeAll` 的 `_probing` 守卫会丢掉刷新请求

- **位置**：`lib/features/sources/storage_health.dart:170-175`
- **原因**：探测进行中（多源 × 12s 超时，最坏几十秒）时，`scheduleRefresh()` 触发的 `probeAll()` 直接 `return`，这次刷新被丢弃。
- **影响**：传输失败后「立刻把源标红」的承诺在最需要的时候失效，界面要等下一个 90 秒周期。
- **建议**：改成 `_pendingProbe = true`，当前轮结束后补跑一轮（与 `Prefs.flush` 的 `_pending` 同款模式）。

### 12. `enqueueDownloadInto` 取下载目录的调用在 try 之外，三级兜底都失败会抛到 UI

- **位置**：`lib/features/transfers/transfers_controller.dart:257`
- **原因**：`final root = await _downloadDir(profile);` 在 `try` 之前；`ensureDownloadDirFor` 的最后一层 `Directory(alt).create()` 没有 try，全失败时异常上抛。
- **影响**：磁盘只读 / 权限异常时，点「下载」会抛未捕获异常，按钮无反馈（而不是提示「无法创建目录」）。
- **建议**：把 `_downloadDir` 移进 try，或在 `ensureDownloadDirFor` 最外层再包一层并返回可展示的错误。

### 13. 传输列表的派生 getter 每次全表遍历，且每秒重建一次全表

- **位置**：`lib/features/transfers/transfers_controller.dart:38-43`（5 个 getter 各 `.toList()`）、`:195-217`（`_tick` 每秒 `copyWith(tasks: List.of(...))`）
- **影响**：1000 条任务时，每帧 UI 会触发数千次遍历 + 每秒一次 1000 元素拷贝。批量下载时传输页明显掉帧，也会拖慢主 isolate 上的下载循环（下载与 UI 同 isolate）。
- **建议**：把 `running/queued/done/failed` 计数在状态更新时增量维护；`_tick` 只在存在 running 任务时重建（当前只判了 `tasks.isEmpty`）。

### 14. 上传的 `Content-Length` 取自上传前，文件变化会让请求挂到超时

- **位置**：`lib/core/api/openlist_api.dart:948-980`
- **原因**：`length = await source.length()` 后按 1MB 读盘，若文件在传输中被截断/追加，实际字节数与 header 不符。
- **影响**：服务端等不满 Content-Length，Dio 的 `sendTimeout` 是 1 天 → 任务长时间停在「上传中 0%」。多流分段新增的连接池放大后更容易撞到。
- **建议**：上传结束后校验实际发送字节数；或把 `sendTimeout` 从 1 天降到 30 分钟这类可感知的量级。

### 15. `FilesNotifier` 没有 `dispose`，`_skeletonTimer` 不会被取消

- **位置**：`lib/features/files/files_controller.dart:96-101`
- **原因**：类里只有 `_skeletonTimer` 字段，没有重写 `dispose`。
- **影响**：ProviderScope 重建 / 退出时定时器仍会触发一次（回调有 `mounted` 守卫，不会崩），属于轻微资源泄漏。
- **建议**：补 `dispose()` 取消定时器（与 `TransfersNotifier` 一致）。

### 16. `SessionState.copyWith` 的 `error` 永远被覆盖，无法「保留旧错误」

- **位置**：`lib/features/auth/session.dart:63`
- **原因**：`error: error`（不是 `error ?? this.error`），任何 `copyWith` 都会把 error 清成 null。
- **影响**：`refreshUser()` 成功时清错误是预期行为，但 `copyWith(latencyMs: ...)` 之类也会意外清掉错误提示，属于语义陷阱，后续容易踩。
- **建议**：显式加 `bool clearError = false`，与项目里其他 `copyWith` 保持一致。

---

## P2 — 低（边界条件与体验瑕疵）

### 17. 移除任务时对 `total == 0` 的任务可能误删已完整的文件

- **位置**：`lib/features/transfers/transfers_controller.dart:398-405`
- **原因**：`complete = task.total > 0 && length >= total`，`total` 未知（恢复的旧任务、服务端未给 size）时恒为 false → 直接 `deleteSync()`。
- **影响**：从恢复列表里移除一条「其实已下载完」的任务，会把文件删掉。
- **建议**：`total <= 0` 时不做删除（宁可留半成品也不误删）。

### 18. `_previousDone` 只增不减

- **位置**：`lib/features/transfers/transfers_controller.dart:69`
- **影响**：任务完成/失败后条目仍在 map 里，长时间批量下载会缓慢增长（每条约几十字节，量级很小）。
- **建议**：`_emit`/`_persist` 时清理不在 `state.tasks` 里的键。

### 19. 存储源表单对 `required` 的布尔字段校验恒为通过

- **位置**：`lib/features/sources/add_source_page.dart:123-133`
- **原因**：`'${_bools[name] ?? false}'` 永远是非空字符串（`"true"`/`"false"`）。
- **影响**：驱动里若把某个 bool 标成必填且要求为真，客户端不会拦，交给引擎报错。
- **建议**：bool 必填按「必须为 true」判定。

### 20. 新建存储的连通性验证走默认 `refresh: false`，可能命中缓存误判为通

- **位置**：`lib/features/sources/sources_controller.dart:101`
- **影响**：复用了一个已存在挂载路径的缓存时，新建即通过，之后打开才发现不可达。
- **建议**：验证时带 `refresh: true`（与健康探测口径一致）。

### 21. `PortAllocator.pick` 是经典 TOCTOU

- **位置**：`lib/core/sidecar/sidecar_config.dart:63-71`
- **影响**：bind(0) → close → 引擎再 bind 之间端口可能被抢；启动失败会换端口重试 3 次，实际能兜住。
- **建议**：保持现状即可，仅在日志里标注「端口冲突」便于排查。

### 22. 快速连续导航时「上次浏览位置」可能被旧路径覆盖

- **位置**：`lib/features/files/files_controller.dart:200`
- **原因**：`await store.saveBrowse(profile.id, normalized, ...)` 在 `seq` 校验之后、但仍可能在用户已进入新目录后完成。
- **影响**：下次启动恢复到上一次而不是最后停留的目录。
- **建议**：写入前再比对一次 `seq == _seq`。

### 23. `SecureStore.write` 失败只打日志，调用方无法感知

- **位置**：`lib/core/storage/secure_store.dart:27-41`
- **影响**：`_ensurePassword` 会认为口令已落钥匙串；实际失败时 `relogin()` 读不到口令，用户看到「本机缺少引擎凭据」。
- **建议**：`write` 返回 `bool`，关键路径（口令）失败时在启动页给出可操作提示。

### 24. 批量扫描的 BFS 队列无上限

- **位置**：`lib/features/files/file_actions.dart:248-296`
- **影响**：文件数有 `_maxFolderFiles` 兜底，但**目录**数没有；极端目录树（十万级空目录）会把队列和内存撑起来。
- **建议**：给 `queue.length` 也加一个上限，超出即 `truncated`。

---

## 已核对、确认没有问题的点

以下是我重点怀疑但确认无误的，列出来避免重复排查：

- **多流分段（0.5.8）**：`segments == 1` 确实完全不进新路径；206 / `Content-Range` 起止 / 流内截断 / 总字节断言 / 失败删文件 / 限速均分 / 单句柄串行写，逻辑闭环。
- **路径穿越**：`safePathSegment` 覆盖了 `..`、结尾点空格、Windows 保留名、超长；递归下载的每一级都过了它。
- **引擎安全配置**：监听 `127.0.0.1`、`https_port: -1`、关闭 s3/ftp/远程登录，没有把管理面暴露到局域网。
- **`toggle()` 的存储操作计数器**：`begin/endStorageOp` 有 `finally` 配对，不会泄漏导致「崩溃后永不自动重启」。
- **枚举反序列化**：`ServerHealth` / `TransferKind` / `TransferStatus` 的 `firstWhere` 都带 `orElse`，脏数据不会抛。
- **播放器**：`_errorSub` 有 cancel，`_player.dispose()` 在 `super.dispose()` 之前，流由框架接管。
- **API 重试**：429 只重试一次，`for` 循环不会无限转。
- **命令执行**：`Process.run('explorer'|'open'|'xdg-open', [path])` 不经 shell，无注入面。

## 建议的修复顺序

1. **P0-1 / P0-2**（传输并发与清除）—— 直接影响文件完整性，改动集中在一个文件
2. **P0-3 / P1-6 / P1-7**（进程收尾）—— 都集中在 `sidecar_manager`，可以一次改完
3. **P1-5 / P1-15**（dispose 期异常与定时器）
4. **P1-9 / P1-11**（两个「状态丢失」类缺陷，各几行）
5. 其余按需

P0-4 是产品决策，不建议改代码，但建议在 README 的安全边界一节写清。

---

## 修复状态（v0.5.9）

| 编号 | 问题 | 状态 | 落点 |
|---|---|---|---|
| P0-1 | 暂停/继续竞态导致双协程 + 令牌被误删 | ✅ 已修 | `transfers_controller.dart`：运行代次 `_runSeq` + 在跑协程登记 `_running` + `_launch`；失败判定改用「令牌是否被取消」 |
| P0-2 | `clearTasks` 不取消运行中任务 | ✅ 已修 | `transfers_controller.dart`：先 `cancel()` 再 `remove()` |
| P0-3 | 按 pid 盲杀进程 | ✅ 已修 | `sidecar_manager.dart`：`SidecarManager.processNameOf()` 校验进程名，不匹配不杀 |
| P0-4 | 固定口令的安全暴露面 | 📝 仅文档 | README 新增「固定口令的代价」一行；代码按产品决策保持不变 |
| P1-5 | dispose 后 `ref.read` 抛未捕获异常 | ✅ 已修 | `transfers_controller.dart`：`_emit` / `_run` 收尾统一判 `mounted` |
| P1-6 | stdout/stderr 订阅未保存 | ✅ 已修 | `sidecar_manager.dart`：保存订阅，`_closeLog` 先取消订阅再关 sink |
| P1-7 | 安全模式未确认进程退出即改库 | ✅ 已修 | `sidecar_manager.dart`：`waitProcessGone()`；`sidecar_controller.dart`：`quarantine` 先等进程消失 |
| P1-8 | `AppDatabase.instance()` 并发重复 open | ✅ 已修 | `app_database.dart`：缓存 `Future<Database>`，失败时清空以便重试 |
| P1-9 | 「清空缓存」标记在事务内被摘掉 | ✅ 已修 | `prefs.dart`：事务内只 `contains('*')`，标记随事务成功后统一清理 |
| P1-10 | 重命名不校验路径分隔符 | ✅ 已修 | `file_actions.dart`：拒绝 `/`、`\`、`.`、`..` |
| P1-11 | 探测期间丢刷新请求 | ✅ 已修 | `storage_health.dart`：`_probePending` 补跑一轮 |
| P1-12 | `_downloadDir` 在 try 外 | ✅ 已修 | `transfers_controller.dart`：纳入 try，返回可展示的错误 |
| P1-13 | 派生 getter 全表遍历 + 每秒重建 | ✅ 已修 | `transfers_controller.dart`：新增不物化的 count getter；`_tick` 静止时不重建 |
| P1-14 | 上传 `Content-Length` 与实际不符 | ✅ 已修 | `openlist_api.dart`：`_counted` 统计实际字节，完成后校验 |
| P1-15 | `FilesNotifier` 无 `dispose` | ✅ 已修 | `files_controller.dart`：补 `dispose` 取消骨架屏定时器 |
| P1-16 | `SessionState.copyWith` 的 error 语义 | ✅ 已修 | `session.dart`：加 `clearError`；调用点同步 |
| P2-17 | `total == 0` 时误删完整文件 | ✅ 已修 | `transfers_controller.dart`：大小未知时不删 |
| P2-18 | `_previousDone` 只增不减 | ✅ 已修 | `transfers_controller.dart`：`_emit` 兜底清理 |
| P2-19 | 必填布尔项拦不住 | ✅ 已修 | `add_source_page.dart`：必填 bool 必须为 true |
| P2-20 | 新建源的连通性验证命中缓存 | ✅ 已修 | `sources_controller.dart`：验证走 `refresh: true` |
| P2-21 | 端口分配 TOCTOU | 📝 仅注释 | `sidecar_config.dart`：补注释说明「有重试兜底」 |
| P2-22 | 浏览位置被旧路径覆盖 | ✅ 已修 | `files_controller.dart`：写浏览位置前复核代次 |
| P2-23 | `SecureStore.write` 失败不可感知 | ✅ 已修 | `secure_store.dart`：`write` 返回 `bool`；`sidecar_manager` 记录日志 |
| P2-24 | 扫描目录队列无上限 | ✅ 已修 | `file_actions.dart`：新增 `_maxFolderDirs = 5000` |

### 仍未闭环的存疑点

1. **「必填布尔项」语义来自引擎的表单定义**，本次按「必须为 true」处理。若某个驱动把 `required` 的布尔项允许为 false，该驱动的表单会被误拦。需要在真机上加几个驱动验证。
2. **进程名校验依赖平台工具**（Windows `tasklist`、类 Unix `ps`）。工具缺失或被安全软件拦截时会判定为「无法确认」→ 不杀进程 → 引擎可能残留（下次启动会接管）。
3. **多流分段不支持断点续传**（0.5.8 的既定取舍），本次未改。
4. **P0-1 这类竞态没有自动化测试**覆盖，只能靠手工用例（暂停后立刻继续）复现验证。

---

## 附：静态检查清理（同一批提交）

`flutter analyze` 之前还有 12 条 warning（不影响构建，但都是**失效代码**），本次一并清掉，现在 analyze 输出 **0 warning / 0 error**：

| 位置 | 问题 | 处理 |
|---|---|---|
| `lib/features/files/parts/files_mobile.dart` | `_AppBarBtn.badge` 参数从未被赋值 → 整段 Stack 徽标绘制是死代码 | 删除参数与约 30 行死代码 |
| `lib/features/settings/parts/settings_mobile.dart` | `_MobileTile.danger` 从未被赋值 → 危险色分支恒不生效 | 删除参数，固定配色 |
| `lib/features/transfers/transfers_controller.dart` | `_prefs` 字段、`_persistKey` 常量只写不读 | 删除 |
| `lib/features/transfers/transfers_controller.dart` | 未使用 import `../files/files_controller.dart`、`../../core/storage/prefs.dart` | 删除（`filesProvider` 实际来自 `app/providers.dart`） |
| `lib/features/transfers/transfers_page.dart` | 未使用 import `package:go_router/go_router.dart` | 删除 |
| `lib/features/files/files_page.dart` | 未使用 import `../../core/i18n/zh.dart` | 删除 |
| `lib/features/settings/settings_sidebar.dart` | 未使用 import `../../app/providers.dart` | 删除 |
| `lib/features/settings/parts/sections_sources.dart` | 两处 `switch` 的 `default` 分支被前面的 case 覆盖（不可达） | 删除 default，保留 `case DriverGroup.other` |
| `lib/core/widgets/ol_controls.dart` | 未使用的局部变量 `p` | 删除 |
| `lib/features/files/file_actions.dart` | 未使用的局部变量 `files` | 删除 |

---

## 勘误：P2-19 的修法是错的（v0.5.10 已回退）

**P2-19** 原文：「存储源表单对 `required` 的布尔字段校验恒为通过」→ 我在 v0.5.9 按
「required 的布尔项必须为 true」修复。**这个修法是错的，并且造成了一个阻断性回归。**

上游事实（`internal/op/driver.go` 的 `getMainItems`）：

```go
items = append(items, driver.Item{
    Name:     "disable_index",
    Type:     conf.TypeBool,
    Default:  "false",
    Required: true,
})
items = append(items, driver.Item{
    Name:     "enable_sign",
    Type:     conf.TypeBool,
    Default:  "false",
    Required: true,
})
```

`Default: "false"` + `Required: true` 自相矛盾 —— 说明 `Required` 对布尔项的含义是
「这个字段必须出现在表单里」（true / false 都是合法值），**不是**「必须为 true」。

v0.5.9 的实现会让 `disable_index` / `enable_sign` 两个默认关闭的开关成为提交门槛，
结果是**所有驱动都无法添加存储**（除非用户手动把两个开关都打开）。

**v0.5.10 已回退**：布尔项不再做「必须为 true」的校验，并加了注释说明上游语义。
本条同时作为本报告的实证 —— 修复前必须核对上游对该字段的实际语义，不能凭字段名推断。

新增的全局默认值覆盖（`kGlobalFormDefaults`）与回退相互独立：它只改表单初值，
不改校验口径。
