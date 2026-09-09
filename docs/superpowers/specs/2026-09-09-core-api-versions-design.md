# Core API 版本目录解码设计

## 这批要解决的问题

上一批已经能构造 `GET /api`，但请求返回后还没有对应的数据边界。我这次只解析 Kubernetes `APIVersions` 响应里的 `versions`，让调用者知道集群公开了哪些 core API 版本。解析结果保留 API Server 的原始顺序，不做排序或去重。

## 公开接口

我会在现有 `discovery` 包中增加：

- `decode_api_versions(body: String) -> Result[ApiVersions, String>`
- `ApiVersions::versions() -> ArrayView[String]`
- `ApiVersions::supports(version: String) -> Bool`

`ApiVersions` 自己持有版本数组，对外只暴露只读视图。`supports` 使用精确、区分大小写的字符串匹配，与 API Server 返回内容保持一致。

## 解码与错误边界

输入必须是 JSON 对象，并包含数组类型的 `versions`。数组中的每一项必须是字符串；任何一项结构错误都会拒绝整份结果，并在错误里指出 `versions[index]`。空数组是合法结果，未知字段继续忽略。

错误采用当前 Discovery 包已有的 `Result[..., String]` 风格，不在这一小批中引入新的错误类型。

## 验证方式

我会先增加三个黑盒场景：正常顺序与查询、合法空目录、非法 JSON/缺字段/错误字段类型/错误数组元素。测试应先因 `decode_api_versions` 不存在而失败，再以最小实现转绿。

完成后运行局部测试、严格 MoonBit 检查、全库 native 测试、当前稳定版格式检查、`moon info` 接口审阅和 `git diff --check`。验证通过后功能提交直接进入 `main`，推送前核对 GitHub 登录账号及远程 owner，推送后等待对应 GitHub Actions。

## 本批明确不做

这次不解析 `/apis` 的 `APIGroupList`，不处理 `serverAddressByClientCIDRs`，不发起网络请求，也不增加缓存、刷新和版本优先级策略。后续 named API group 解码会沿用这次确定的有序、整份拒绝和只读访问原则。
