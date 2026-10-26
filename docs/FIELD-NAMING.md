# 存储表单字段：与 OpenList Web 端的对齐说明

本文记录客户端「添加存储源」表单与 **OpenList Web 端**添加同类型存储时
字段集合、中文名与取值格式的对照关系，以及已修正的差异。

数据来源：
- 引擎接口 `GET /api/admin/driver/list`（93 个驱动、306 个字段）
- OpenList 官方前端 `OpenList-Frontend/src/lang/en/drivers.json`（按驱动索引字段标签）
- OpenList Web 端实际表单截图

## 一、字段集合

OpenList Web 端的表单 = 存储顶层字段 + 引擎 `common` 字段 + 驱动 `additional` 字段。

| 层次 | 含义 | 客户端处理 |
|---|---|---|
| 顶层 | `mount_path` / `order` / `remark` / `cache_expiration` | 客户端自己处理（挂载路径由名称派生、名称即备注、独立的缓存过期时间输入框、序号在通用选项里） |
| `common` | 所有驱动共享的通用项：排序、缓存策略、网盘代理、WebDAV 策略、下载代理网址、种子策略…… | **0.5.0 补齐**（此前整组漏掉，用户无法配置） |
| `additional` | 驱动特有项（root_folder_path、username、password……） | 一直有 |

> **重要**：引擎把 `common` 字段定义在**存储顶层**，不在 `addition` 里。
> 提交时必须分开：`common → 请求体顶层`，`additional → addition`。
> 混在一起引擎会忽略 addition 里的未知键。

## 二、字段中文名对照（对齐 Web 端）

| 引擎字段 | 修正前 | 修正后 | 说明 |
|---|---|---|---|
| `url` | 分享链接 | **服务器地址** | 分享类驱动（Onedrive Sharelink / OpenListShare / AliyundriveShare）仍为「分享链接」，由驱动级映射区分 |
| `order` | 排序值 | **序号** | |
| `order_by` | 排序字段 | **用于排序** | |
| `order_direction` | 排序方向 | 排序方向 | 未变 |
| `cache_expiration` | 缓存时长（秒） | **缓存过期时间（秒）** | 界面手写文案同步（设置页为「（分钟）」） |
| `custom_cache_policies` | 自定义缓存策略 | 自定义缓存策略 | 未变 |
| `web_proxy` | 网页代理 | **网盘代理** | |
| `webdav_policy` | WebDAV 策略 | WebDAV 策略 | 未变 |
| `down_proxy_url` | 下载代理地址 | **下载代理网址** | |
| `proxy_range` | 代理范围 | 代理范围 | 未变 |
| `disable_index` | 关闭索引 | **禁用索引** | |
| `enable_sign` | 开启签名 | **启用签名** | |
| `disable_proxy_sign` | 关闭代理签名 | **禁用代理签名** | |
| `seed_policy` | 秒传策略 | **种子策略** | |
| `extract_folder` | 解压目录 | 解压目录 | 未变 |
| `remark` | 备注 | 备注 | 未变 |
| `mount_path` | 挂载路径 | 挂载路径 | 未变 |

### 补齐的 5 个字段（此前无中文名，直接显示英文）

| 引擎字段 | 中文名 |
|---|---|
| `bbsid` | 业务标识 |
| `generate_torrent` | 生成种子文件 |
| `ignore_jwt_check` | 忽略 JWT 校验 |
| `order_desc` | 倒序排列 |
| `writable` | 可写入 |

### 统一掉的同义异名

| 引擎字段 | 修正前 | 修正后 | 统一到 |
|---|---|---|---|
| `cookie` | 登录凭证 | **Cookie** | 与 `cookies` 一致 |
| `cookies` | 登录 Cookie | **Cookie** | 与 `cookie` 一致 |
| `phone` | 手机号 | **手机号码** | 与 `phone_number` 一致 |
| `share_link` | 生成分享链接 | **使用分享链接下载** | 与 `use_share_link` 一致（bool 开关） |
| `access_key_id` | 访问密钥 | **访问密钥编号** | 与 `access_key` 区分 |
| `drive_type` | 存储类型 | **网盘类型** | 与 `alipan_type` 区分 |
| `cwd_list` | 目录列表 | **按工作目录列出** | 按引擎语义 |
| `item_xpath` | 条目 XPath | **文件条目 XPath** | |
| `user_agent` | 客户端标识 | **客户端标识（User-Agent）** | 补协议名 |

## 三、下拉选项

引擎 88 个选项值，客户端此前只覆盖 57 个，其余直接显示英文（如 `file_name`、
`302_redirect`）。现已补齐 68 条，覆盖 86/88。

| 引擎选项 | 修正前 | 修正后 |
|---|---|---|
| `302_redirect` | 302 跳转 | **302 重定向**（与 Web 端一致） |
| `0` / `1` | 关闭 / 开启 | **原样显示**（实为排序规则编号，翻译反而看不懂） |

`optionLabel()` 对纯数字原样返回，其余走映射表。

## 四、审查中发现并修复的其他缺陷

| # | 严重度 | 位置 | 问题 | 修法 |
|---|---|---|---|---|
| 1 | **崩溃** | `add_source_page.dart` `_textField` | 引擎有 5 个 `type=text` 的机密字段（`private_key`/`mail_cookies`/`accesstoken`/`qrcode_token`/`gpg_private_key`），`obscureText` 与 `maxLines>1` 同时使用会触发 Flutter 断言 —— 选到 SFTP、139Yun 等驱动时表单直接崩 | 机密字段强制单行 |
| 2 | **安全** | `zh.dart` `isSecretFieldName` | 关键字表漏了 `pwd`，导致 `pwd`（115 系）与 `repoPwd`（GitHub）密码明文显示 | 补 `pwd`；新增不遮蔽白名单 `share_pwd`（提取码要看得见） |
| 3 | 健壮性 | `file_actions.dart` `_loadText` | 预览文本用裸 `Dio()`，无任何超时，服务端不回数据时永远转圈 | 补 connect 10s / receive 20s |
| 4 | 一致性 | `openlist_api.dart` | 删除与启停接口手工拼 `?id=` 字符串 | 新增 `_postQuery`，由 dio 负责编码 |
