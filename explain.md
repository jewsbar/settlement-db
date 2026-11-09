# 실행계획 비교: 복합 인덱스 전후

`sales_raw`(130,200행)에서 플랫폼·콘텐츠 하나의 매출 행을 찾는 쿼리를, 복합 인덱스가 있을 때와 없을 때 `EXPLAIN ANALYZE`로 비교한 기록입니다.

- 측정일: 2026-11-04
- 환경: PostgreSQL 16.15 (Docker 컨테이너, GitHub Codespaces)
- 인덱스: `idx_sales_platform_content ON sales_raw (platform_id, content_id)`

## 실행한 쿼리

```sql
EXPLAIN ANALYZE
SELECT * FROM sales_raw WHERE platform_id = 5 AND content_id = 100;
```

## 1. 인덱스 있음

```
 Bitmap Heap Scan on sales_raw  (cost=4.42..48.70 rows=12 width=31) (actual time=0.025..0.042 rows=12 loops=1)
   Recheck Cond: ((platform_id = 5) AND (content_id = 100))
   Heap Blocks: exact=12
   ->  Bitmap Index Scan on idx_sales_platform_content  (cost=0.00..4.41 rows=12 width=0) (actual time=0.018..0.018 rows=12 loops=1)
         Index Cond: ((platform_id = 5) AND (content_id = 100))
 Planning Time: 0.473 ms
 Execution Time: 0.066 ms
(7 rows)
```

## 2. 인덱스 없음

운영 DB가 아닌 개인 환경이므로, 트랜잭션 안에서 인덱스를 지우고 측정한 뒤 되돌렸습니다.

```sql
BEGIN;
DROP INDEX idx_sales_platform_content;
EXPLAIN ANALYZE
SELECT * FROM sales_raw WHERE platform_id = 5 AND content_id = 100;
ROLLBACK;
\d sales_raw   -- Indexes에 idx_sales_platform_content가 돌아온 것 확인
```

```
 Seq Scan on sales_raw  (cost=0.00..2977.00 rows=12 width=31) (actual time=0.140..8.200 rows=12 loops=1)
   Filter: ((platform_id = 5) AND (content_id = 100))
   Rows Removed by Filter: 130188
 Planning Time: 0.081 ms
 Execution Time: 8.218 ms
(5 rows)
```

## 요약

| 항목 | 인덱스 있음 | 인덱스 없음 |
|---|---|---|
| 접근 방식 | Bitmap Index Scan → Bitmap Heap Scan | Seq Scan |
| 읽고 버린 행 | 0 | 130,188 |
| 결과 행 | 12 | 12 |
| Execution Time | **0.066 ms** | **8.218 ms** |

같은 12행을 찾는 데 인덱스가 없으면 테이블 전체를 읽고 130,188행을 버립니다. 인덱스가 있으면 해당 행이 있는 12개 페이지만 읽습니다(`Heap Blocks: exact=12`). 실행 시간은 약 124배 차이입니다.

플래너의 예상 행 수(`rows=12`)와 실제 행 수(`rows=12`)가 일치합니다. 적재 후 `ANALYZE`로 통계를 갱신했기 때문입니다(load.sql).

## 캐시 상태에 따른 차이

위 결과는 같은 쿼리를 두 번씩 실행한 것 중 두 번째 값입니다. 컨테이너를 막 켠 직후의 첫 실행은 데이터를 디스크에서 읽어 훨씬 느렸습니다.

| 항목 | 인덱스 있음 | 인덱스 없음 |
|---|---|---|
| 첫 실행 Execution Time | 311.479 ms | 533.522 ms |
| 두 번째 Execution Time | 0.066 ms | 8.218 ms |

첫 실행에서 인덱스를 찾는 단계(Bitmap Index Scan)는 0.961 ms였고, 시간 대부분은 실제 행을 디스크에서 가져오는 단계에서 걸렸습니다. 그래서 비교는 양쪽 모두 버퍼 캐시에 데이터가 올라온 상태에서 했습니다.

## 참고

README의 수치(11.885 ms → 0.067 ms)는 2026-11-01 첫 측정값입니다. 실행 시간은 측정할 때마다 조금씩 다르지만, 접근 방식과 버린 행 수(130,188)는 같습니다.
