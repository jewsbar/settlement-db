import csv
import random
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

random.seed(42)  # 씨앗 번호 고정: 몇 번을 돌려도 같은 데이터가 나옴

# ---------- 1. platform (31건) ----------
COUNTRIES = ["KR", "US", "JP", "CN", "TW", "TH", "VN", "ID"]
FORMATS = ["csv", "xlsx", "json"]

platforms = []
for i in range(1, 32):  # 1부터 31까지 (32는 포함 안 됨)
    platforms.append([
        i,                          # platform_id
        f"Platform_{i:02d}",        # platform_name
        random.choice(COUNTRIES),   # country
        random.choice(FORMATS),     # file_format
    ])

with open("platform.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["platform_id", "platform_name", "country", "file_format"])
    writer.writerows(platforms)

print(f"platform: {len(platforms)}건")

# ---------- 2. content (350건) ----------
contents = []
for i in range(1, 351):  # 1부터 350까지
    release = date(2024, 1, 1) + timedelta(days=random.randint(0, 365))
    contents.append([
        i,                                    # content_id
        f"Track_{i:04d}",                     # title
        f"Artist_{random.randint(1, 80):03d}", # artist
        release.isoformat(),                  # release_date (2024-03-01 형태)
    ])

with open("content.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["content_id", "title", "artist", "release_date"])
    writer.writerows(contents)

print(f"content: {len(contents)}건")
# ---------- 3. contract (31 × 350 = 10,850건) ----------
contracts = []
contract_lookup = {}  # (플랫폼, 곡) → (계약번호, 요율)  = 정산할 때 쓸 VLOOKUP 표
contract_id = 1
for p in platforms:
    for c in contents:
        rate = Decimal(random.randint(5000, 8000)) / 100  # 50.00 ~ 80.00
        contracts.append([contract_id, p[0], c[0], rate, c[3]])  # 계약 시작일 = 발매일
        contract_lookup[(p[0], c[0])] = (contract_id, rate)
        contract_id += 1

with open("contract.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["contract_id", "platform_id", "content_id", "rate", "start_date"])
    writer.writerows(contracts)

print(f"contract: {len(contracts)}건")

# ---------- 4. sales_raw (31 × 350 × 12개월 = 130,200건) ----------
# 플랫폼마다 재생 1회당 단가가 다름: 0.30 ~ 8.00원
unit_price = {p[0]: Decimal(random.randint(30, 800)) / 100 for p in platforms}

sales = []
sales_id = 1
for month in range(1, 13):
    sales_month = date(2025, month, 1).isoformat()  # 매월 1일로 저장
    for p in platforms:
        for c in contents:
            play_count = random.randint(10, 5000)
            amount = (play_count * unit_price[p[0]]).quantize(Decimal("0.01"))
            sales.append([sales_id, p[0], c[0], sales_month, play_count, amount, "KRW"])
            sales_id += 1

with open("sales_raw.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["sales_id", "platform_id", "content_id", "sales_month",
                     "play_count", "amount", "currency"])
    writer.writerows(sales)

print(f"sales_raw: {len(sales)}건")
# ---------- 5. settlement (매출의 약 98%만 정산, 약 2%는 미정산) ----------
settlements = []
settlement_id = 1
unsettled = 0
for s in sales:
    if random.random() < 0.02:  # 약 2%는 일부러 정산하지 않음 = 미정산
        unsettled += 1
        continue
    contract_id, rate = contract_lookup[(s[1], s[2])]  # (플랫폼, 곡)으로 계약 찾기
    settled_amount = (s[5] * rate / 100).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    sm = date.fromisoformat(s[3])
    pay_day = date(sm.year + sm.month // 12, sm.month % 12 + 1, 10)  # 다음 달 10일 정산
    settlements.append([settlement_id, s[0], contract_id, rate, settled_amount,
                        f"{pay_day} 09:00:00"])
    settlement_id += 1

with open("settlement.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["settlement_id", "sales_id", "contract_id", "applied_rate",
                     "settled_amount", "settled_at"])
    writer.writerows(settlements)

print(f"settlement: {len(settlements)}건")
print(f"미정산: {unsettled}건")