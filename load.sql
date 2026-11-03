-- =========================================================
-- load.sql : 합성 데이터 적재 + 시퀀스 동기화
-- 실행 순서: schema.sql → load.sql → V2__add_sales_index.sql
-- 전제: generate.py로 만든 csv 5개가 컨테이너의 /tmp/data/ 에 있음
-- =========================================================

-- 중간에 오류가 나면 즉시 멈춘다 (뒤 단계가 반쯤 실행되는 것을 막음)
\set ON_ERROR_STOP on

-- 전부 성공하거나 전부 취소되도록 하나의 트랜잭션으로 묶는다
BEGIN;

-- ---------- 1. 적재: 참조 순서대로 ----------
-- 참조당하는 테이블(platform, content)이 먼저, 참조하는 테이블이 나중.
-- 순서가 바뀌면 외래키 제약에 걸려 적재가 실패한다.

COPY platform   (platform_id, platform_name, country, file_format)
  FROM '/tmp/data/platform.csv'   WITH (FORMAT csv, HEADER true);

COPY content    (content_id, title, artist, release_date)
  FROM '/tmp/data/content.csv'    WITH (FORMAT csv, HEADER true);

COPY contract   (contract_id, platform_id, content_id, rate, start_date)
  FROM '/tmp/data/contract.csv'   WITH (FORMAT csv, HEADER true);

COPY sales_raw  (sales_id, platform_id, content_id, sales_month, play_count, amount, currency)
  FROM '/tmp/data/sales_raw.csv'  WITH (FORMAT csv, HEADER true);

COPY settlement (settlement_id, sales_id, contract_id, applied_rate, settled_amount, settled_at)
  FROM '/tmp/data/settlement.csv' WITH (FORMAT csv, HEADER true);

-- ---------- 2. 시퀀스 동기화 ----------
-- id를 csv에서 직접 넣었기 때문에 SERIAL 시퀀스는 여전히 1에 머물러 있다.
-- 이대로 새 행을 INSERT하면 id=1이 다시 발급되어 duplicate key 오류가 난다.
-- 각 시퀀스를 실제 최대 id에 맞춰, 다음 INSERT가 최대 id + 1을 받게 한다.

SELECT setval(pg_get_serial_sequence('platform',   'platform_id'),   (SELECT MAX(platform_id)   FROM platform));
SELECT setval(pg_get_serial_sequence('content',    'content_id'),    (SELECT MAX(content_id)    FROM content));
SELECT setval(pg_get_serial_sequence('contract',   'contract_id'),   (SELECT MAX(contract_id)   FROM contract));
SELECT setval(pg_get_serial_sequence('sales_raw',  'sales_id'),      (SELECT MAX(sales_id)      FROM sales_raw));
SELECT setval(pg_get_serial_sequence('settlement', 'settlement_id'), (SELECT MAX(settlement_id) FROM settlement));

COMMIT;

-- ---------- 3. 통계 갱신 ----------
-- 대량 적재 직후에는 플래너의 통계가 비어 있어 실행계획이 부정확할 수 있다.
ANALYZE;

-- ---------- 4. 적재 확인 ----------
-- 기대값: platform 31 / content 350 / contract 10,850 / sales_raw 130,200 / settlement 127,512
SELECT 'platform'   AS table_name, COUNT(*) AS row_count FROM platform
UNION ALL SELECT 'content',    COUNT(*) FROM content
UNION ALL SELECT 'contract',   COUNT(*) FROM contract
UNION ALL SELECT 'sales_raw',  COUNT(*) FROM sales_raw
UNION ALL SELECT 'settlement', COUNT(*) FROM settlement;
