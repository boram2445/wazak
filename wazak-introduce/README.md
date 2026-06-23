# Wazak Introduce

정적 랜딩 페이지 샘플입니다.

## 로컬에서 보기

`index.html`을 브라우저로 열면 됩니다.

```sh
open wazak-introduce/index.html
```

## 다운로드 파일 갱신

앱을 다시 패키징한 뒤 zip을 복사하세요.

```sh
./scripts/package-app.sh
cp dist/Wazak.zip wazak-introduce/downloads/Wazak.zip
```

Vercel 같은 정적 호스팅에 올릴 때는 `wazak-introduce/` 폴더를 프로젝트 루트로 배포하면 됩니다.
