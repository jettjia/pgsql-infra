-- ParadeDB 初始化脚本
-- 在首次启动时执行

-- 启用必要扩展(带 IF NOT EXISTS,即使挂载第二次也安全)
CREATE EXTENSION IF NOT EXISTS pg_search;
CREATE EXTENSION IF NOT EXISTS vector;
