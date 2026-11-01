# settlement-db

콘텐츠 유통사의 다중 플랫폼 정산 구조를 PostgreSQL로 옮긴 개인 프로젝트입니다.
실무에서 엑셀로 관리하던 정산 데이터를 정규화된 테이블로 설계하고, 대량 적재 · 조회 · 성능 개선 · 잠금 분석 · 백업/복구 검증까지 직접 수행했습니다.

> 회사 데이터는 사용하지 않았습니다. 실무 정산 구조를 본뜬 **합성 데이터**를 직접 생성했습니다.

## 환경

- PostgreSQL 16.15 (Docker 컨테이너)
- GitHub Codespaces (Linux)
- Python 3 (데이터 생성)

## 스키마

기준 정보 테이블 3개와 거래 테이블 2개로 나눴습니다. 원본 매출(sales_raw)과 정산 결과(settlement)를 분리해 원본은 수정하지 않고 재정산과 추적이 가능하도록 했습니다.

```
platform ─┐
          ├─→ contract ─────────┐
content ──┤                     ├─→ settlement
          └─→ sales_raw ────────┘
```

주요 설계 결정

- 금액·요율은 `NUMERIC`(오차 없는 소수)로 저장
- `settlement.sales_id`에 `UNIQUE` 제약 → 매출 1건은 한 번만 정산
- `settlement.applied_rate`에 적용 당시 요율을 보관 → 계약 요율이 바뀌어도 이력 유지
- 미정산 = `sales_raw`에는 있고 `settlement`에는 없는 행

## 파일

| 파일 | 내용 |
|---|---|
| `schema.sql` | V1: 5개 테이블 생성 |
| `generate.py` | 합성 데이터 생성 (seed 고정, 재현 가능) |
| `V2__add_sales_index.sql` | V2: 조회 성능 개선용 복합 인덱스 |

## 데이터

| 테이블 | 건수 |
|---|---|
| platform | 31 |
| content | 350 |
| contract | 10,850 |
| sales_raw | 130,200 (2025년 12개월) |
| settlement | 127,512 |
| 미정산 (의도적으로 생성) | 2,688 |

- 통화는 KRW로 통일 (환율 환산은 범위에서 제외)
- 정산 금액 반올림을 PostgreSQL `ROUND`와 같은 방식(ROUND_HALF_UP)으로 맞춤

## 수행 내용과 결과

### 1. 대량 적재와 건수 검증

- `COPY`로 참조 순서(platform, content → contract → sales_raw → settlement)대로 적재
- csv 행 수(`wc -l`)와 테이블 건수(`count(*)`)를 대조해 누락 없음 확인
- 적재 데이터를 csv로 다시 추출해 원본과 `diff` 비교 → 차이 0
- id를 직접 적재한 뒤 시퀀스가 1에 머물러 `duplicate key` 오류가 나는 것을 재현하고, `setval`로 실제 최대 id에 동기화

### 2. 조회 쿼리

- 미정산 조회: `NOT EXISTS`로 2,688건 → 생성 시점 정답과 일치
- 미정산 내역: `JOIN`으로 플랫폼명·곡명을 붙인 목록
- 월별 정산 현황: `LEFT JOIN` + `GROUP BY`로 월별 매출/정산 건수·금액 집계

### 3. 실행계획과 인덱스

PostgreSQL은 외래키 칸에 인덱스를 자동으로 만들지 않습니다. 플랫폼×곡 조회의 실행계획을 확인하고 복합 인덱스를 추가했습니다.

| | 실행계획 | 읽고 버린 행 | Execution Time |
|---|---|---|---|
| 인덱스 전 | Seq Scan | 130,188 | 11.885 ms |
| 인덱스 후 | Bitmap Index Scan | 0 | 0.067 ms |

```sql
CREATE INDEX idx_sales_platform_content ON sales_raw (platform_id, content_id);
```

### 4. 트랜잭션과 잠금

두 세션에서 같은 정산 행을 동시에 수정하는 상황을 재현했습니다.

- 커밋 전 변경은 다른 세션에 보이지 않음을 확인
- `pg_stat_activity`와 `pg_blocking_pids()`로 대기 중인 세션과 막고 있는 세션을 식별
- 선행 트랜잭션을 `ROLLBACK`하자 대기 세션이 즉시 진행되는 것을 확인

### 5. 백업과 복구 검증

| 단계 | 결과 |
|---|---|
| `pg_dump` 전체 백업 | 12 MB, 0.9초 |
| 별도 DB(`settlement_restore`)에 복구 (`ON_ERROR_STOP=1`) | 1.8초, 오류 없음 |
| 원본과 대조 (5개 테이블 건수 + 매출·정산 금액 합계) | 7개 값 모두 일치 |

## 재현 방법

```bash
docker run --name juice-db -e POSTGRES_PASSWORD=<password> -e POSTGRES_DB=settlement -d postgres:16
python3 generate.py
docker cp . juice-db:/tmp/data
docker exec -it juice-db psql -U postgres -d settlement -f /tmp/data/schema.sql
# 이후 COPY로 적재 (위 1번 참고)
```

수치는 기본 GitHub Codespace 환경 기준이며 실행 환경에 따라 달라질 수 있습니다.# settlement-db