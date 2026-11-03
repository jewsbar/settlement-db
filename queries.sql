-- =========================================================
-- queries.sql : 미정산 조회와 월별 정산 현황
-- 미정산 = sales_raw에는 있고 settlement에는 없는 매출
-- 정답(generate.py 생성 시점 기록): 미정산 2,688건
-- =========================================================

-- ---------- 1. 미정산 건수 ----------
-- 엑셀로 치면: 매출 시트의 각 행에 대해 정산 시트에서 COUNTIF = 0 인 행만 센다.
-- 기대값: 2688
SELECT COUNT(*) AS unsettled_count
FROM sales_raw s
WHERE NOT EXISTS (
  SELECT 1
  FROM settlement st
  WHERE st.sales_id = s.sales_id
);

-- ---------- 2. 미정산 내역 ----------
-- 1번과 같은 조건에 JOIN으로 플랫폼명·곡명을 붙인다 (엑셀의 VLOOKUP).
-- 화면 확인용이라 50건만 보여준다. 건수는 1번 쿼리로 확인한다.
SELECT s.sales_id,
       s.sales_month,
       p.platform_name,
       c.title,
       s.amount
FROM sales_raw s
JOIN platform p ON p.platform_id = s.platform_id
JOIN content  c ON c.content_id  = s.content_id
WHERE NOT EXISTS (
  SELECT 1
  FROM settlement st
  WHERE st.sales_id = s.sales_id
)
ORDER BY s.sales_month, s.sales_id
LIMIT 50;

-- ---------- 3. 월별 정산 현황 ----------
-- LEFT JOIN: 정산이 없는 매출도 버리지 않고 남긴다 (짝이 없으면 st 칸은 NULL).
-- COUNT(*)는 전체 행, COUNT(st.settlement_id)는 NULL을 빼고 센다 → 차이가 미정산.
-- 기대값: 12개월 합계 매출 130,200건 / 정산 127,512건 / 미정산 2,688건
SELECT s.sales_month,
       COUNT(*)                          AS sales_count,
       COUNT(st.settlement_id)           AS settled_count,
       COUNT(*) - COUNT(st.settlement_id) AS unsettled_count,
       SUM(s.amount)                     AS sales_amount,
       SUM(st.settled_amount)            AS settled_amount
FROM sales_raw s
LEFT JOIN settlement st ON st.sales_id = s.sales_id
GROUP BY s.sales_month
ORDER BY s.sales_month;
