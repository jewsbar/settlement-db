# 백업과 복구 검증

`pg_dump`로 전체 백업을 받고, 원본과 다른 DB(`settlement_restore`)에 복구한 뒤, 원본과 복구본에서 같은 대조 쿼리를 실행해 7개 값이 일치하는지 확인한 기록입니다.

- 측정일: 2026-11-04
- 환경: PostgreSQL 16.15 (Docker 컨테이너 `juice-db`, GitHub Codespaces)
- 원본 DB: `settlement` / 복구 DB: `settlement_restore`

## 1. 백업

```bash
time docker exec juice-db pg_dump -U postgres -d settlement -f /tmp/backup.sql
docker exec juice-db ls -lh /tmp/backup.sql
```

```
real    0m1.175s
user    0m0.021s
sys     0m0.018s

-rw-r--r-- 1 root root 12M Nov  4 12:53 /tmp/backup.sql
```

## 2. 복구할 빈 DB 준비

복구는 원본 위가 아니라 별도 DB에 합니다. 원본을 건드리지 않고, 대조가 끝난 뒤에 쓸 수 있는지 판단하기 위해서입니다.

```bash
docker exec juice-db dropdb -U postgres settlement_restore
docker exec juice-db createdb -U postgres settlement_restore
```

## 3. 복구

```bash
time docker exec juice-db psql -q -U postgres -d settlement_restore -v ON_ERROR_STOP=1 -f /tmp/backup.sql
echo $?
```

```
real    0m1.434s
user    0m0.024s
sys     0m0.015s

0
```

- `-v ON_ERROR_STOP=1`: 오류가 하나라도 나면 즉시 멈춥니다. 이 옵션이 없으면 psql은 오류를 건너뛰고 끝까지 실행해서, 일부만 복구된 DB가 성공처럼 보일 수 있습니다.
- 종료 코드 `0`: 오류 없이 끝까지 실행됐다는 뜻입니다.
- 실행 중 출력된 `setval` 결과는 시퀀스(다음에 발급할 id)가 원본의 최대 id로 함께 복원된 것입니다.

## 4. 원본과 대조

두 DB에서 같은 쿼리를 실행했습니다. `\x on`은 결과를 세로로 보여 주는 psql 설정입니다.

```sql
\x on
SELECT
  (SELECT COUNT(*) FROM platform) AS platform,
  (SELECT COUNT(*) FROM content) AS content,
  (SELECT COUNT(*) FROM contract) AS contract,
  (SELECT COUNT(*) FROM sales_raw) AS sales_raw,
  (SELECT COUNT(*) FROM settlement) AS settlement,
  (SELECT SUM(amount) FROM sales_raw) AS sales_total,
  (SELECT SUM(settled_amount) FROM settlement) AS settled_total;
```

원본 `settlement`:

```
-[ RECORD 1 ]-+--------------
platform      | 31
content       | 350
contract      | 10850
sales_raw     | 130200
settlement    | 127512
sales_total   | 1557899323.33
settled_total | 994972671.14
```

복구본 `settlement_restore` (`\c settlement_restore`로 접속을 바꾼 뒤 같은 쿼리):

```
-[ RECORD 1 ]-+--------------
platform      | 31
content       | 350
contract      | 10850
sales_raw     | 130200
settlement    | 127512
sales_total   | 1557899323.33
settled_total | 994972671.14
```

## 요약

| 항목 | 원본 | 복구본 | 일치 |
|---|---|---|---|
| platform 건수 | 31 | 31 | ✅ |
| content 건수 | 350 | 350 | ✅ |
| contract 건수 | 10,850 | 10,850 | ✅ |
| sales_raw 건수 | 130,200 | 130,200 | ✅ |
| settlement 건수 | 127,512 | 127,512 | ✅ |
| 매출 합계 | 1,557,899,323.33 | 1,557,899,323.33 | ✅ |
| 정산 합계 | 994,972,671.14 | 994,972,671.14 | ✅ |

| 단계 | 결과 |
|---|---|
| 백업 (`pg_dump`) | 12 MB, 1.175초 |
| 복구 (`ON_ERROR_STOP=1`) | 1.434초, 종료 코드 0 |
| 대조 | 7개 값 모두 일치 |

건수만 보면 행이 들어갔는지만 알 수 있고, 금액 합계까지 맞춰야 값이 바뀌지 않고 그대로 옮겨졌는지 확인할 수 있습니다.

## 참고

- README의 수치(12 MB, 백업 0.9초, 복구 1.8초)는 2026-11-01 첫 측정값입니다. 시간은 측정할 때마다 조금씩 다르고, 파일 크기와 대조 값은 같습니다.
- 측정 시간에는 `docker exec` 자체의 시간도 포함됩니다.
- `pg_dump`는 백업을 받은 시점의 논리 백업입니다. 그 이후 변경분은 담기지 않으므로, 운영 환경에서는 물리 백업(`pg_basebackup`)과 WAL 아카이브를 이용한 시점 복구(PITR)를 함께 씁니다.
