# 꼬맨틀 — 단어 유사도 추측 게임

이 레포지터리는 Johannes Gätjen의 [Semantlich](http://semantlich.johannesgaetjen.de/)
([소스코드](https://github.com/gaetjen/semantle-de))를 포크하여,
한국어로 플레이할 수 있도록 수정한 것입니다.

## 빠른 시작

처음 한 번은 대용량 데이터 다운로드와 전처리가 필요합니다.
최소 15GB 이상의 여유 디스크 공간이 필요합니다.

Docker:

```bash
git clone <repo-url>
cd semantle-ko
./scripts/setup-data.sh
docker compose up
```

로컬 Python:

```bash
git clone <repo-url>
cd semantle-ko
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
./scripts/setup-data.sh --local
gunicorn semantle:app --bind 0.0.0.0:8899
```

서버가 올라오면 브라우저에서 `http://localhost:8899`로 접속할 수 있습니다.

## setup-data.sh

필요한 경우:

```bash
./scripts/setup-data.sh --docker
./scripts/setup-data.sh --local
./scripts/setup-data.sh --regenerate-secrets
```
