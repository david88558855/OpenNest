/// 面向用户的文案本地化。
///
/// 引擎返回的驱动名、字段名、选项值与帮助文案都是英文；这里统一映射为中文，
/// 未收录的项退回原始标识（保证可用性），但不再把英文帮助直接显示出来。
library;

const Map<String, String> _driverLabels = {
  'Local': '本地存储',
  'WebDav': 'WebDAV 服务器',
  'S3': 'S3 对象存储',
  'Doge': 'S3 兼容存储',
  'Azure Blob Storage': 'Azure 对象存储',
  'USS': '又拍云存储',
  'Bunny Storage': 'Bunny 存储',
  'Seafile': '海文件',
  'FTP': 'FTP 服务器',
  'Sftp': 'SFTP 服务器',
  'SMB': 'SMB 共享',
  'OpenList': '远程 OpenList',
  'AList V3': '远程 AList',
  'Alias': '别名目录',
  'Virtual': '虚拟目录',
  'Chunk': '分片目录',
  'AutoIndex': '自动索引',
  'Crypt': '加密目录',
  'UrlTree': '链接树',
  'Strm': 'STRM 索引',
  'Aliyundrive': '阿里云盘',
  'AliyundriveOpen': '阿里云盘（开放）',
  'AliyundriveShare': '阿里云盘分享',
  'BaiduNetdisk': '百度网盘',
  'BaiduPhoto': '百度相册',
  'Quark': '夸克网盘',
  'QuarkOpen': '夸克网盘（开放）',
  'UC': '夸克 UC 网盘',
  '115 Cloud': '115 网盘',
  '115 Open': '115 网盘（开放）',
  '123 Cloud': '123 云盘',
  '123 Open': '123 云盘（开放）',
  '139Yun': '移动云盘',
  '189Cloud': '天翼云盘',
  '189CloudPC': '天翼云盘（电脑版）',
  '189CloudTV': '天翼云盘（电视版）',
  'Thunder': '迅雷云盘',
  'ThunderExpert': '迅雷云盘（专家模式）',
  'PikPak': 'PikPak 网盘',
  'Onedrive': '微软 OneDrive',
  'OnedriveAPP': '微软 OneDrive（应用）',
  'Onedrive Sharelink': 'OneDrive 分享链接',
  'GoogleDrive': '谷歌云端硬盘',
  'GooglePhoto': '谷歌相册',
  'Dropbox': 'Dropbox 网盘',
  'Mega': 'MEGA 网盘',
  'Lanzou': '蓝奏云',
  'ILanzou': '蓝奏云（备用线路）',
  'Weiyun': '腾讯微云',
  'WoPan': '联通沃盘',
  'MoPan': '移动云盘',
  'YandexDisk': 'Yandex 网盘',
  'Terabox': 'TeraBox 网盘',
  'MediaFire': 'MediaFire 网盘',
  'Teambition': 'Teambition',
  'GitHub': 'GitHub 仓库',
  'GitHubReleases': 'GitHub 发布',
  'CNBReleases': 'CNB 发布',
  'Cloudreve': 'Cloudreve',
  'Kodbox': '可道云',
  'Emby': 'Emby 媒体库',
  'ProtonDrive': 'Proton 网盘',
  'Teldrive': 'Telegram 网盘',
  'Halalcloud': '哈喽云盘',
  'Wopan': '联通沃盘',
  'Doubao': '豆包网盘',
};

const Map<String, String> _driverShortTags = {
  'Local': '本地',
  'WebDav': 'WebDAV',
  'Sftp': 'SFTP',
  'FTP': 'FTP',
  'SMB': 'SMB',
  'S3': '对象',
  'Doge': '对象',
  'OpenList': '级联',
  'AList V3': '级联',
  'Crypt': '加密',
  'UrlTree': '链接',
  'Strm': '索引',
};

const Map<String, String> _fieldLabels = {
  // 公共字段
  'mount_path': '挂载路径',
  'order': '排序值',
  'remark': '备注',
  'cache_expiration': '缓存时长（秒）',
  'custom_cache_policies': '自定义缓存策略',
  'web_proxy': '网页代理',
  'webdav_policy': 'WebDAV 策略',
  'proxy_range': '代理范围',
  'down_proxy_url': '下载代理地址',
  'disable_proxy_sign': '关闭代理签名',
  'order_by': '排序字段',
  'order_direction': '排序方向',
  'extract_folder': '解压目录',
  'disable_index': '关闭索引',
  'enable_sign': '开启签名',
  'seed_policy': '秒传策略',
  // 通用连接
  'address': '服务器地址',
  'username': '用户名',
  'password': '密码',
  'root_folder_path': '根目录',
  'root_folder_id': '根目录编号',
  'tls_insecure_skip_verify': '跳过证书校验',
  'vendor': '服务商',
  'encoding': '编码',
  'cwd_list': '目录列表',
  'share_name': '共享名',
  'private_key': '私钥',
  'passphrase': '私钥口令',
  'ignore_symlink_error': '忽略软链接错误',
  // 对象存储
  'bucket': '存储桶',
  'endpoint': '接入地址',
  'region': '区域',
  'access_key_id': '访问密钥',
  'secret_access_key': '访问密钥密码',
  'session_token': '会话令牌',
  'custom_host': '自定义域名',
  'sign_url_expire': '直链有效期（秒）',
  'force_path_style': '强制路径样式',
  'list_object_version': '列表版本',
  'remove_bucket': '移除存储桶',
  'add_filename_to_disposition': '下载文件名参数',
  'enable_direct_upload': '允许直传',
  'direct_upload_host': '直传域名',
  'user_agent': '客户端标识',
  'placeholder': '占位图',
  'container_name': '容器名称',
  'operator_name': '操作员账号',
  'operator_password': '操作员密码',
  'anti_theft_chain_token': '防盗链令牌',
  // 网盘与分享
  'refresh_token': '刷新令牌',
  'client_id': '客户端编号',
  'client_secret': '客户端密钥',
  'redirect_uri': '回调地址',
  'site_id': '站点编号',
  'chunk_size': '分片大小',
  'share_id': '分享编号',
  'share_pwd': '分享提取码',
  'share_password': '分享提取码',
  'url': '分享链接',
  'cookie': '登录凭证',
  'base_path': '基础路径',
  'page_size': '每页数量',
  'limit_rate': '限速（字节/秒）',
  'alipan_type': '网盘类型',
  'drive_type': '存储类型',
  'rapid_upload': '秒传',
  'remove_way': '删除方式',
  'client_temp_dir': '客户端临时目录',
  'repo_id': '仓库编号',
  'repo_pwd': '仓库密码',
  'url_structure': '链接结构',
  'head_size': '头部大小',
  'paths': '路径列表',
  'site_url': '站点地址',
  'filter_file_types': '过滤文件类型',
  'download_file_types': '下载文件类型',
  'min_file_size': '最小文件大小',
  'without_url': '不含地址',
  'filename_encryption': '文件名加密',
  'directory_name_encryption': '目录名加密',
  'remote_path': '远端路径',
  'encrypted_suffix': '加密后缀',
  'filename_encoding': '文件名编码',
};

const Map<String, String> _optionLabels = {
  '302_redirect': '302 跳转',
  'use_proxy_url': '使用代理地址',
  'native_proxy': '本机代理',
  'name': '名称',
  'size': '大小',
  'modified': '修改时间',
  'asc': '升序',
  'desc': '降序',
  'front': '前置',
  'back': '后置',
  'inherit': '跟随全局',
  'on': '开启',
  'off': '关闭',
  'v1': '版本 1',
  'v2': '版本 2',
  'sharepoint': 'SharePoint',
  'other': '其它',
  'off_standard': '不加密',
  'standard': '标准加密',
  'obfuscate': '混淆',
  'base64': 'Base64',
  'base32': 'Base32',
  'base32768': 'Base32768',
  'trash': '回收站',
  'delete': '直接删除',
  'global': '国际版',
  'cn': '世纪互联',
  'us': '美国政府版',
  'de': '德国版',
  'account': '账号密码',
  'qrcode': '扫码登录',
  'official': '官方接口',
  'crack': '第三方接口',
};

/// 引擎返回的驱动帮助文案（英文）逐条翻译；未收录的返回空串，界面不展示。
const Map<String, String> _helpLabels = {
  'The path you want to mount to, it is unique and cannot be repeated': '挂载路径，全局唯一且不可重复',
  'use to sort': '用于排序',
  'The cache expiration time for this storage': '该存储的目录缓存时长',
  'The cache expiration rules for this storage': '该存储的自定义缓存规则',
  'Need to enable proxy': '需要先开启代理',
  'Disable sign for Download proxy URL': '下载代理地址是否关闭签名',
  'Override automatic transfer-seed generation for this storage': '覆盖该存储的秒传策略',
};

String driverLabel(String key) => _driverLabels[key] ?? key;

/// 侧边栏等窄区域的短标签。
String driverShortTag(String key) => _driverShortTags[key] ?? _fallbackTag(key);

String _fallbackTag(String key) {
  final label = driverLabel(key);
  if (label.contains('对象')) return '对象';
  if (label.contains('OpenList') || label.contains('AList')) return '级联';
  if (label.contains('目录') || label.contains('索引')) return '目录';
  if (label.contains('网盘') || label.contains('云')) return '网盘';
  return label.length <= 4 ? label : '其它';
}

String fieldLabel(String raw) {
  final label = _fieldLabels[raw];
  if (label != null) return label;
  return raw;
}

String fieldHelp(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  return _helpLabels[raw.trim()] ?? '';
}

String optionLabel(String value) => _optionLabels[value] ?? value;

/// 存储源状态：引擎返回 `work` / `ok` / `disabled` 等原始标识。
String storageStatusLabel(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return '待加载';
  if (value == 'work' || value == 'ok' || value == '1') return '正常';
  if (value == 'disabled') return '已停用';
  if (value == 'error' || value == 'failed') return '异常';
  return '未知';
}
