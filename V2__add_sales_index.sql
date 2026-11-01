-- V2: 플랫폼×곡 조회용 복합 인덱스
-- 근거: EXPLAIN ANALYZE 결과 Seq Scan 11.885ms → Bitmap Index Scan 0.067ms
CREATE INDEX idx_sales_platform_content ON sales_raw (platform_id, content_id);
