# Firecrawl MCP服务器使用指南

## 概述
Firecrawl MCP服务器是一个强大的网页抓取和网络搜索工具，通过Model Context Protocol (MCP)集成到开发环境中。它提供了8个主要工具，用于网页内容抓取、网站映射、搜索和数据提取。

## 可用工具列表

### 1. firecrawl_scrape - 单页抓取
从单个URL抓取内容，支持JavaScript渲染和高级选项。

**参数:**
- `url`: 目标网页URL
- `formats`: 输出格式，如["markdown"]或["html"]
- `onlyMainContent`: 是否只提取主要内容
- `waitFor`: 等待页面加载的时间（毫秒）
- `timeout`: 超时时间（毫秒）
- `mobile`: 是否模拟移动设备
- `includeTags`: 包含的HTML标签
- `excludeTags`: 排除的HTML标签

**示例:**
```json
{
  "url": "https://example.com",
  "formats": ["markdown"],
  "onlyMainContent": true,
  "waitFor": 1000
}
```

### 2. firecrawl_batch_scrape - 批量抓取
高效抓取多个URL，内置速率限制和并行处理。

**参数:**
- `urls`: URL数组
- `options`: 抓取选项

**示例:**
```json
{
  "urls": ["https://example1.com", "https://example2.com"],
  "options": {
    "formats": ["markdown"],
    "onlyMainContent": true
  }
}
```

### 3. firecrawl_check_batch_status - 检查批量状态
检查批量操作的状态。

**参数:**
- `id`: 批量操作ID

### 4. firecrawl_map - 网站映射
映射网站以发现所有索引URL。

**参数:**
- `url`: 基础URL
- `search`: 搜索词过滤URL
- `sitemap`: sitemap使用方式："include"、"skip"或"only"
- `includeSubdomains`: 是否包含子域名
- `limit`: 返回的最大URL数量
- `ignoreQueryParameters`: 是否忽略查询参数

**最佳用途:** 在决定抓取内容之前发现网站上的URL；查找网站的特定部分。

### 5. firecrawl_search - 网络搜索
搜索网络并可选地从搜索结果中提取内容。

**参数:**
- `query`: 搜索查询
- `limit`: 结果数量限制
- `lang`: 语言代码
- `country`: 国家代码
- `scrapeOptions`: 抓取选项

### 6. firecrawl_crawl - 异步爬取
启动具有高级选项的异步爬取。

**参数:**
- `url`: 起始URL
- `maxDepth`: 最大深度
- `limit`: 最大URL数量
- `allowExternalLinks`: 是否允许外部链接
- `deduplicateSimilarURLs`: 是否去重相似URL

### 7. firecrawl_check_crawl_status - 检查爬取状态
检查爬取作业的状态。

**参数:**
- `id`: 爬取作业ID

### 8. firecrawl_extract - 结构化数据提取
使用LLM能力从网页提取结构化信息。

**参数:**
- `urls`: URL数组
- `prompt`: LLM提取的自定义提示
- `systemPrompt`: 指导LLM的系统提示
- `schema`: 结构化数据提取的JSON模式
- `allowExternalLinks`: 是否允许从外部链接提取
- `enableWebSearch`: 是否启用网络搜索获取额外上下文
- `includeSubdomains`: 是否包含子域名

## 使用场景示例

### 场景1: 抓取技术文档
```json
{
  "tool": "firecrawl_scrape",
  "parameters": {
    "url": "https://docs.flutter.dev/get-started",
    "formats": ["markdown"],
    "onlyMainContent": true,
    "includeTags": ["article", "main", "section"]
  }
}
```

### 场景2: 映射竞争对手网站
```json
{
  "tool": "firecrawl_map",
  "parameters": {
    "url": "https://competitor.com",
    "search": "product",
    "limit": 50,
    "sitemap": "include"
  }
}
```

### 场景3: 搜索最新技术文章
```json
{
  "tool": "firecrawl_search",
  "parameters": {
    "query": "Flutter state management 2024",
    "limit": 10,
    "lang": "en",
    "scrapeOptions": {
      "formats": ["markdown"],
      "onlyMainContent": true
    }
  }
}
```

### 场景4: 提取产品信息
```json
{
  "tool": "firecrawl_extract",
  "parameters": {
    "urls": ["https://example.com/products/1"],
    "prompt": "提取产品信息，包括名称、价格、描述和规格",
    "schema": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "price": {"type": "number"},
        "description": {"type": "string"},
        "specifications": {"type": "array", "items": {"type": "string"}}
      },
      "required": ["name", "price"]
    }
  }
}
```

## 配置说明

### 环境变量
当前配置包含以下环境变量：
- `FIRECRAWL_API_KEY`: fc-a32f4ffc8aec4734b68b96d923941d42
- `FIRECRAWL_RETRY_MAX_ATTEMPTS`: 5 (重试次数)
- `FIRECRAWL_RETRY_INITIAL_DELAY`: 2000 (初始延迟毫秒)
- `FIRECRAWL_RETRY_MAX_DELAY`: 30000 (最大延迟毫秒)
- `FIRECRAWL_RETRY_BACKOFF_FACTOR`: 3 (退避因子)
- `FIRECRAWL_CREDIT_WARNING_THRESHOLD`: 2000 (信用警告阈值)
- `FIRECRAWL_CREDIT_CRITICAL_THRESHOLD`: 500 (信用临界阈值)

### 重试行为
配置的重试行为：
- 第1次重试: 2秒延迟
- 第2次重试: 6秒延迟 (2 × 3)
- 第3次重试: 18秒延迟 (6 × 3)
- 第4次重试: 30秒延迟 (达到最大延迟)
- 第5次重试: 30秒延迟

## 最佳实践

### 1. 速率限制管理
- 使用批量操作而不是单个请求
- 合理设置重试参数
- 监控信用使用情况

### 2. 内容提取优化
- 使用`onlyMainContent: true`提取主要内容
- 指定`includeTags`和`excludeTags`提高准确性
- 对于动态内容，适当增加`waitFor`时间

### 3. 错误处理
- 检查批量操作状态
- 处理速率限制错误
- 监控信用阈值警告

### 4. 性能考虑
- 对于大型网站，先使用`firecrawl_map`了解结构
- 使用批量操作提高效率
- 合理设置超时时间

## 故障排除

### 常见问题
1. **连接超时**: 增加`timeout`参数值
2. **内容不完整**: 增加`waitFor`参数值，确保JavaScript渲染完成
3. **速率限制**: 检查重试配置，考虑降低请求频率
4. **信用不足**: 监控信用使用，调整抓取策略

### 日志信息
Firecrawl MCP服务器提供详细的日志：
- `[INFO] Firecrawl MCP Server initialized successfully`
- `[INFO] Starting scrape for URL: ...`
- `[WARNING] Credit usage has reached warning threshold`
- `[ERROR] Rate limit exceeded, retrying in 2s...`

## 与当前项目的集成

### Flutter项目应用场景
1. **文档抓取**: 抓取Flutter官方文档用于离线参考
2. **竞争对手分析**: 映射和分析竞争对手的移动应用功能
3. **技术研究**: 搜索最新的移动开发趋势和最佳实践
4. **内容聚合**: 收集相关技术文章和教程

### 示例工作流
```mermaid
graph LR
    A[需求分析] --> B[使用firecrawl_search搜索]
    B --> C[使用firecrawl_map映射相关网站]
    C --> D[使用firecrawl_scrape抓取关键页面]
    D --> E[使用firecrawl_extract提取结构化数据]
    E --> F[数据整合到Flutter应用]
```

## 后续开发建议

### 功能扩展
1. 添加自定义解析规则
2. 集成缓存机制减少重复请求
3. 添加数据导出功能
4. 创建可视化仪表板监控使用情况

### 安全考虑
1. 实现API密钥轮换机制
2. 添加请求白名单
3. 实施使用量配额
4. 添加审计日志

---

*最后更新: 2025-12-30*  
*配置状态: 已计划，待实施*