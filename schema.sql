-- =========================================================
-- settlement-db : 콘텐츠 정산 데이터 스키마 (PostgreSQL 16)
-- 통화는 KRW 단일. 환율 환산은 범위에서 제외.
-- 생성 순서 = 참조 순서 (참조당하는 테이블이 먼저)
-- =========================================================

-- ---------- 기준 정보 ----------

-- 유통 플랫폼
CREATE TABLE platform (
  platform_id   SERIAL PRIMARY KEY,
  platform_name TEXT NOT NULL UNIQUE,      -- 같은 플랫폼 중복 등록 방지
  country       TEXT NOT NULL,
  file_format   TEXT NOT NULL              -- 정산서 파일 형식 (csv, xlsx, json 등)
);

-- 콘텐츠(곡)
CREATE TABLE content (
  content_id   SERIAL PRIMARY KEY,
  title        TEXT NOT NULL,              -- 동명곡이 있을 수 있어 UNIQUE 걸지 않음
  artist       TEXT NOT NULL,
  release_date DATE NOT NULL               -- DATE 타입이 잘못된 날짜(13월 등)를 거부
);

-- 계약: 어느 플랫폼에서 어느 콘텐츠를 몇 % 요율로
CREATE TABLE contract (
  contract_id SERIAL PRIMARY KEY,
  platform_id INTEGER NOT NULL REFERENCES platform(platform_id),
  content_id  INTEGER NOT NULL REFERENCES content(content_id),
  rate        NUMERIC(5,2) NOT NULL,       -- 정산 요율(%), 예: 70.00
  start_date  DATE NOT NULL
);

-- ---------- 거래 ----------

-- 플랫폼에서 받은 매출 원본 (받은 그대로 보관, 수정하지 않음)
CREATE TABLE sales_raw (
  sales_id    SERIAL PRIMARY KEY,
  platform_id INTEGER NOT NULL REFERENCES platform(platform_id),
  content_id  INTEGER NOT NULL REFERENCES content(content_id),
  sales_month DATE NOT NULL,               -- 정산월, 매월 1일로 저장 (예: 2024-03-01)
  play_count  INTEGER NOT NULL,
  amount      NUMERIC(14,2) NOT NULL,      -- 소수점 금액 대응
  currency    TEXT NOT NULL DEFAULT 'KRW'
);

-- 정산 결과
CREATE TABLE settlement (
  settlement_id  SERIAL PRIMARY KEY,
  sales_id       INTEGER NOT NULL UNIQUE REFERENCES sales_raw(sales_id),  -- 매출 1건은 1번만 정산
  contract_id    INTEGER NOT NULL REFERENCES contract(contract_id),
  applied_rate   NUMERIC(5,2) NOT NULL,    -- 정산 당시 적용 요율 (계약 요율 변경에 대비해 기록)
  settled_amount NUMERIC(14,2) NOT NULL,
  settled_at     TIMESTAMP NOT NULL DEFAULT now()
);

-- 미정산 매출 = sales_raw에는 있고 settlement에는 없는 행 (4단계에서 조회)